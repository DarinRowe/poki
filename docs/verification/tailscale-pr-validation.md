# Tailscale transport validation

The implementation was built and exercised on 2026-11-06. The initial checks below predate the observation-cancellation fix. Device screenshots are not stored in this repository.

## Automated checks

Seventeen relevant checks passed: the remote-session case and two batch-input cases (6.9 seconds together), three tool-discovery cases (5.2 seconds together), nine native pasteboard cases, and two native app-directory cases. The native release build also passed. This was targeted validation, not a full-suite run.

The added or modified tests in this PR are:

| Test and location | Protected behavior | Regression that fails it | Failed on the pre-change base? |
| --- | --- | --- | --- |
| `Remote screen capture survives observation cancellation and daemon restart after new connections are refused` in `test/remote.test.mjs` | A later capture still works after an observation deadline and a daemon restart | Killing the persistent helper on observation cancellation or losing it on daemon restart | Yes: before the cancellation fix, the next screenshot failed with `Remote helper stopped before becoming ready.` |
| `stdio reaches the authenticated local MCP service and rejects an absent device` in `test/protocol.test.mjs` | Default discovery stays limited while full HTTP discovery exposes the maintenance tools | Keeping the old full-catalog size after adding the two tools | Yes: full discovery returns 56 instead of 58 |
| `an all-profile HTTP service still lets each stdio client choose its own list` in `test/protocol.test.mjs` | Per-client default/full catalog selection survives the HTTP bridge | Applying the default filter to the full client | Yes: the full catalog lacks the two added tools |
| `Poki Agent opens its own MCP with the complete catalog even when the parent uses the default profile` in `test/protocol.test.mjs` | The independent Agent receives the full catalog | Losing the full profile when launching its own MCP client | Yes: the full catalog lacks the two added tools |

The protocol cases already existed; this PR updates their expected full-catalog size. The pasteboard, app-directory, and batch-input cases were reused without modification.

## Real-device evidence

Tested on iPhone17,1 with iOS 27.3. The operator confirmed USB disconnection and cellular use.

- After initialization over Wi-Fi, the same native session continued on 5G.
- Restarting the Poki daemon preserved the helper. Settings launched, and `poki123 AbC 中文24680` was entered with exact accessibility readback and a matching screen capture inspected during the check. The field was subsequently cleared.
- A failed explicit reconnect preserved the old usable session.
- Disconnecting Tailscale caused capture to fail explicitly rather than return a cached frame.

## Cancellation repair verification

The updated remote lifecycle regression failed before the repair with `Remote helper stopped before becoming ready.` It passed after the repair. The remote and protocol test files passed all 17 cases, and the native release build passed. After adding an assertion that the deadline actually interrupted an accessibility request, the single regression was rerun on both versions and again failed before the fix and passed after it.

On the authorized physical iPhone over RemotePairing, the original `wait_for` one-second timeout terminated the helper. The next screenshot needed a new process. With the rebuilt helper, the same timeout left the helper alive and the next screenshot reused its PID. A missing-element `tap_text` also returned an error without tapping, and the following screenshot retained the same helper and established TCP connections.

Two native-protocol checks exercised different failure paths. A screenshot aimed at an existing file returned an error, preserved the file, and kept the same tunnel connections. Abandoning a screenshot request removed its late output before the next request ran. These checks used the real native helper and phone, not the integration fixture.

The phone was on Wi-Fi during this repair round. One Settings launch returned a delivered launch but failed foreground verification; it is not counted as a successful app-launch check. No text was typed or submitted during the repair verification.

## Unresolved behavior

The cancellation regression now passes at the MCP boundary. Its synthetic helper refuses a replacement process, so the successful second screenshot proves reuse at that boundary. Native device verification is separate from this fixture.

Remote automatic unlock, Linux hosting, simultaneous use with another iOS VPN, and continuous video have not passed acceptance. Device name and OS version may be absent from remote device information because the current implementation reads RSD properties. These metadata omissions do not block screen or input operations. USB and simulator behavior has not been retested on devices in this repair round.

A clipboard snapshot was unavailable in the earlier mixed-text run, so restoration was not claimed. One accessibility read took 46.8 seconds; this evidence does not establish latency or long-duration stability targets.
