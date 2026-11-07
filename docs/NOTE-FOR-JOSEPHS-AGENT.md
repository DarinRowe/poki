# Note for Joseph's agent: Poki on the iPhone, standalone (branch `dev/ios-standalone`)

Written Nov 7 2026, 1:30 am ET, for Joseph and the agent working for him. Zhehan is away and cannot
test further builds, so everything from this round is on this branch. It was developed on Zhehan's
fork (ZhehanZhang/poki-remote) and consolidated here; nothing on `main` was changed and no PR is open.
The companion branch `dev/mcp-agent-tools` carries the matching work on the Node MCP; its note is
`docs/mcp-agent-tools-notes.md` there.

## Ground rules for this branch

- Do not merge into `main` without Joseph's review (CODEOWNERS). Open a PR only when Joseph asks.
- CI here never runs on a push: every workflow in `.github/workflows/` is `workflow_dispatch` only
  (GitHub shows "Run workflow" only once a workflow file is on the default branch), and `release.yml`
  runs on an `ios-vX.Y.Z` tag, so it never collides with Poki's own `vX.Y.Z` releases.
- Checks you can run without a phone:
  - PokiCore: `cd native/ios/PokiCore && swift test` (Linux or macOS; about 80 tests plus a soak).
  - PokiLauncher: clone `jkcoxson/idevice` at `89702099f4d7552f704f93b4526756abda319ceb` into
    `.deps/idevice`, apply `native/patches/idevice-xctest-run-over-rsd.patch`, then
    `cd native/launcher && cargo test`.
  - Relay: `cd deploy/cf-relay && npm ci && npx vitest run`.
  - App: `native/ios-app/scripts/make-assets.sh && xcodegen generate --spec native/ios-app/project.yml`,
    then build the `Poki` scheme (see `.github/workflows/ios-app.yml` for the exact unsigned build and
    the simulator screenshots).
- Evidence rule used so far: a claim about the phone counts only when it was seen on a real device;
  simulator-only facts are listed in `native/ios/PokiCore/UNVERIFIED.md`.

## What this is

Poki running with no Mac and no server in the loop. The iPhone runs three pieces of ours:

- **Poki** (`native/ios-app`): SwiftUI app. Setup, on/off, Live Activity with Allow/Deny for
  sensitive actions, the MCP address for each client, a Debug tab with the log.
- **Poki Runner** (`native/ios-runner`): WebDriverAgent 16.15.3 as an XCTest runner, branded,
  plus `PokiRunnerHost` (an injected dylib) that draws its screen. Started by Poki through
  `PokiLauncher` (Rust, idevice, `native/launcher`) over the phone's own developer services at
  10.7.0.1, which the user's proxy app reflects back (Surge, Loon, Shadowrocket, sing-box modules in
  `deploy/proxy-modules`). No VPN slot taken, no Mac after the first pairing.
- **PokiCore** (`native/ios/PokiCore`, Swift): the MCP (`look`, `do`, `status`) over WDA at
  127.0.0.1:8100, reached from the cloud through a Cloudflare Worker relay (`deploy/cf-relay`,
  live at pokimcp.zheha.nz, stores nothing).

The model stays in the cloud (claude.ai, Claude Code) and talks to the phone through the relay.

## What is on this branch

All of it is new files under these paths, except a WebDriverAgent section in `THIRD_PARTY_NOTICES.md`:

| Path | What | Fork branch it came from (final commit) |
|---|---|---|
| `native/ios-app` | The app (0.2.3), including the Live Activity | `dev/ios-app` 485f1fc, `dev/live-activity` 421c214 |
| `native/ios/PokiCore` | The on-phone MCP (`look`, `do`, `status`); its own note is `native/ios/PokiCore/NOTE-FOR-UPSTREAM.md` | `dev/ios-core` e822e43 |
| `native/launcher` | PokiLauncher (Rust, idevice): pairs, mounts the DDI, starts and supervises the runner | `dev/ios-core` |
| `native/ios-runner` | WDA 16.15.3 submodule, branding, `PokiRunnerHost` | `dev/ios-runner` a3e80ea |
| `deploy/cf-relay`, `native/ios/RelayCheck` | Workers relay and a client check | `dev/cf-relay` fb8876c |
| `deploy/proxy-modules` | Loopback modules for Surge, Loon, sing-box, Shadowrocket | `dev/ios-app` |
| `docs/ios-core.md`, `docs/device-test-checklist.md`, `docs/production-bar.md`, `docs/release-review.md`, `CHANGELOG.md` | Spec, phone checklist, release notes | |

