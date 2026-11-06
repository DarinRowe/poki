# Cross-network connection checks

## Remote session lifecycle

Use the MCP integration test in `test/remote.test.mjs`. Capture the configured phone, let `wait_for` reach its observation deadline, and capture again. Then restart the daemon and capture from a new client. The helper fixture refuses every new connection process after the first one.

1. Protect continued screen capture after an observation timeout or a client and daemon restart.
2. Killing the helper on cancellation makes the next capture fail because a replacement process cannot connect.
3. Reuse the existing remote lifecycle test. USB and simulator tests cannot establish this transport contract.
4. Use the existing MCP fixture and `beforeStart` boundary without adding a production test hook.

The one-second deadline is the failure trigger, not a delay used to synchronize the test. The fixture represents the helper process boundary; it does not emulate Apple's tunnel protocol.

## Physical iPhone checks

On one authorized, prepared iPhone, capture the screen, run `wait_for` with a one-second timeout for absent text, and capture again. Record the helper PID before and after. The helper must remain alive and the second capture must use it. Repeat after a missing-element lookup. Do not submit text.

For cellular acceptance, establish the session on Wi-Fi, disconnect USB, and switch to cellular. Verify screenshots, app launch, and exact field readback. Test explicit reconnection and recovery after complete tunnel loss separately.

## Tool catalog contract

The existing protocol tests cover default and full HTTP discovery, per-client stdio profiles, and the independent Poki Agent client. The complete catalog includes `reconnect_device` and `disconnect_device`, raising its count from 56 to 58.

These checks protect the public discovery contract at each distinct transport or configuration boundary. They use real MCP discovery and add no production test entry points.
