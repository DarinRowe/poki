# Poki for iPhone

One app for everything a user does on the phone: setup (Developer Mode, on-device pairing, UI
Automation, the loopback, the first-session passcode), starting and stopping a session, the Live
Activity with Approve/Deny for sensitive actions, the MCP address for each client (text, QR, copy),
and a Debug tab (the former Poki Probe). Native SwiftUI on the iOS 26 SDK with Liquid Glass.

Poki automates the phone in its own process: it opens the XCTest automation session itself
(`Poki/Native/InProcess.m`, answered to PokiCore by `Poki/Runtime/InProcessWDA.swift`), so Poki is
the only app to install. The older Runner path (WebDriverAgent as a second bundle, built by
`.github/workflows/ios-runner.yml`; `docs/single-bundle.md` is the earlier study) stays in the code
and is chosen per launch with `-automationPath runner`.

## Layout

| Path | What |
|---|---|
| `Poki/App` | App entry (Chat and Voice pages), status words and issues, all steps, the app model (on/off, runner sleep and wake, events, approvals, pairing, setup steps) |
| `Poki/Setup` | Setup, one guided page with live checks |
| `Poki/Loopback` | Local VPN configuration and status, live developer-service checks, external VPN choices |
| `Poki/Activity` | Live Activity controller (state, steps, thumbnail in the App Group) |
| `Poki/Connect` | Relay identity (Ed25519 key, label, connector secrets in the keychain), MCP address with QR |
| `Poki/Runtime` | PokiCore and PokiLauncher glue, background keep-alive (location, then silent audio) |
| `Poki/Voice` | Talk to Poki: an OpenAI Realtime session over WebRTC, the calls it asks for, test runs |
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

