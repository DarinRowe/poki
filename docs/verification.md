# Verification and known limits

## Status

The Simulator path is tested end to end from a fresh clone. Physical iPhone support has been verified only with the Chinese interface in portrait orientation. `sent: true` only means the touch was written to the connection. The device does not acknowledge it, so check `screen_changed` and the returned screen.

## Physical iPhone status

The earlier measurements below come from a single iPhone running iOS 27.3 over Wi-Fi. Treat them as a test log from that setup, not a guarantee for other apps or devices.

- With the old connection handling, tapping a specific search field in a chat app dropped 2 of 70 touches. Every dropped touch still returned `sent: true`. Keeping the connection open until the post-touch wait finished dropped 0 of 70 touches, and the final build dropped 0 of 24. These numbers only apply to that single search field.
- Via MCP in the same app, `tap_text` took effect 12 of 12 times. Batches that launched the app and called `tap_text` opened the conversation 14 of 14 times.
- Via MCP, `fill` on that search field worked 6 of 6 times and took about 15 seconds. If `fill` cannot verify the entered text, it now returns an error and stops the batch, matching Simulator behavior. `tap_text` took about 8 seconds.
- Two earlier `tap_text` calls on a conversation row returned `sent: true` but had no effect. We have not reproduced this failure, so it may have a different cause. Why the device drops touches is unknown.
- Touches sent too soon after app launch may have no effect. At 1.5 seconds after launch, 0 of 3 taps opened the conversation. At 2.8 seconds or later, 12 of 12 did. Via MCP, the pre-tap screen reads have so far delayed the tap past this window.
- Tapping a target next to a bottom floating bar had no effect 4 of 4 times in the Settings app. This is not fixed. Those taps now return `screen_changed: false`.
- We only measured taps. `drag` and `pinch` use the same connection path and were not measured. The latest update to how `screen_changed` compares screens has not been tested with touches on a physical phone.
- In one landscape game, taps on button coordinates had no effect, while portrait taps in the same session worked. The cause is unknown.

## Measured on simulators only

Known tasks ran on iOS 27.0 simulators with the disposable fixture app. A fresh client window got the tool descriptions and one sentence of task. Time covers the whole session, from client start to the last reply. Values are medians of 5 interleaved runs per client, task, and group. The single-step group was the same commit with `batch_commands` hidden.

| Client | Task | Round trips, batch | Round trips, single-step | Seconds, batch | Seconds, single-step |
| --- | --- | --- | --- | --- | --- |
| Claude Code | Counter | 3 | 5 | 17.1 | 24.6 |
| Claude Code | Form | 3 | 8 | 20.0 | 31.6 |
| Codex CLI | Counter | 2 | 7 | 24.4 | 36.4 |
| Codex CLI | Form | 2 | 7 | 28.7 | 46.1 |

A task with a deliberately wrong button name showed no measurable time difference. The ratio changes with task and machine load, so do not read it as a constant. These numbers were measured before the later physical-tap changes. They have not been re-run. To run the measurement yourself, see `bin/eval-first-call.mjs`.

## Test Suites

**Current state on an iOS 27.0 simulator.** `bin/verify-fixture.mjs` passes. `bin/verify-platform.mjs --with-core` passes and reports the pasteboard limit below, so it does not verify clipboard writes on this runtime. `npm test` passes on a loaded Mac. Occasional failures were seen under heavy load, and the cause of one is not known yet.

- **Protocol suite (`npm test`)**: Runs against an isolated temporary state directory and ephemeral port. It verifies the `stdio`-to-HTTP bridge, authentication, tool discovery, absent-device error handling, and wait-only batches without injecting input into a phone or simulator. All external device programs are replaced in an isolated copied runtime, including discovery and the approval dialog. No phone, simulator UI or real system dialog is used. The coordination suite covers two clients, lease expiry and exit cleanup, queued/SDK cancellation, stale references, OCR reuse, read deadlines, recording receipt preservation and bounded recovery. Node dependencies must be installed; native helpers need not be built.
- **Live simulator verification (`bin/verify-fixture.mjs`, `bin/verify-platform.mjs`)**: Optional scripts that perform real UI and application mutations. They require a dedicated disposable simulator named `Poki MCP QA` with the `PokiMCPFixture` app (`local.pokimcp.fixture`) installed, and are intentionally excluded from `npm test`.

These coordination checks use external-process fixtures. They do not establish real-device cancellation, gesture effects, first-time system permissions, or an independent new-user installation. Those checks still require separately authorized device acceptance.

## Known Platform Limits

- **First release on physical iPhones**: Portrait orientation only. Landscape control is unsupported. App container export (`download_app_container`) and direct Settings subpage links (`open_settings` with a page) are unavailable. Open Settings normally and navigate its visible controls instead. These limits do not change simulator support.

- **Pasteboard (iOS 27 Simulator)**: On the tested iOS 27.0 runtime (24A5370g) and iOS 27.1 runtime (24A94425), `simctl pbcopy` leaves the simulator pasteboard empty. Because of this, `set_clipboard` fails its readback and non-ASCII text cannot reach a simulator field. `fill` reports this as a mismatch. Plain ASCII text does not use the pasteboard and is not affected.
- **Emoji keyboard dismissal (iOS 27 Simulator)**: On the tested iOS 27 simulator, the emoji panel remains visible after toggling the keyboard. `hide_keyboard` truthfully reports failure while preserving field text; use the on-screen keyboard hide button or an app-supported outside tap instead.
- **Settings & Accessibility services**: Some Settings routes are unavailable. Simulator *Reduce Motion* and *Reduce Transparency* require direct Settings UI interaction, and a tested physical device returned `not implemented` for the larger-accessibility-sizes service.
- **Signing & container permissions**: Installing or building apps for physical devices requires valid Apple signing credentials (none are bundled), and container access is bound by platform permissions.
- **Private Apple interfaces**: CoreSimulator and physical-device bridges rely on Apple private interfaces whose behavior may change across OS releases. Exposing 56 tools does not imply complete tool/parameter validation across every iOS, macOS, or Xcode version.
- **Crash symbolication**: Only matches UUIDs and architectures from builds known to the current MCP session.

For deeper architecture notes, see the [physical-device bridge documentation](../native/NATIVE.md) and [simulator and platform adapter documentation](../native/simulator.md). Keep runtime outputs and test evidence inside the git-ignored `.runtime/` directory; never commit device screenshots, clipboard contents, or pairing records.

## Disclaimers

- Speed scales with the model and service tier you choose. Actual time depends on the model service, your Mac, and the phone's state.
- Saved routes require the page to stay the same. When it changes, Poki falls back to the model.
- Screen contents are sent to your configured model service.
- Poki does not confirm actions on the device. It operates a real device as instructed, and you are responsible for any messages sent or payments made.
- Provided as is under the AGPL-3.0-only license, without warranty.
- Poki is not affiliated with Apple. iPhone and iMessage are trademarks of Apple.
