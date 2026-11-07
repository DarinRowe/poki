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
| `Poki/Loopback` | Live 10.7.0.1 check, proxy app detection and one-tap module install |
| `Poki/Activity` | Live Activity controller (state, steps, thumbnail in the App Group) |
| `Poki/Connect` | Relay identity (Ed25519 key, label, connector secrets in the keychain), MCP address with QR |
| `Poki/Runtime` | PokiCore and PokiLauncher glue, background keep-alive (location, then silent audio) |
| `Poki/Voice` | Talk to Poki: an OpenAI Realtime session over WebRTC, the calls it asks for, test runs |
| `Poki/Debug` | 10.7.0.1 checks, the background hold test, the Live Activity preview |
| `Shared` | Live Activity attributes and views, the Approve/Deny/Stop App Intents (app and widget) |
| `PokiWidgets` | The Live Activity widget |

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
- The Live Activity starts from the foreground, because iOS does not allow it from the background:
  when Poki turns on, when pairing starts, and when a setup step opens Settings.

## Voice

The Voice tab talks to OpenAI's Realtime API (`gpt-realtime-2.1`) over WebRTC: the microphone is the
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

Enter `http://<Mac>:47830/voice/<secret>` in the Voice tab (the secret is in `voice-bridge.json` in the
state directory). `get_ios_version` is answered on the phone;
the bridge runs the tools that move the phone (`open_settings`, `read_screen`, `open_app`, `tap_text`,
`go_home`) through the Mac's Poki MCP.

- Each function call runs once, keyed by its `call_id`, in the app and again in the bridge.
- `tap_text` is held by Poki's approvals, like an agent's `do`: the bridge first says what it would tap
  and in which app, without tapping; the phone checks that with PokiCore's rules (payments, deleting,
  sending messages, calls) and, when they ask for it, waits up to two minutes for Allow (in Voice, on Home
  or from the notification). Only then does the bridge tap that element, matched exactly, in that app.
- A dropped connection sends nothing again. A call outlives the session that asked for it; the next
  session is told how it ended instead of asking for it again.
- Stop talking (or speaking over Poki) cancels the reply, never the step running on the phone.
- A `poki://voice` link, from a web page or another app, only opens the Voice tab: a link never
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

There is no built-in VPN for now: a sideloaded app cannot use the Network Extension (it needs
TestFlight or the App Store).

## Loopback choices

- **Proxy app**: Surge (module, `surge:///install-module?url=`), Loon (plugin,
  `loon://import?plugin=`), Shadowrocket (its "Include route 10.7.0.1/32" toggle) or sing-box (one
  line in the tun inbound). Files in `deploy/proxy-modules/`, served from the fork's raw GitHub URL
  for now (`ProxyApps.modulesBase`).
- **No proxy app**: LocalDevVPN (free, App Store), which takes the VPN slot.

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
