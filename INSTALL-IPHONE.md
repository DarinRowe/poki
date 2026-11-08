# Install the Poki iPhone app (for agents)

Use this guide when the user asks you to put Poki on their iPhone, for example "install Poki on my iPhone". It installs the standalone iPhone app through Poki Setup for Mac. It does not use the MCP install in [AGENTS.md](AGENTS.md).

You run one command. It does every step that does not need a person. At a step only a person can do, it prints one sentence. Tell the user that sentence, word for word. The command sees when the step is done and continues. At the end it runs a self-check and prints one `RESULT` line.

## Before you start

- A Mac with macOS 14 or later, Node.js 24 or later, and this repository checked out. Xcode is not needed.
- An iPhone or iPad on iOS 18 or later, and a USB data cable.
- The user's Apple Account. A free account works and is signed for 7 days at a time; Poki renews itself.
- Optional: a Cloudflare API token from the "Edit Cloudflare Workers" template, for a relay that lets outside agents reach the phone.

## The steps

| # | Step | Who | What the person does |
|---|---|---|---|
| 1 | Get Poki Setup | agent | Nothing. The command downloads the DMG, checks its SHA-256, its Developer ID team (`Q64ZL36CJN`) and notarization, and copies the app to `~/Applications`. |
| 2 | Start Poki Setup without a window | agent | Nothing. |
| 3 | Choose the release channel | agent | Nothing. Alpha is the default. |
| 4 | Sign in with the Apple Account | input | Stores the password in the Mac's keychain once, then types the 6-digit code Apple sends into their own Terminal. |
| 5 | Find the iPhone | phone | Plugs the iPhone in by USB and unlocks it. |
| 6 | Pair, Developer Mode, sign, install | phone | Taps Trust and enters the passcode; turns on Developer Mode, restarts, taps Turn On. |
| 7 | Trust the developer and open Poki | phone | Trusts the Apple Account in VPN & Device Management and opens Poki once. |
| 8 | Relay (optional) | input | Nothing if `CLOUDFLARE_API_TOKEN` is set or Poki Setup already keeps a token; skipped otherwise. |
| 9 | Self-check | agent | Nothing. |

The command skips what is already done: a signed-in Apple Account, a paired phone, Developer Mode that is on, and an install from an earlier run.

## Run it

From the repository root, start the command in the background so you can keep talking to the user:

```sh
node bin/install-iphone.mjs run --json
```

With `--json`, every line is one JSON event:

- `{"event":"step","step":"install","n":6,"of":9,"who":"phone","title":"..."}` starts a step.
- `{"event":"wait","wait":"pair","who":"phone","say":"..."}` is a person stop. Tell the user `say` exactly. `who` is `phone` (something to tap on the iPhone) or `input` (something to type on the Mac or tell you).
- `{"event":"done","step":"..."}` or `{"event":"skipped","step":"...","reason":"..."}` ends a step.
- `{"event":"error","code":"...","reason":"...","agent_fix":"...","retrying":true}` is a failure. When `retrying` is true, the command is already trying again.
- `{"event":"result","ok":true,"check":{...}}` is the last line.

Without `--json`, the same events print as text, and person stops start with `⏸ PERSON`.

Several iPhones plugged in: list them with `node bin/install-iphone.mjs phones` and pass `--udid <udid>`.

`node bin/install-iphone.mjs --version` prints the installer's version and build commit. `run` prints the same on its first line (`{"event":"installer",...}` with `--json`), so say which installer you used when you report a problem.

### Person stops

| `wait` | What you do |
|---|---|
| `apple_password` | Give the user the command in `say`. They run it in their own Terminal, and macOS asks for the password without showing it. Never ask for the password in chat, and never type it for them. The command reads it from the keychain item `poki-setup-install`, signs in, and then deletes that item; Poki Setup keeps its own copy for renewals. |
| `apple_code` | Give the user the command in `say` exactly as printed: it has the absolute path of this checkout's installer (and `--state` when the run uses a non-default folder), because a new Terminal starts in their home folder, not here. They paste it into their own Terminal and type the 6-digit code at the hidden prompt, like the password. Never ask for the code in chat, and never put it in a command line or type it for them. The command accepts no code as an argument. |
| `phone_plug` | Tell the user `say`. The command sees the phone. |
| `pair` | Tell the user `say`. The command sees the Trust tap. |
| `devmode` | Tell the user `say`. The phone restarts; the command waits for it to come back with Developer Mode on. |
| `pairing_file` | Tell the user `say`. This happens only when Poki Setup could not write the pairing file into Poki itself. |
| `open_poki` | Tell the user `say`. The command cannot see this step. When the user says Poki is open, run `node bin/install-iphone.mjs done open_poki`. |

A person stop waits 15 minutes. After that the command exits with code 3 and prints `{"event":"result","ok":false,"waiting":"..."}`. Run the same command again when the user is ready; it continues from that step.

## When a step fails

