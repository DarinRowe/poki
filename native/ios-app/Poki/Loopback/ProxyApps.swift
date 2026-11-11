import Foundation
import UIKit

/// The proxy apps that can provide the 10.7.0.1 loopback, so users
/// keep their own VPN. Detected with canOpenURL (their schemes are listed in LSApplicationQueriesSchemes).
/// The module files live in deploy/proxy-modules/.
struct ProxyApp: Identifiable, Hashable {
    enum Install: Hashable { case url(URL), toggle(String), snippet(String) }
    let id: String
    let name: String
    let scheme: String
    let minimumVersion: String
    let install: Install
    let steps: [String]
    /// The setup comes from the app's own documentation (true), or from what users and other
    /// loopback tools report (false): the page says so, and the live check above the list is the proof.
    var documented = true
    /// What to check when the app is set up and the phone still does not answer, in the order to try.
    var troubleshooting: [String] = []

    var isInstalled: Bool {
        guard let url = URL(string: "\(scheme)://") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }
}

enum ProxyApps {
    /// Where the module files are served from: raw GitHub of the repository's main branch, which keeps
    /// these paths.
    static let modulesBase = URL(string: "https://raw.githubusercontent.com/JosssphZhou/poki/main/deploy/proxy-modules/")!

    static func encoded(_ url: URL) -> String {
        url.absoluteString.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? url.absoluteString
    }

    static let all: [ProxyApp] = [
        ProxyApp(id: "karing", name: "Karing", scheme: "karing", minimumVersion: "1.2.4.862",
                 install: .toggle("TUN > Loopback address > 10.7.0.1"),
                 steps: ["Open Karing's settings, then TUN.", "Set Loopback address (loopback_address) to 10.7.0.1, then reconnect Karing.", "Keep Karing connected. Choose External app in Poki and do not enable Poki's built-in connection."]),
        ProxyApp(id: "surge", name: "Surge", scheme: "surge", minimumVersion: "5.23.0",
                 install: .url(URL(string: "surge:///install-module?url=\(encoded(modulesBase.appendingPathComponent("poki-loopback.sgmodule")))")!),
                 steps: ["Tap Install Module, then confirm in Surge.", "Turn on the Poki Device Loopback module.", "Turn on Enhanced Mode (required for loopback)."]),
        ProxyApp(id: "loon", name: "Loon", scheme: "loon", minimumVersion: "3.5.3",
                 install: .url(URL(string: "loon://import?plugin=\(encoded(modulesBase.appendingPathComponent("poki-loopback.lpx")))")!),
                 steps: ["Tap Install Plugin, then confirm in Loon.", "Make sure the plugin and Loon VPN are turned on."]),
        ProxyApp(id: "shadowrocket", name: "Shadowrocket", scheme: "shadowrocket", minimumVersion: "",
                 install: .toggle("Settings › Other › Include route 10.7.0.1/32"),
                 steps: [
                    "Update Shadowrocket from the App Store. The switch came with version 2.2.91, and 2.2.93 and later are reported to work.",
                    "In Shadowrocket, open **Settings › Other** and turn on **Include Route 10.7.0.1/32**.",
                    "Disconnect Shadowrocket and connect it again on Wi-Fi. The switch only takes effect on a new connection.",
                    "Come back to Poki and keep Shadowrocket connected. The status below turns to Loopback Is On by itself.",
                 ],
                 documented: false,
                 troubleshooting: [
                    "**Reconnect after every change.** Turn Shadowrocket off and on again. A connection made before the switch was turned on does not carry the route.",
                    "**Start on Wi-Fi.** iOS refuses this loopback when the iPhone has only cellular. Once Poki is on, you can go back to cellular.",
                    "**Only one VPN at a time.** Turn off LocalDevVPN, StosVPN and Poki’s built-in connection. iOS runs one and the last one started wins.",
                    "**Leave Include All Networks and Force Routing off** in Shadowrocket’s settings while you test.",
                    "**Check your configuration’s excluded routes.** Many configurations keep 10.0.0.0/8 out of the tunnel (tun-excluded-routes). Edit the configuration, remove 10.0.0.0/8 from that line or try the default configuration, then reconnect.",
                    "**The switch must be the one in the app.** A module or a [General] line does not turn the route on.",
                    "**Pair again if the status says Loopback Is On but Poki cannot connect.** The route works then, and the pairing is what the phone refuses.",
                    "**Still Not On Yet on iOS 18?** Some iPhones on iOS 18.7 never get the route from Shadowrocket. Use LocalDevVPN there.",
                 ]),
        ProxyApp(id: "stash", name: "Stash", scheme: "stash", minimumVersion: "",
                 install: .snippet("tun:\n  loopback-address:\n    - 10.7.0.1"),
                 steps: ["Open Stash. If its TUN or override settings have a loopback or 10.7.0.1 option, turn it on.", "Otherwise add the lines below to an override (Settings › Overrides) and enable it.", "Reconnect Stash and keep it connected."],
                 documented: false),
        ProxyApp(id: "quantumult-x", name: "Quantumult X", scheme: "quantumult-x", minimumVersion: "",
                 install: .snippet("reflected_routes = 10.7.0.1/32"),
                 steps: ["Copy the line below.", "Add it to the [general] section of your Quantumult X profile and save.", "Reconnect Quantumult X and keep it connected."],
                 documented: false),
        ProxyApp(id: "clashmi", name: "Clash Mi", scheme: "clashmi", minimumVersion: "",
                 install: .snippet("tun:\n  loopback-address:\n    - 10.7.0.1"),
                 steps: ["Copy the lines below.", "Add them to the tun section of your Clash Mi profile, import it, then connect.", "Keep Clash Mi connected. Users report this works on iOS 26.3 and failed on 26.4. The check above tells."],
                 documented: false),
        ProxyApp(id: "sing-box", name: "sing-box", scheme: "sing-box", minimumVersion: "1.12.0",
                 install: .snippet("\"loopback_address\": [\"10.7.0.1\"]"),
                 steps: ["Copy the line below.", "Add it to the tun inbound in your sing-box profile, then reload the profile.", "Keep IPv6 out of the tun address list."]),
    ]
}
