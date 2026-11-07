# Poki for iPhone

One app for everything a user does on the phone: setup (Developer Mode, on-device pairing, UI
Automation, the loopback, the first-session passcode), starting and stopping a session, the Live
Activity with Approve/Deny for sensitive actions, the MCP address for each client (text, QR, copy),
and a Debug tab (the former Poki Probe). Native SwiftUI on the iOS 26 SDK with Liquid Glass.

The runner (WebDriverAgent, built by `.github/workflows/ios-runner.yml`) is a second bundle for v1;
`docs/single-bundle.md` explains why.

## Layout

| Path | What |
|---|---|
| `Poki/App` | App entry, tabs, Home, the app model (on/off, runner sleep and wake, events, approvals, pairing, setup steps) |
| `Poki/Setup` | Setup, one guided page with live checks |
| `Poki/Loopback` | Local VPN configuration and status, live developer-service checks, external VPN choices |
| `Poki/Activity` | Live Activity controller (state, steps, thumbnail in the App Group) |
| `Poki/Connect` | Relay identity (Ed25519 key, label, connector secrets in the keychain), MCP address with QR |
| `Poki/Runtime` | PokiCore and PokiLauncher glue, background keep-alive (location, then silent audio) |
| `Poki/Debug` | 10.7.0.1 checks, the background hold test, the Live Activity preview |
| `Shared` | Live Activity attributes and views, the Approve/Deny/Stop App Intents (app and widget) |
| `PokiWidgets` | The Live Activity widget |
| `PokiTunnel` | Local-only IPv4 TCP packet tunnel; no server, DNS or internet default route |

PokiCore (Swift, `native/ios/PokiCore`) and PokiLauncher (Rust with a C ABI, `native/launcher`) are described in `docs/ios-core.md`. Poki has no default relay: the person deploys their own (`deploy/cf-relay/DEPLOY.md`) and enters its address in the Connect tab.

## Build

GitHub Actions (`.github/workflows/ios-app.yml`) builds `Poki-unsigned.ipa` on demand and for
`ios-v*` release tags, runs it on the iOS Simulator and uploads a screenshot of every screen in light and
dark mode (artifact `simulator-smoke`, folder `shots`). Locally on a Mac with Xcode 26 or later:

```sh
native/ios-app/scripts/make-assets.sh
xcodegen generate --spec native/ios-app/project.yml
open native/ios-app/Poki.xcodeproj
```

`-pokiScreen home|setup|connect|debug|activity` opens that screen at launch.

## How it runs

- Poki stays on once turned on, and turns on again at launch. The runner, and with it iOS's
  automation banner, starts only when an agent asks. It stops after the idle time (default 60 s),
  from Stop on the Live Activity or in Poki, or when Poki is closed. The launcher ends the runner's
  process at once instead of leaving it up for about 30 s.
- Only Poki starts the runner. Opened by hand, Poki Runner starts no test (PokiRunnerHost,
  `native/ios-runner/host`) and sends the person to Poki.
- Known issue: while the runner runs, it answers on port 8100 to any device on the same network,
  with no credentials and without Poki's approvals (`native/ios-runner/README.md`). Turn Poki on only
  on networks you trust. A pairing code between Poki and the runner is the planned fix.
- The Live Activity starts from the foreground, because iOS does not allow it from the background:
  when Poki turns on, when pairing starts, and when a setup step opens Settings.

## Signing and entitlements

| Entitlement | Needed for | Notes |
|---|---|---|
| App Groups `group.nz.zheha.poki` | Live Activity thumbnail, approvals between widget and app | Signing tools rewrite group ids per Apple ID; that works as long as both targets get the same rewritten group. |

| Network Extensions `packet-tunnel-provider` | Built-in local connection | Required in both Poki and PokiTunnel, with a matching provisioning profile for each bundle. A wildcard profile is insufficient. |

The default `project.yml` builds Poki with its local VPN. Use signing that supports Network
Extensions (including properly provisioned paid-team development/ad-hoc distribution). Free Personal
Team signing cannot provision this capability. Re-signing must preserve the entitlement in both the
app and its extension. CI includes the generated entitlements in `Poki-signing.zip`.

