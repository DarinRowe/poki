# Agent install: steps, design and next stage

This note is for the people who maintain the install. The agent-facing guide is [INSTALL-IPHONE.md](../INSTALL-IPHONE.md).

## Every step from zero, and who has to act

"Agent" means the installer does it with no window and no prompt. "Phone" means a person taps on the iPhone. "Input" means a person types something only they know.

| # | Step | Who | Can it go away, merge or move? |
|---|---|---|---|
| 1 | Download Poki Setup, check SHA-256, Developer ID and notarization | agent | Done by `bin/install-iphone.mjs`. A file fetched with `curl` carries no quarantine flag, so macOS shows no "downloaded from the internet" dialog, and the helper runs without the window. |
| 2 | Start Poki Setup | agent | The shipped `poki-setup-bridge` (JSON lines over stdio) is the headless mode. No change to Poki Setup was needed. |
| 3 | Choose the channel | agent | `set_channel`. |
| 4 | Apple Account password | input | Cannot go away: Apple's GSA sign-in needs it. Moved to the start, before any phone step. Typed once into the Mac's keychain with `security add-generic-password -w`, never in chat. Poki Setup keeps it for renewals, so it is asked once per Mac. |
| 5 | Two-factor code | input | Cannot go away. Once per Mac, since Poki Setup keeps the session. The code can arrive on the same iPhone. |
| 6 | Plug in by USB and unlock | phone | Needed for the first pairing and the install. |
| 7 | Trust This Computer and passcode | phone | Cannot go away: lockdown pairing needs the owner's consent. The RemotePairing record for iOS 26.4 and later is made in the same visit. Skipped when this Mac is already paired. |
| 8 | Developer Mode | phone | Cannot go away: development-signed apps do not launch without it, and the developer disk image needs it. On a phone with no passcode Poki Setup turns it on and the person only confirms after the restart. With a passcode, iOS refuses the remote switch, so Poki Setup reveals the switch and waits (Poki Setup 319). `devicectl` cannot turn it on either. |
| 9 | Sign and install Poki, pairing file, disk image | agent | Done by the bridge's `install`. |
| 10 | Trust the developer in VPN & Device Management | phone | Required for free accounts. Unverified: whether a paid team needs it, and whether `xcrun devicectl device process launch --payload-url "prefs:root=General&path=ManagedConfigurationList" com.apple.Preferences` can open that page directly (needs Xcode). |
| 11 | Open Poki once | phone | The installer cannot see it with Poki Setup 319, so the agent confirms with `done open_poki`. Next stage: a bridge check that Poki took `signing-identity.json` (Poki deletes it on first launch). Unverified: launching Poki with `devicectl` when Xcode is present. |
| 12 | Poki's Setup checklist on the phone (system permission prompts) | phone | iOS permission alerts need a tap. Not needed to finish the install; they come up the first time Poki needs each one. |
| 13 | Model API key for chat and voice | input | Today typed on the phone. Not needed when an outside agent drives Poki. Next stage: typed once on the Mac and carried to the phone (below). |
| 14 | Relay | input | The Cloudflare token comes from `CLOUDFLARE_API_TOKEN` or the token Poki Setup keeps; the deploy is agent work. Scanning the relay QR on the phone is still a person step. Next stage: hand the relay address over like the pairing file. |
| 15 | Self-check | agent | Install record, Developer Mode, pairing, disk image mount, relay check. |

## Design of this stage

- **Data shape.** `src/install/steps.json` is the single list: the steps in order (`id`, `who`, `title`), the person stops (`waits`, each with one sentence) and the error codes (`errors`, each with `reason`, `agent_fix`, `person`, `retry`). The runner, the guide and the tests all read it, and a test fails when the guide misses a code.
- **Runner.** `src/install/run.mjs` walks the list. Each step is a method that returns a detail line, returns `{ skipped }`, or throws. `classify` turns bridge error kinds and messages into a code. Steps the phone can heal (`trust_not_answered`, `developer_mode_off`, `phone_locked`) run again by themselves. A person stop polls for its own evidence: the keychain item, a file the agent writes with `code` or `done`, or the bridge's own wait. `run.json` records each step, so a second run resumes.
- **Transport.** `src/install/bridge.mjs` talks to the shipped `poki-setup-bridge`. Passwords and tokens go to it over stdin. `src/install/fake-bridge.mjs` speaks the same protocol with a simulated iPhone and Apple Account. The dry run and the tests use it.
- **Diagnostics.** `src/install/report.mjs` collects versions, step results, what usbmuxd, the USB bus, `devicectl` and Bonjour each see, and the last 40 log lines. `src/install/redact.mjs` removes identifiers and secrets. Poki Setup's own support bundle masks the Apple ID only and keeps UDIDs, device names and the relay address, so it is not used here.
- **Alternative not taken.** A non-interactive mode in the Rust `poki-setup` CLI. It would need a Rust toolchain on the user's Mac, it is not in the DMG, and a Rust change on `standalone` would conflict with the Poki Setup work that is still on `dev/desktop-setup`. The bridge already in the notarized app does everything needed.

