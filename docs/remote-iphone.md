# iPhone over Tailscale

RemotePairing lets Poki use an already paired iPhone through its Tailscale address. It uses an encrypted userspace tunnel and does not change the Mac's default route, DNS, proxy, or other VPN settings. This is an opt-in transport; the existing USB path remains available for devices without a remote configuration.

**Experimental cross-network support:** the Mac and iPhone no longer need to remain on the same LAN. The verified route initializes a session on Wi-Fi, then keeps it while the iPhone uses cellular data.

## Prepare

1. Run `./bin/setup` in this checkout. Install the Tailscale app on the iPhone and Mac, and connect both devices to the same tailnet.
2. Connect the trusted, unlocked iPhone over USB and Wi-Fi. Developer Mode and UI Automation must already be enabled.
3. Set `POKI_MCP_STATE_DIR` to this installation's private state directory, then run:

   ```sh
   node bin/prepare-remote.mjs DEVICE_ID TAILSCALE_IP
   ```

   This verifies a RemotePairing record over the existing trusted USB connection. The pairing key remains in the private state directory. Ordinary operations never trigger a new pairing flow.
4. Start Poki with the same state directory. Call `take_screenshot` with the selected device ID while Wi-Fi is connected. Confirm the actual screen before disconnecting USB.
5. Disconnect Wi-Fi from Control Center, leaving the Wi-Fi setting enabled, Tailscale connected, and the phone unlocked. Verify the phone is using cellular data.

The configured device uses RemotePairing even when a USB connection is present, so testing does not silently fall back to USB.

## Operations and recovery

Supported paths are screenshots, accessibility observations, app listing and launch, touches and gestures, keyboard events, and verified text input through Poki's existing clipboard/field verification flow. Clipboard restoration is reported separately; an unavailable snapshot means the prior clipboard cannot be restored.

The native connection helper is independent of MCP clients and the Poki daemon. Closing a client or restarting the daemon preserves an idle phone connection. The private local socket is under `/tmp/poki-remote-<uid>`; it exposes no network listener. Pairing keys remain in the state directory; ephemeral tunnel keys are not saved.

`reconnect_device` attempts a replacement tunnel before dropping a working one. It never repeats a previous input. If an operation loses its response, inspect the screen before retrying. `disconnect_device` explicitly closes the helper and phone connection. Cancelling an observation abandons only that request. The helper finishes the read and discards its response. Cancelling an input drops the in-flight operation without replaying it or closing the shared tunnel. Some input may already have reached the phone; inspect the screen before retrying. The helper processes one request at a time, so later operations cannot overtake a draining read.

Ordinary service errors and observation deadlines preserve a live tunnel. The helper clears a connection after its underlying adapter has stopped. A cancelled read can occupy the helper until its native deadline, so the next request may wait. Native connection setup has a 25-second limit and execution has a 90-second limit; the JavaScript request budget is 120 seconds.

On iOS, Tailscale cannot run alongside another ordinary VPN. Users who need that other VPN to reach their AI client must resolve the internet-access requirement too. A suitable Tailscale exit node is a possible topology, but it has not been validated in this experiment. See [Tailscale's VPN compatibility documentation](https://tailscale.com/docs/reference/faq/other-vpns).

Device-management paths such as app installation, process termination, Settings deep links, recording, location simulation, and standalone clipboard access are not supported by this transport. They report a transport limitation instead of silently using a local connection.

## Return to USB or local Wi-Fi

Call `disconnect_device` for the selected iPhone. In this installation's `remote-devices.json`, remove only that device's entry. Use the same `POKI_MCP_STATE_DIR` as the daemon, or the default `~/Library/Application Support/PokiMCP` when it is unset. Restart the daemon and connect the phone over USB or local Wi-Fi. Merely plugging in USB does not override a remote entry. Keep the private pairing files if you intend to re-enable RemotePairing.

If setup reports that the saved pairing record did not verify, reconnect the trusted and unlocked iPhone over USB. Rename `remote/DEVICE_ID/pairing.plist` within the same private state directory, then run `bin/prepare-remote.mjs` again to create a new record. Do not share the old or new pairing file.

## Verification status

The initial transport checks used an iPhone17,1 running iOS 27.3 on 2026-11-06, before the cancellation fix:

- Wi-Fi initialization followed by cellular operation, with USB disconnected.
- Restarting the Poki daemon on 5G while retaining the native helper, then launching Settings and entering `poki123 AbC 中文24680` with exact accessibility readback and a matching screenshot.
- Continuing to read and clear the field after an explicit reconnect failed, demonstrating that the old working tunnel survived the failed replacement attempt.
- Returning an error without a cached image when Tailscale was disconnected.

Clipboard restoration was unavailable for the final mixed-text check and was reported as such. One accessibility-tree request took 46.8 seconds; this run is not a performance or long-duration stability acceptance. Continuous video/recording is outside the implemented remote transport.

The [cancellation repair checks](verification/tailscale-pr-validation.md#cancellation-repair-verification) separately verify timeout recovery, missing-element failure, and late screenshot cleanup on a real phone using Wi-Fi.