`native/ios-app/scripts/app-tests.sh SIMULATOR_UDID` builds `PokiTests` and runs it inside Poki on a booted simulator (the in-process transport's clipboard and session answers).

`-pokiScreen home|setup|connect|debug|activity|steps|status|connector|details|model|voice` opens that screen at launch (home is the chat, setup its full-screen flow, connect the Settings sheet, debug Diagnostics inside it, details Poki's details, steps its history); `-pokiChat empty|working|approved` and `-pokiVoice ready|listening|working` show the ESP-171 boards' sample chat and voice faces; `-pokiSetupStep N` opens setup at step N, and `-pokiSample B|C` fills the status, history and Live Activity with sample steps and an approval, and `-pokiSample PIN` shows a sample pairing code, for screenshots only; on a simulator `-pokiLoopback cellular` forces the cellular-only loopback hint.

Poki is in English and Simplified Chinese and follows the iPhone's language. The app's screens use the String Catalog `Shared/Localizable.xcstrings`, the Live Activity its own table `Shared/LiveActivity.xcstrings` (see `Shared/ActivityWords.swift`), and the permission prompts `Poki/InfoPlist.xcstrings`. Poki's own status words stay in English inside the app (the code compares them and the agent reads them) and are looked up where they reach the screen; the launcher's fix sentences have entries too. Steps an agent reports, logs and diagnostics output stay as they come. Add `-AppleLanguages '(zh-Hans)'` to a launch to see Chinese without changing the simulator's language.

## How it runs

- Poki stays on once turned on, and turns on again at launch. Once the launcher has mounted the
  disk image, Poki opens its automation session (the log says `in-process session ready`), so the
  first look does not wait for it. The session, and with it iOS's automation banner, stays open until
  Poki exits; it is not stopped for idle. If it cannot be opened, an agent's call answers at once with
  the reason, and the next call, Poki coming to the front, or an agent connecting tries again.
- Nothing listens on a port: PokiCore's requests are answered inside Poki.
- The built-in local connection dials itself again when it fails or drops while Poki is on: 1, 2, 4, 8,
  16, 30, 30, 30 s, then it stops until the owner taps Enable Local Connection in Setup. Opening Poki
  dials nothing. It does not dial when the owner ended it (Turn off, Disconnect, Settings > VPN), when
  another VPN took the packet tunnel, or when another VPN is detected at the time of a try: Poki says so and
  stops. Detection is best effort: a VPN that sets no proxy, such as Tailscale, may not be detected. The automation then comes back by the loopback's own recovery. An external
  connection is never touched.
- Runner path only (`-automationPath runner`): the runner, and with it the banner, starts only when
  an agent asks, and stops after the idle time (default 60 s), from Stop on the Live Activity or in
  Poki, or when Poki is closed. Only Poki starts the runner; opened by hand, Poki Runner starts no
  test (PokiRunnerHost, `native/ios-runner/host`) and sends the person to Poki. While it runs, it
  answers on port 8100 to any device on the same network, with no credentials and without Poki's
  approvals (`native/ios-runner/README.md`).
- The Live Activity starts from the foreground, because iOS does not allow it from the background:
  when Poki turns on, when pairing starts, and when a setup step opens Settings.

## Voice

Voice (the waveform button beside the gear on Home, a sheet) talks to OpenAI's Realtime API (`gpt-realtime-2.1`) over WebRTC: the microphone is the
audio track, Poki's voice plays on the speaker, and events travel on the `oai-events` data channel.
The phone never holds an OpenAI key. The voice bridge on the person's Mac (`bin/voice-bridge.mjs`)
keeps the key and gives the phone a client secret that expires after 60 seconds:

1. Create an API key at platform.openai.com (API keys). Realtime audio is billed to that account per
   token; each test turn reports the tokens it used.
2. Keep it in the keychain, and read it from there, so it never lands in your shell history:

   ```sh
   security add-generic-password -a "$USER" -s openai-api-key -w    # asks for the key
   export OPENAI_API_KEY="$(security find-generic-password -s openai-api-key -w)"
   ```

3. Start Poki MCP first (`npm start`, see [docs/install.md](../../docs/install.md)); the bridge stops at
   once with "Local Poki MCP is not running" without it. Then, with the same state directory:

   ```sh
   POKI_MCP_STATE_DIR=... node bin/voice-bridge.mjs --device <iPhone id>
   ```

The bridge listens on every network interface (`--host 0.0.0.0`), because the phone reaches it over
the local network, in plain HTTP. Anyone who learns its address, which carries the secret, can open
sessions on your OpenAI key and move the phone through your Mac. Run it only on a network you trust,
and pass `--host <this Mac's LAN address>` to keep it off other interfaces (for example a VPN).

Enter `http://<Mac>:47830/voice/<secret>` in Voice (the secret is in `voice-bridge.json` in the
state directory). `get_ios_version` is answered on the phone;
the bridge runs the tools that move the phone (`open_settings`, `read_screen`, `open_app`, `tap_text`,
`go_home`) through the Mac's Poki MCP.

- Each function call runs once, keyed by its `call_id`, in the app and again in the bridge.
- `tap_text` is held by Poki's approvals, like an agent's `do`: the bridge first says what it would tap
  and in which app, without tapping; the phone checks that with PokiCore's rules (payments, deleting,
  sending messages, calls) and, when they ask for it, waits up to two minutes for Allow (in the Dynamic Island, on the Live
  Activity or from the notification). Only then does the bridge tap that element, matched exactly, in that app.
- A dropped connection sends nothing again. A call outlives the session that asked for it; the next
  session is told how it ended instead of asking for it again.
- Stop talking (or speaking over Poki) cancels the reply, never the step running on the phone.
- A `poki://voice` link, from a web page or another app, only opens Voice: a link never
  changes the bridge and never turns on the microphone. The person enters the address and taps Talk
  to Poki.
- Development builds only: the launch argument `-pokiVoiceLink "poki://voice?bridge=<address>&test=1-20"`
  runs recorded utterances from a bridge started with `--test-dir`, silently: the speech goes over
  the data channel instead of the microphone, and Poki's voice is muted. Release builds have no test
  runs.

## Signing and entitlements

| Entitlement | Needed for | Notes |
|---|---|---|
| App Groups `group.nz.zheha.poki` | Live Activity thumbnail, approvals between widget and app | Signing tools rewrite group ids per Apple ID; that works as long as both targets get the same rewritten group. |
| Network Extensions `packet-tunnel-provider` | Built-in local connection | Required in both Poki and PokiTunnel, with a matching provisioning profile for each bundle. A wildcard profile is insufficient. |

Which build to sign depends on the Apple account:

| Apple account | Build | Local connection | Signing |
|---|---|---|---|
| Paid Apple Developer Program team | `Poki-unsigned.ipa` (`project.yml`) | Built-in, or an external VPN app | App IDs for Poki, `.widgets` and `.tunnel`; the App Group on Poki and `.widgets`; Network Extensions (packet tunnel) on Poki and `.tunnel`; a development or ad-hoc profile for each of the three. |
| Free Apple ID (Personal Team) | `Poki-external-unsigned.ipa` (`project-external.yml`) | An external VPN app or LocalDevVPN only | The App Group on Poki and `.widgets` (signing tools rewrite it per Apple ID). Apps signed this way expire after 7 days, and only 3 can be installed at a time; Poki uses one (two with Poki Runner on the Runner path). |

On the Runner path, sign Poki Runner with the same account as Poki in both cases.

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

CI produces `Poki-unsigned.ipa` and `Poki-external-unsigned.ipa`. Choose one; on the Runner path,
also install Poki Runner with the same signing. The external build retains the App Group requirement for approvals and
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
  DNS are unchanged. The connection may displace another packet-tunnel VPN. Poki does not silently
  change an external VPN configuration or start its local VPN merely because the app opened. While
  Poki is on, its own tunnel is dialled again after a failure (see above), and stops when it detects another VPN (best effort, as above).
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
- [ ] Install `Poki-unsigned.ipa`. Runner path only: also install the runner IPA with the same signing, and open Poki Runner by hand: no passcode prompt, no automation banner; it opens Poki (or shows Open Poki).
- [ ] Launch Poki: the Setup tab shows a badge with the steps left, and no Install Poki Runner step.

Setup
- [ ] Each step opens in turn; Open Settings starts a Live Activity with the step number and what to tap.
- [ ] Loopback: the status changes within 3 s when the proxy app's module is turned on or off.
- [ ] Pairing: the code shows in the Live Activity and in Poki; the step ticks.
- [ ] Let Poki stay on: Allow location shows iOS's prompt; Live Activities show as on.

Turned on
- [ ] Turn on: the Live Activity says "On. Waiting for an agent"; once the session opens, the log says `in-process session ready` and the automation banner shows.
- [ ] An agent's first call finds the session open; its steps show on the Lock Screen and in the chat.
- [ ] No banner flicker during a run; a slow swipe or drag does not reopen the session.
- [ ] Runner path only: no banner until an agent's first call starts the runner; opening Poki Runner while in use shows "Poki is using this iPhone"; Stop on the Live Activity or in Poki takes the banner away within seconds and the next call starts it again; after the idle time with no calls, the banner goes away by itself.
- [ ] Ten minutes in the background: the location pill shows and agents still reach the phone.
- [ ] Close Poki from the app switcher: the banner goes away within seconds.
- [ ] A sensitive action shows Approve/Deny in the Live Activity; Approve asks for Face ID.

Connect
- [ ] Add a connector: the sheet shows the URL, a QR that scans to the same URL, and Copy works.
- [ ] Revoke by swiping: the connector disappears and the relay answers 404 for it.