### What the diagnostics cover in issues #6, #55 and #60

| Issue | What the reporter needed | In the bundle |
|---|---|---|
| #6 usbmuxd lists no device on macOS 27.2 | macOS and Xcode versions; usbmuxd's list against the USB bus and `devicectl` | `system`, `devices.usbmuxd`, `devices.usb_iphones`, `devices.devicectl` |
| #55 RemotePairing over Wi-Fi fails | iOS version, link kind, whether the phone advertises `_remotepairing._tcp` | `phones[].ios`, `phones[].link`, `devices.remotepairing_adverts`, the pairing step's notes in the log |
| #60 JD search blocked after install | Poki build and a working device session | Only the environment part. The failure is in automating one app after the install, which is outside the installer. |

## Next stage: the install agent inside Poki Setup

Asked for on Nov 8: Poki Setup's first page asks for a model key, and an agent built into Poki Setup runs the same steps with it, diagnoses failures and drafts the issue. The same key then works in Poki on the iPhone.

- **No agent framework in Poki Setup today.** The iPhone app's loop is PiSwift (`xibbon/PiSwift`, MIT), whose package supports macOS 15 and iOS 18. Poki Setup for Mac can link `PiSwiftAgent` and `PiSwiftAI` (its floor moves from macOS 14 to 15, or the agent is offered on 15 and later). Poki Setup for Windows is Tauri and React, so it uses pi's TypeScript packages (`@earendil-works/pi-ai`, already a dependency of `agent/`).
- **Key kinds** follow `ModelProvider` in `native/ios-app/Poki/Chat/ModelKeys.swift`: Anthropic, OpenAI, Sign in with ChatGPT, DeepSeek, Gemini, OpenRouter and a custom endpoint. Poki Setup keeps the key with the core's `store::secret_set` (macOS keychain, Windows Credential Manager) under `model-key.<provider>`, the account name the iPhone uses.
- **One set of steps.** The runner moves into `desktop/core` and reads the same `steps.json` (`include_str!`). The bridge gains one command, `agent_install`, that emits these events. The model drives four tools: run the next step, read the last error, collect diagnostics, draft the issue. It never decides the step order. `bin/install-iphone.mjs` becomes a thin client of `agent_install`, so an outside agent and Poki Setup's own agent run the same code.
- **Carrying the key to the phone.** Release builds have no path for this today. The closest existing path is the signing identity: Poki Setup writes `Documents/PokiSetup/signing-identity.json` into Poki's container over the USB pairing, and Poki moves it into its Keychain and deletes the file on first launch (`SelfSigner.start`, `import_identity`). A debug-only importer already reads `{provider, secret, model}` (`TestCredential.importIfGiven`). Proposal: Poki Setup writes `Documents/PokiSetup/model-key.json` (schema `poki.model-key/1`, with `provider`, `secret`, optional `model` and `custom_url`) right before the "open Poki" step. On launch Poki saves it with `ModelKeys.save`, selects the provider, and deletes the file. It is never logged. Exposure: until Poki first opens, a computer paired with the phone can read the file, the same as the signing identity, which holds the team's private key. The key page has a switch, on by default, "Also use this key on the iPhone".
- **Split.** This PR is the shared steps, the outside-agent command, diagnostics and the issue template. The next PR adds `agent_install` to the bridge, the key page and agent in Poki Setup for Mac, the key hand-off in the core and the iPhone app, and Windows after that.

## Checks on a real iPhone (not done yet)

1. Delete any Poki on the phone, then run `node bin/install-iphone.mjs run --udid <udid>` from zero with the phone locked by a passcode.
2. Compare `node bin/install-iphone.mjs phones` with `xcrun devicectl list devices` on macOS 27.3 (the #6 symptom).
3. Tap Don't Trust once and confirm `trust_not_answered` retries.
4. Confirm whether step 10 appears for a paid team, and try the two `devicectl` shortcuts in steps 10 and 11.
5. Run `diagnose` with the phone attached and read the bundle for anything left in.
