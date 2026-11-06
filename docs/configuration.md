# Configuration and sessions

All device operations are serialized inside the daemon. Every setting below is optional:

| Setting | Purpose |
| --- | --- |
| `POKI_MCP_STATE_DIR` | Override the state and endpoint directory. Must be set to the same value for both daemon and client. |
| `POKI_MCP_SESSION` | Session identifier (`1–80` characters: letters, digits, `_`, or `-`). Simultaneously connected clients with the same identifier share a session and its device selection, while distinct identifiers isolate them. The session closes as soon as any sharing client exits. Because of this, a shared value will not preserve a selection across separate `bin/call.mjs` runs, and reusing a running client's identifier in `bin/call.mjs` will clear that client's selection when the command exits. |
| `POKI_MCP_APPROVAL_MODE=allow` | Preapprove sensitive operations (listed under [Approval & Clipboard Behavior](tools.md#approval--clipboard-behavior)) for this daemon instance. Omit for interactive local approval prompts. |
| `POKI_MCP_NATIVE_TRACE` | Enable native diagnostic timing output on `stderr`. |
| `POKI_BIND_HOST` | Addresses the local HTTP bridge listens on, comma-separated. Defaults to `127.0.0.1`; `127.0.0.1` is added to any list that has no `127.0.0.1` or wildcard entry, because local clients read a `127.0.0.1` endpoint from `mcp.json` and send that `Host` header. A wildcard address cannot be combined with others. |
| `POKI_HOST_ALLOW` | Comma-separated `Host` header allowlist, for example `127.0.0.1,192.168.1.20`. When set, `hostHeaderValidation(list)` replaces `localhostHostValidation()`, which otherwise rejects every non-loopback `Host` with `403` and makes a LAN bind unusable. It must contain `127.0.0.1` itself: an entry for `localhost` or `[::1]` does not match the `Host` header local clients send. |
| `POKI_MCP_TOKEN` | Fixed bearer token for the local HTTP bridge. Defaults to a random token generated at each start, which invalidates every client's configuration on restart. |
| `IDEVICE_TOOLS` | Optional path override for the pinned upstream CLI. |

The authenticated local HTTP bridge passes the session via the `x-poki-mcp-session` header. Standard MCP clients should always connect through `src/stdio.mjs`.

On loopback the token file is a local convenience rather than a remote access mechanism: nothing off the machine can reach the bridge. That changes as soon as `POKI_BIND_HOST` points at something else, because the bearer token then becomes the only thing between the network and full control of the device. Give it to a LAN or tailnet you trust, keep it in a mode-0600 file rather than a command line, and expect `403` from every client whose `Host` header is not in `POKI_HOST_ALLOW`.

`poki_mcp_status` reports the version from the root `package.json`, the current short Git `commit` (`unknown` outside Git), and `native_build`, the bridge file’s UTC modification time (`unknown` when absent). A daemon startup warning reports Rust source or Cargo metadata newer than the bridge. It does not block startup or rebuild anything.