For a team that does not own the default identifiers, set `POKI_BUNDLE_ID`, `POKI_APP_GROUP` and
optionally `POKI_DISPLAY_NAME` in Xcode or the `xcodebuild` invocation. Register the App Group and
associate it with both the app and widget identifiers in the developer portal before provisioning.
The app and widget read that same group from their built Info.plist; approval notifications are
namespaced to it. Do not reuse another app's group just to make signing pass.

`project-external.yml` builds the same app without the tunnel or its Network Extension entitlement:

```sh
xcodegen generate --spec native/ios-app/project-external.yml
open native/ios-app/PokiExternal.xcodeproj
```

CI produces `Poki-unsigned.ipa` and `Poki-external-unsigned.ipa`. Choose one, then install Poki Runner
with the same signing. The external build retains the App Group requirement for approvals and
thumbnails; it does not solve other free-account signing restrictions.

## Loopback choices

Setup initially offers an installed supported VPN before the built-in option. The user selects the
connection explicitly; an existing service response alone does not finish the setup step.

- **Karing**: keep its VPN connected, set TUN > Loopback address to `10.7.0.1`, and use **External
  app** in Poki. Poki's VPN stays off, so Karing continues to own the single packet tunnel. See the
  [maintainer's iOS support record](https://github.com/KaringX/karing/issues/899); verify the installed
  version and the developer-service check before continuing.
- **Built-in (default)**: Setup > Connect to this iPhone > Enable local connection. Approve iOS's
  VPN configuration prompt. Poki reflects only IPv4 TCP to `10.7.0.1/32`; normal internet routes and
  DNS are unchanged. The connection may displace another packet-tunnel VPN. Poki never silently
  changes an external VPN configuration or starts its local VPN merely because the app opened.
- **Proxy app**: Surge (module, `surge:///install-module?url=`), Loon (plugin,
  `loon://import?plugin=`), Shadowrocket (its "Include route 10.7.0.1/32" toggle) or sing-box (one
  line in the tun inbound). Files in `deploy/proxy-modules/`, served from the fork's raw GitHub URL
  for now (`ProxyApps.modulesBase`).
- **External build without a proxy app**: LocalDevVPN (App Store). This is an additional app and
  must be tested with the installed iOS version. It may displace another packet-tunnel VPN.

The setup step completes only when a TCP connection to the phone's RemotePairing or lockdown
service succeeds. Selecting an app, saving a profile or a VPN's Connected label alone never completes
it. Built-in VPN transport cannot be validated in the Simulator. See [the design and acceptance
checks](../../docs/ios-loopback.md).

## Device test checklist

Install and launch
- [ ] Install `Poki-unsigned.ipa` and the runner IPA with the same signing.
- [ ] Open Poki Runner by hand: no passcode prompt, no automation banner; it opens Poki (or shows Open Poki).
- [ ] Launch Poki: the Setup tab shows a badge with the steps left.

Setup
- [ ] Each step opens in turn; Open Settings starts a Live Activity with the step number and what to tap.
- [ ] Loopback: the status changes within 3 s when the proxy app's module is turned on or off.
- [ ] Pairing: the code shows in the Live Activity and in Poki; the step ticks.
- [ ] Let Poki stay on: Allow location shows iOS's prompt; Live Activities show as on.

Turned on
- [ ] Turn on: the Live Activity says "On. Waiting for an agent"; no automation banner yet.
- [ ] An agent's first call starts the runner; its steps show on the Lock Screen and on Home.
- [ ] Opening Poki Runner while in use shows "Poki is using this iPhone", not a black screen.
- [ ] No banner flicker during a run; a slow swipe or drag does not restart the runner.
- [ ] Stop on the Live Activity or in Poki: the banner goes away within seconds; the next call starts it again.
- [ ] After the idle time with no calls, the banner goes away by itself.
- [ ] Ten minutes in the background: the location pill shows and agents still reach the phone.
- [ ] Close Poki from the app switcher: the banner goes away within seconds.
- [ ] A sensitive action shows Approve/Deny in the Live Activity; Approve asks for Face ID.

Connect
- [ ] Add a connector: the sheet shows the URL, a QR that scans to the same URL, and Copy works.
- [ ] Revoke by swiping: the connector disappears and the relay answers 404 for it.
