import Foundation
import PokiCore
import UIKit

/// A persistent banner-free client through PokiLauncher's paired CoreDevice services. Requests are
/// serial at both layers, like WDA and the desktop bridge, and the expensive tunnel/media handshake
/// is paid once per active transport rather than once per action.
private final class NativeServicesBridge: @unchecked Sendable {
    final class Box: @unchecked Sendable {
        let continuation: CheckedContinuation<[String: Any], Error>
        init(_ continuation: CheckedContinuation<[String: Any], Error>) { self.continuation = continuation }
        func finish(_ value: [String: Any]) {
            if value["ok"] as? Bool == true, let answer = value["value"] as? [String: Any] { continuation.resume(returning: answer) }
            else { continuation.resume(throwing: NSError(domain: "PokiNativeServices", code: 1, userInfo: [NSLocalizedDescriptionKey: value["error"] as? String ?? "native services returned no result"])) }
        }
    }

    private let handle: OpaquePointer?

    init() {
        let config: [String: Any] = [
            "device_address": "10.7.0.1", "pairing_file": AppFiles.pairingFile.path,
            "host_name": "Poki",
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: config) else { handle = nil; return }
        let text = String(decoding: data, as: UTF8.self)
        handle = text.withCString { poki_native_client_new($0) }
    }

    deinit { if let handle { poki_native_client_free(handle) } }

    func call(_ request: [String: Any]) async throws -> [String: Any] {
        guard let handle else { throw NSError(domain: "PokiNativeServices", code: 2, userInfo: [NSLocalizedDescriptionKey: "native services could not be created"]) }
        let data = try JSONSerialization.data(withJSONObject: request)
        let text = String(decoding: data, as: UTF8.self)
        return try await withCheckedThrowingContinuation { continuation in
            let box = Box(continuation)
            let retained = Unmanaged.passRetained(box)
            let queued = text.withCString { json in
                poki_native_client_call(handle, json, { context, result in
                    guard let context, let result else { return }
                    let box = Unmanaged<Box>.fromOpaque(context).takeRetainedValue()
                    let data = Data(String(cString: result).utf8)
                    let value = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                    box.finish(value ?? ["ok": false, "error": "native services returned invalid JSON"])
                }, retained.toOpaque())
            }
            guard queued == 0 else {
                retained.release()
                continuation.resume(throwing: NSError(domain: "PokiNativeServices", code: 2, userInfo: [NSLocalizedDescriptionKey: "native services could not queue the request"]))
                return
            }
        }
    }
}

/// Experimental WDA-shaped transport backed by accessibility, DVT screenshots and CoreDevice HID.
/// It never opens an XCTest session, so iOS does not show the Automation Running banner.
final class NativeServicesWDA: HTTPTransport, @unchecked Sendable {
    private struct Tree: @unchecked Sendable { var value: [String: Any] }
    private let screen: CGSize
    /// Reads/launches, screenshots, and HID each keep their own tunnel. PokiCore reads the tree and
    /// picture together; separate lanes preserve the production path's parallel read latency.
    private let native = NativeServicesBridge()
    private let pictures = NativeServicesBridge()
    private let input = NativeServicesBridge()
    private let queue = DispatchQueue(label: "poki.native-services.wda")
    private var focused: [String: Any]?
    private var cachedTree: (at: Date, tree: Tree)?
    private var treeTask: Task<Tree, Error>?
    private var inputWarming = false

    init(screen: CGSize) { self.screen = screen }

    /// Drops all paired tunnels without destroying the transport. The next call reconnects them,
    /// which gives PokiCore's existing restart policy the same clean boundary as the runner path.
    func reset() async {
        async let state: [String: Any]? = try? native.call(["op": "reset"])
        async let picture: [String: Any]? = try? pictures.call(["op": "reset"])
        async let controls: [String: Any]? = try? input.call(["op": "reset"])
        _ = await (state, picture, controls)
        queue.sync {
            focused = nil
            cachedTree = nil
            treeTask = nil
            inputWarming = false
        }
    }

