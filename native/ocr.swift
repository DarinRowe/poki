import Foundation
import Vision
import ImageIO

func recognize(_ image: CGImage, request: VNRecognizeTextRequest) throws -> [[String: Any]] {
    try VNImageRequestHandler(cgImage: image).perform([request])
    return (request.results ?? []).compactMap { observation in
        guard let text = observation.topCandidates(1).first else { return nil }
        let rect = observation.boundingBox
        return [
            "text": text.string,
            "confidence": text.confidence,
            "x": rect.minX * Double(image.width),
            "y": (1 - rect.maxY) * Double(image.height),
            "width": rect.width * Double(image.width),
            "height": rect.height * Double(image.height)
        ]
    }
}

func makeRequest() -> VNRecognizeTextRequest {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = false
    request.automaticallyDetectsLanguage = true
    return request
}

final class WorkerOutput: @unchecked Sendable {
    private let lock = NSLock()
    func send(_ value: [String: Any]) {
        guard var data = try? JSONSerialization.data(withJSONObject: value) else { return }
        data.append(10)
        lock.lock()
        defer { lock.unlock() }
        FileHandle.standardOutput.write(data)
    }
}

func worker() {
    let parent = getppid()
    guard parent > 1 else { return }
    // Vision runs synchronously, so monitor the parent independently of recognition.
    let watchdog = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
    watchdog.schedule(deadline: .now() + .seconds(1), repeating: .seconds(1))
    watchdog.setEventHandler { if getppid() != parent { _exit(0) } }
    watchdog.resume()
    defer { watchdog.cancel() }

    let output = WorkerOutput()
    let pressure = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .global(qos: .utility))
    pressure.setEventHandler { [weak pressure] in
        guard let pressure else { return }
        output.send(["pressure": pressure.data.contains(.critical) ? "critical" : "warning"])
    }
    pressure.resume()
    defer { pressure.cancel() }

    let request = makeRequest()
    output.send(["ready": true])
    while let line = readLine() {
        autoreleasepool {
            guard let job = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let id = job["id"] as? Int, let encoded = job["image"] as? String else { return }
            guard let data = Data(base64Encoded: encoded),
                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                output.send(["id": id, "error": true])
                return
            }
            do {
                let rows = try recognize(image, request: request)
                output.send(["id": id, "rows": rows])
            } catch {
                output.send(["id": id, "error": true])
            }
        }
    }
}

if CommandLine.arguments == [CommandLine.arguments[0], "--worker"] {
    worker()
} else {
    guard CommandLine.arguments.count == 2,
          let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        fputs("Expected a readable image path\n", stderr)
        exit(1)
    }
    do {
        let rows = try recognize(image, request: makeRequest())
        FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys]))
    } catch {
        fputs("OCR failed: \(error)\n", stderr)
        exit(1)
    }
}