Tags: none yet. Versions come from `native/ios-app/VERSION`; `release.yml` on an `ios-vX.Y.Z` tag
builds both IPAs with that version. The relay address is still hard-coded to Zhehan's deployment
(`pokimcp.zheha.nz`, in `PokiCore/Core.swift` and `ios-app/Poki/Connect/RelayIdentity.swift`); that
needs a decision before anything ships from this repo.

## Phone-test rounds on an iPhone 17 Pro, iOS 27.3 (owner's own tests)

| Round | Build | Found | Fixed in |
|---|---|---|---|
| 5 | 0.2.0 | Live Activity clipped; scrolling stalled; approvals never showed (event stream died after the first Turn off); Stop slow; raw JSON | 0.2.1 |
| 6 | 0.2.1 | Taps near the top landed on the expanded Dynamic Island and opened Poki; iOS 27 container clipped the Live Activity; "Best Buy" read as a payment | 0.2.2 |
| 7 | 0.2.2 | Surge's tunnel dropped twice and took the runner with it (recovery 30-90 s); tree reads stalled behind autoplay and a paste alert; one WDA session per read; paste leaked the clipboard; stale element numbers | 0.2.3 (tunnel side) and PokiCore e822e43 (clipboard, banner, sessions, relay drop); the rest is open |

Details per round: `native/ios-app/CHANGELOG-round.md`. What only the phone can confirm:
`native/ios/PokiCore/UNVERIFIED.md`, `docs/device-test-checklist.md`.

## Open problems, in order of pain

1. **Tunnel drops.** The XCTest runner dies when the developer connection does, and that connection
   runs through the user's proxy tunnel. 0.2.3 notices a drop, names it to the agent with the time
   and restarts the runner the moment 10.7.0.1 answers; it cannot stop the drop. Ideas: a keepalive
   through the tunnel, Surge on-demand rules, checking whether Focus/Bedtime suspends the proxy.
2. **Tree reads under animation.** WDA's snapshot waits for the app to idle; JD's homepage and a
   system paste alert never idle. PokiCore e822e43 keeps the session when a read times out and moves
   WDA's active-app detection point to mid-screen; idle timeouts near zero and alert detection before
   slow calls are still to do.
3. **`via: "paste"`** inserted the owner's clipboard instead of the text once. Fixed in PokiCore
   e822e43 (write verified, clipboard restored only once the field shows the text), not yet seen on
   the phone.
4. **Element numbers** persist across page changes; the agent tapped the wrong thing by number.
5. **Stop while the runner is stuck** in a long read waits for iOS's ~30 s watchdog; 0.2.3 retries.

## How this could unify with upstream's MCP

- The detailed view from the PokiCore side is in `native/ios/PokiCore/NOTE-FOR-UPSTREAM.md`: one
  look/do contract for both MCPs, facts only, phone-only pieces stay in the app.
- `dev/mcp-agent-tools` (this repo) already carries a WDA backend for the look/do profile in the Node
  daemon (`src/cua-wda.mjs`, `POKI_CUA_BACKEND=wda`), so `look` and `do` answer the same way whether
  the bridge or the runner is underneath. PokiCore's later lessons (timed-out requests end the WDA
  session so nothing runs late, XML tree, busy answers, covered-element taps, the island region,
  per-action clocks) are in Swift and would need porting into that backend (about a day).
- The runner path sidesteps the private RemoteXPC services behind upstream issues #1 (AX and touch
  unavailable on iOS 18.6) and #6 (usbmuxd empty on macOS 27.2), and needs no Mac after pairing.
  It still needs the personalized developer disk image (#18 applies as much to us).
- It cannot replace all upstream tools: no raw HID, no per-process tools, and the runner must be
  installed and signed (a free Apple ID gives 7 days and 3 apps).
- Suggested shape: the runner path as an optional backend behind the same tool names, chosen per
  device, with the on-phone app as the way to run it without a computer.

## Facts that cost us time (so you do not pay again)

- ActivityKit `AlertConfiguration.sound` is not optional; an alert always expands the island, and a
  tap on the expanded island opens the app. Never alert while automation may tap near the top.
- A Live Activity on iOS 27's Lock Screen sits in a container with a ~40 pt corner radius; keep
  content within 124 pt and 22/18 pt margins.
- Cancelling the Task that iterates an `AsyncStream` ends the stream for good: one pump per app life.
- WDA serves one request at a time except `GET /status`, `GET /screenshot`, `DELETE /session`;
  `DELETE /session` voids everything queued, which is the only clean "abandon".
- The JSON `/source` fetches custom actions per element (one accessibility round trip each); the
  XML `/source` does not and is 3 to 7 times faster.
- A merge once dropped the CI version stamp silently; the IPA check in `ios-app.yml` now fails
  if the IPA's version differs from `VERSION`.