    func send(method: String, url: URL, body: Data?, timeout: Double) async throws -> (status: Int, body: Data) {
        var parts = url.path.split(separator: "/").map(String.init)
        if parts.first == "session", parts.count >= 2 { parts.removeFirst(2) }
        var element: String?
        if parts.first == "element", parts.count >= 3 { element = parts[1]; parts.remove(at: 1) }
        let path = parts.isEmpty ? "/session" : "/" + parts.joined(separator: "/")
        let key = "\(method) \(path)"
        let input = body.flatMap { try? JSON.parse($0) }
        let sourceIsXML = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "format" })?.value?.lowercased() == "xml"
        let started = Date()
        defer {
            let took = Int(Date().timeIntervalSince(started) * 1000)
            if took > 5 { NSLog("%@", "PokiNativeServices timing: \(key) \(took) ms") }
        }
        do {
            let value = try await answer(key, body: input, element: element, sourceIsXML: sourceIsXML)
            return (200, (["value": value] as JSON).data())
        } catch {
            return (500, (["value": ["error": .string("unknown error"), "message": .string(error.localizedDescription)]] as JSON).data())
        }
    }

    private func answer(_ key: String, body: JSON?, element: String?, sourceIsXML: Bool) async throws -> JSON {
        switch key {
        case "GET /status": return ["ready": true, "message": "experimental native services"]
        case "POST /session": return ["sessionId": "native-services"]
        case "DELETE /session", "POST /appium/settings": return .null
        case "GET /wda/screen": return ["screenSize": ["width": .number(screen.width), "height": .number(screen.height)]]
        case "GET /wda/locked":
            let tree = try await readTree()
            return .bool(Self.looksLocked(tree))
        case "GET /source":
            let tree = try await readTree()
            return .string(sourceIsXML ? Self.sourceXML(tree) : Self.sourceJSON(tree))
        case "GET /wda/activeAppInfo":
            let tree = try await readTree()
            let app = tree["foreground_app"] as? [String: Any] ?? [:]
            return ["bundleId": .string(app["bundle_id"] as? String ?? ""), "name": .string(app["name"] as? String ?? ""), "pid": .number(Double(app["pid"] as? Int ?? 0))]
        case "GET /screenshot":
            let result = try await pictures.call(["op": "screenshot"])
            guard let base64 = result["base64"] as? String else { throw failure("the screenshot service returned no image") }
            return .string(base64)
        case "GET /element/active":
            let tree = try await readTree()
            let elements = tree["elements"] as? [[String: Any]] ?? []
            guard let field = elements.first(where: { $0["focused"] as? Bool == true }) else { throw failure("no element has keyboard focus") }
            queue.sync { focused = field }
            return ["ELEMENT": "focused"]
        case "GET /element/attribute/value":
            guard element == "focused", let field = queue.sync(execute: { focused }) else { throw failure("the focused element is gone") }
            return field["value"].map(Self.json) ?? .null
        case "GET /element/attribute/placeholderValue":
            guard element == "focused", let field = queue.sync(execute: { focused }) else { throw failure("the focused element is gone") }
            return field["placeholder"].map(Self.json) ?? .null
        case "GET /element/rect":
            guard element == "focused", let field = queue.sync(execute: { focused }), let frame = field["frame"] as? [String: Any] else { throw failure("the focused element is gone") }
            return Self.json(frame)
        case "POST /wda/tap":
            try await callPoint("tap", body: body); return .null
        case "POST /wda/touchAndHold":
            let point = try Self.point(body, x: "x", y: "y")
            _ = try await input.call(["op": "long_press", "x": point.x, "y": point.y, "duration_ms": Int((body?["duration"]?.double ?? 1) * 1000)])
            return .null
        case "POST /wda/pressAndDragWithVelocity", "POST /wda/dragfromtoforduration":
            let from = try Self.point(body, x: "fromX", y: "fromY"), to = try Self.point(body, x: "toX", y: "toY")
            let duration = key.contains("pressAndDrag") ? max(80, Int(hypot(Double(to.x - from.x), Double(to.y - from.y)) / max(1, body?["velocity"]?.double ?? 1000) * 1000)) : 300
            _ = try await input.call(["op": "drag", "x1": from.x, "y1": from.y, "x2": to.x, "y2": to.y, "duration_ms": duration, "hold_ms": Int((body?["duration"]?.double ?? body?["pressDuration"]?.double ?? 0) * 1000), "end_hold_ms": Int((body?["holdDuration"]?.double ?? 0) * 1000)])
            return .null
        case "POST /actions":
            try await actions(body); return .null
        case "POST /wda/keys":
            let text = (body?["value"]?.array ?? []).compactMap(\.string).joined()
            guard !text.isEmpty else { throw failure("no keys given") }
            var request: [String: Any]
            if Self.hidCanType(text) {
                request = ["op": "type_keys", "text": text]
                if let frequency = body?["frequency"]?.int { request["frequency"] = frequency }
            } else {
                let deletes = text.prefix { $0 == "\u{8}" }.count
                var pasted = String(text.dropFirst(deletes))
                let submit = pasted.last == "\n"
                if submit { pasted.removeLast() }
                request = ["op": "type_text", "text": pasted, "clear": deletes > 0, "submit": submit]
            }
            _ = try await input.call(request)
            return .null
        case "POST /wda/homescreen": _ = try await input.call(["op": "button", "button": "home"]); return .null
        case "POST /wda/lock": _ = try await input.call(["op": "button", "button": "lock"]); return .null
        case "POST /wda/pressButton": _ = try await input.call(["op": "button", "button": body?["name"]?.string ?? ""]); return .null
        case "POST /wda/apps/launch": try await launch(body, terminate: true); return .null
        case "POST /wda/apps/activate": try await launch(body, terminate: false); return .null
        case "POST /wda/apps/terminate":
            guard let bundle = body?["bundleId"]?.string, !bundle.isEmpty else { throw failure("bundleId is needed") }
            _ = try await native.call(["op": "terminate_app", "bundle_id": bundle]); return .null
        case "POST /wda/getPasteboard":
            let result = try await native.call(["op": "pasteboard_get"])
            let text = result["text"] as? String ?? ""
            return .string(Data(text.utf8).base64EncodedString())
        case "POST /wda/setPasteboard":
            guard let encoded = body?["content"]?.string, let data = Data(base64Encoded: encoded) else { throw failure("content must be base64 text") }
            _ = try await native.call(["op": "pasteboard_set", "text": String(decoding: data, as: UTF8.self)])
            return .null
        default: throw failure("\(key) is not implemented in the experimental native-services path")
        }
    }

    private func callPoint(_ op: String, body: JSON?) async throws {
        let point = try Self.point(body, x: "x", y: "y")
        _ = try await input.call(["op": op, "x": point.x, "y": point.y])
    }

    private func launch(_ body: JSON?, terminate: Bool) async throws {
        guard let bundle = body?["bundleId"]?.string, !bundle.isEmpty else { throw failure("bundleId is needed") }
        _ = try await native.call(["op": "launch_app", "bundle_id": bundle, "terminate_existing": terminate])
    }

    /// W3C actions are used by PokiCore only for a two-finger pinch. Reduce them to its centre,
    /// starting and ending distance; ordinary drags use the dedicated routes above.
    private func actions(_ body: JSON?) async throws {
        let sources = body?["actions"]?.array ?? []
        guard sources.count == 2 else { throw failure("the experiment supports two-finger W3C actions only") }
        func endpoints(_ source: JSON) -> ((Double, Double), (Double, Double), Int)? {
            let moves = (source["actions"]?.array ?? []).filter { $0["type"]?.string == "pointerMove" }
            guard let first = moves.first, let last = moves.last else { return nil }
            return ((first["x"]?.double ?? 0, first["y"]?.double ?? 0), (last["x"]?.double ?? 0, last["y"]?.double ?? 0), last["duration"]?.int ?? 500)
        }
        guard let a = endpoints(sources[0]), let b = endpoints(sources[1]) else { throw failure("the pinch has no pointer moves") }
        let centreX = (a.0.0 + b.0.0) / 2, centreY = (a.0.1 + b.0.1) / 2
        let start = hypot(a.0.0 - b.0.0, a.0.1 - b.0.1), end = hypot(a.1.0 - b.1.0, a.1.1 - b.1.1)
        _ = try await input.call(["op": "pinch", "x": Self.coordinate(centreX), "y": Self.coordinate(centreY), "start_distance": start, "end_distance": end, "duration_ms": max(a.2, b.2)])
    }

    /// Coalesces PokiCore's parallel source and foreground requests into the one accessibility read
    /// the Mac/Linux bridge already returns. The short cache never survives an action's 300 ms settle.
    private func readTree() async throws -> [String: Any] {
        let task: Task<Tree, Error> = queue.sync {
            if let cachedTree, Date().timeIntervalSince(cachedTree.at) < 0.15 {
                return Task { cachedTree.tree }
            }
            if let treeTask { return treeTask }
            let task = Task { Tree(value: try await native.call(["op": "ax_tree"])) }
            treeTask = task
            if !inputWarming {
                inputWarming = true
                Task { _ = try? await input.call(["op": "warm_input"]) }
            }
            return task
        }
        do {
            let tree = try await task.value
            queue.sync { cachedTree = (Date(), tree); treeTask = nil }
            return tree.value
        } catch {
            queue.sync { treeTask = nil }
            throw error
        }
    }

    private static func point(_ body: JSON?, x: String, y: String) throws -> (x: Int, y: Int) {
        guard let px = body?[x]?.double, let py = body?[y]?.double else { throw failure("\(x) and \(y) are needed") }
        return (coordinate(px), coordinate(py))
    }
    private static func coordinate(_ value: Double) -> Int { max(0, min(65_535, Int(value.rounded()))) }
    private static func hidCanType(_ text: String) -> Bool {
        text.unicodeScalars.allSatisfy { scalar in
            scalar.value == 8 || scalar.value == 9 || scalar.value == 10 || (32...126).contains(scalar.value)
        }
    }
    private static func looksLocked(_ tree: [String: Any]) -> Bool {
        let app = tree["foreground_app"] as? [String: Any]
        guard app?["bundle_id"] as? String == "com.apple.springboard" else { return false }
        let elements = tree["elements"] as? [[String: Any]] ?? []
        let words = elements.flatMap { [$0["identifier"], $0["label"], $0["placeholder"]] }
            .compactMap { $0 as? String }.joined(separator: " ").lowercased()
        // SpringBoard also owns Home, alerts and the app switcher. Only lock/passcode vocabulary (or
        // a secure field on SpringBoard) is treated as locked, so ordinary system prompts still work.
        return words.contains("unlock") || words.contains("passcode") || words.contains("locked")
            || elements.contains { ($0["role"] as? String) == "SecureTextField" }
    }
    private static func failure(_ text: String) -> NSError { NSError(domain: "PokiNativeServices", code: 3, userInfo: [NSLocalizedDescriptionKey: text]) }

    /// Turns the bridge's flat preorder accessibility records back into the JSON hierarchy PokiCore
    /// already consumes from WDA. Parent indices preserve containment and hit testing.
    private static func sourceJSON(_ tree: [String: Any]) -> String {
        let elements = tree["elements"] as? [[String: Any]] ?? []
        var nodes: [[String: Any]] = elements.map { element in
            let frame = element["frame"] as? [String: Any] ?? [:]
            return ["type": "XCUIElementType\(element["role"] as? String ?? "Other")", "name": element["identifier"] ?? element["label"] ?? "", "label": element["label"] ?? "", "value": element["value"] ?? "", "rect": frame, "children": []]
        }
        if nodes.isEmpty { return "{\"type\":\"XCUIElementTypeApplication\",\"children\":[]}" }
        for index in nodes.indices.reversed() {
            guard let parent = elements[index]["parent"] as? Int, nodes.indices.contains(parent) else { continue }
            var children = nodes[parent]["children"] as? [[String: Any]] ?? []
            children.insert(nodes[index], at: 0)
            nodes[parent]["children"] = children
        }
        let roots = elements.indices.filter { elements[$0]["parent"] is NSNull || elements[$0]["parent"] == nil }.map { nodes[$0] }
        let root: [String: Any] = roots.count == 1 ? roots[0] : ["type": "XCUIElementTypeApplication", "children": roots]
        let data = (try? JSONSerialization.data(withJSONObject: root)) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    /// PokiCore's production configuration asks WDA for XML. The native AX service returns the same
    /// fields as a flat preorder list, so preserve its parent relationships in WDA's XML shape too.
    private static func sourceXML(_ tree: [String: Any]) -> String {
        let elements = tree["elements"] as? [[String: Any]] ?? []
        var children: [Int: [Int]] = [:]
        var roots: [Int] = []
        for index in elements.indices {
            if let parent = elements[index]["parent"] as? Int, elements.indices.contains(parent) {
                children[parent, default: []].append(index)
            } else {
                roots.append(index)
            }
        }
        func escaped(_ value: Any?) -> String {
            guard let value, !(value is NSNull) else { return "" }
            return String(describing: value)
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
                .replacingOccurrences(of: "\"", with: "&quot;")
                .replacingOccurrences(of: "'", with: "&apos;")
        }
        func node(_ index: Int) -> String {
            let element = elements[index]
            let frame = element["frame"] as? [String: Any] ?? [:]
            let type = "XCUIElementType\(element["role"] as? String ?? "Other")"
            let attributes = [
                ("name", element["identifier"] ?? element["label"]),
                ("label", element["label"]), ("value", element["value"]),
                ("x", frame["x"]), ("y", frame["y"]),
                ("width", frame["width"]), ("height", frame["height"]),
            ].map { "\($0.0)=\"\(escaped($0.1))\"" }.joined(separator: " ")
            let nested = (children[index] ?? []).map(node).joined()
            return nested.isEmpty ? "<\(type) \(attributes)/>" : "<\(type) \(attributes)>\(nested)</\(type)>"
        }
        let content = roots.map(node).joined()
        return "<?xml version=\"1.0\" encoding=\"UTF-8\"?><AppiumAUT>\(content.isEmpty ? "<XCUIElementTypeApplication/>" : content)</AppiumAUT>"
    }

    private static func json(_ value: Any) -> JSON {
        switch value {
        case let value as String: .string(value)
        case let value as Bool: .bool(value)
        case let value as NSNumber: .number(value.doubleValue)
        case let value as [String: Any]: .object(value.mapValues(json))
        case let value as [Any]: .array(value.map(json))
        default: .null
        }
    }
}