The command exits with code 2. The last `error` event has a `code`, the `reason`, and `agent_fix`, which says what to do. Do what `agent_fix` says, then run the command again. Ask the user only for what the `person` field names.

| Code | Meaning | What you do |
|---|---|---|
| `setup_download_failed` | GitHub did not serve the DMG or its checksum file. | Retried 3 times. Then check the network and run again. |
| `setup_checksum_mismatch` | The DMG does not match `SHA256SUMS-desktop.txt`. | Fetched again once. Then stop and report. Never open the file. |
| `setup_signature_invalid` | Poki Setup is not signed by team `Q64ZL36CJN` or not notarized. | Stop. Do not run it. Report it. |
| `bridge_start_failed` | Poki Setup's helper did not start. | Delete `~/Applications/Poki Setup.app` if this command put it there, and run again. |
| `usbmuxd_unreachable` | macOS does not list the iPhone (see issue #6). | Ask the user to plug it in again, unlocked. Then run `diagnose`. |
| `several_phones` | More than one iPhone is plugged in. | Run again with `--udid`. |
| `phone_locked` | The iPhone is locked. | Ask the user to unlock it. Retried by itself. |
| `trust_not_answered` | Nobody tapped Trust in time, or someone tapped Don't Trust. | Ask the user to tap Trust. Retried by itself. |
| `developer_mode_off` | Developer Mode is still off. | Ask the user to turn it on. Retried by itself. |
| `apple_credentials_missing` | No Apple Account password in the environment or the keychain. | Give the user the keychain command from the `apple_password` stop. |
| `apple_sign_in_rejected` | Apple refused the email or the password. | The keychain item is deleted; give the user the keychain command again. |
| `setup_app_missing` | `phones` or `diagnose` cannot find Poki Setup.app in the run's folder, `~/Applications` or `/Applications`. | Run `run`, which installs it, or pass `--app-dir` or `--bridge`. |
| `apple_code_wrong` | Apple refused the code. | Ask the user to run the `code` command again with the newest code. |
| `apple_server_busy` | Apple or the anisette server answered with an error. | Switches anisette servers and retries by itself. |
| `apple_account_limit` | A free-account limit: 10 App IDs a week, 3 apps, or one certificate already held by AltStore, SideStore or Xcode. | Stop. Tell the user which limit Apple named. The way out is their decision. |
| `network` | A request failed. | Retried by itself. Then report. |
| `sign_failed` | Signing failed. | Stop and run `diagnose`. |
| `install_failed` | iOS refused the install. | Retried once. Then run `diagnose`. |
| `relay_failed` | The relay deploy or check failed. Poki still works on the phone. | Report it. The user can deploy from Poki Setup's Relay page. |
| `check_failed` | Installed, but the self-check found something not ready. | Read the `check` fields, fix what the matching code says, and run again. |
| `unknown` | Not recognised. | Run `diagnose` and `issue`. |

## When you cannot fix it

1. Run `node bin/install-iphone.mjs diagnose`. It prints a JSON bundle: the versions and build of this installer, Poki Setup and the installed Poki, macOS, Xcode, each step's result, what usbmuxd, the USB bus, `devicectl` and Bonjour each see, and the last 40 lines of Poki Setup's log. It removes UDIDs, ECIDs, serials, device names, Apple Account emails, the Apple Account holder's name (a free account's team is named after them), the Mac's name, team and bundle IDs, tokens, keys, passwords, pairing records, relay addresses, IP addresses and the macOS user name. Show the user the bundle.
2. Run `node bin/install-iphone.mjs issue`. It writes an English issue draft that follows [the install-failure template](.github/ISSUE_TEMPLATE/install-failure.yml) and prints the `gh issue create` command. It never submits.
3. Show the user the whole draft. Ask whether to submit it. Run the printed `gh issue create` command only after the user says yes. If the user wants changes, edit the draft file first. Never submit an issue without that yes.

## Secrets

- The Apple Account password comes only from the keychain item `poki-setup-install`, which the user fills in their own Terminal. The Apple code is typed to the `code` command from the `apple_code` prompt, pasted as printed into their own Terminal. Never put either in a command you run. (`POKI_APPLE_ID` and `POKI_SETUP_PASSWORD` exist for the user's own shell, not for agents.) The Cloudflare token comes only from `CLOUDFLARE_API_TOKEN` or the token Poki Setup keeps. They go to Poki Setup's helper over a pipe, never on a command line, and the command never prints them.
- Do not print, log or paste the user's password, tokens, model API keys or iPhone passcode.

## Dry run

`node bin/install-iphone.mjs run --dry-run` downloads and checks the real Poki Setup, starts its real helper and reads the real release channels, then simulates the iPhone and the Apple Account. Nothing touches a device or Apple. It keeps its own state in `~/Library/Application Support/PokiInstall/dry-run`.

## Windows

Not covered yet. On Windows, install Poki Setup from the release and follow its window.
