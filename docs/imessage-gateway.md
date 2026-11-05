# Optional iMessage gateway

Poki uses BlueBubbles to receive iMessage tasks and return replies. Install it only if you want this channel. The normal `./bin/setup` build and Telegram do not download a gateway.

## Install

Use macOS on Apple Silicon or Intel, Python 3.11 or newer, and the macOS `curl` and `ditto` tools. The channel itself also needs Node.js 24+ and the [Poki Agent prerequisites](../agent/README.md).

From the repository root, run:

```sh
./bin/setup-channels
```

Choose `imessage` to install, or press Enter for `none`. Choosing `none` makes no network requests and writes no files. The explicit equivalents are `./bin/setup-channels --channel imessage` and `./bin/setup-channels --channel none`.

The installer asks for the local server URL, the single allowed sender, the Poki device name or ID, the exact direct chat GUID, and a server password. Password input is hidden. Choose a password now and set the same one in BlueBubbles when completing its setup. For a self-chat, the GUID can be `any;-;<sender>` or `iMessage;-;<sender>`; use the exact value for that conversation. See the [existing channel guide](../agent/README.md#configure-imessage-through-bluebubbles) for sender scoping and self-chat behavior.

The command downloads the architecture-specific ZIP from the [official 1.9.12 release](https://github.com/BlueBubblesApp/bluebubbles-server/releases/tag/v1.9.12), verifies the pinned SHA-256 digest before extraction, and checks the app version. It installs `~/Applications/BlueBubbles.app` and creates `~/.config/poki-agent/imessage/`:

- `imessage.json`: sender, direct chat GUID, device and ChatGPT authentication selection.
- `connection.json`: local server URL and password. Keep this file private.
- `state/`: created by the channel later for its cursor, reply ledger and task records.

The configuration directory has mode `700`; its two JSON files have mode `600`. The installer does not print the password, start BlueBubbles, sign in, grant permissions, start a worker or send messages. Download and verification failures remove the temporary archive and leave no app or channel configuration. Installation failures remove only the new app and configuration created by that attempt. Existing app or configuration destinations cause an error and are left unchanged.

Choose unused destinations when testing or keeping an existing installation:

```sh
./bin/setup-channels --channel imessage \
  --app-dir /path/to/clean/Applications \
  --config-dir /path/to/clean/imessage
```

For offline installation, add `--archive /path/to/BlueBubbles-1.9.12-arm64-mac.zip` (Apple Silicon) or the matching Intel `BlueBubbles-1.9.12-mac.zip`. This still requires the pinned digest. There is no option to skip verification or use a moving latest release. Release provenance and digests are recorded in the installer; the archive itself is not committed to Git.

For unattended installation, use `--answers /path/to/private-answers.json` instead of interactive input. Create it with mode `600` and these fields: `url`, `password`, `sender`, `device`, and optional `chatGuid`. Use the same formats as the prompts. Keep it outside the repository and remove it after successful installation. Do not put passwords in command arguments, shell history, screenshots or logs. The installer copies the password into the private connection file; it does not change BlueBubbles' own settings.

## Complete the steps that require you

1. Open **Messages → Settings → iMessage**, then sign in to your Apple Account. Complete Apple verification yourself. The installer never reads your Apple credentials.
2. Open the installed **BlueBubbles.app**. In its **Intro → Permissions** setup, follow the links to **System Settings → Privacy & Security → Full Disk Access** and enable this copy of BlueBubbles. Follow the Accessibility prompt if you use features that need it. When macOS asks for Messages automation permission, allow BlueBubbles to control Messages.
3. In BlueBubbles' **Connection** step, set the password you chose in the installer and click the save icon. Use the same local server port as the saved Poki URL. If you change the port or password later, update the private `connection.json` to match. Follow BlueBubbles' remaining onboarding steps, including notification setup if requested, using its [official setup guide](https://docs.bluebubbles.app/server/installation-guides/manual-setup).
4. Keep the server reachable locally. Poki's polling channel does not require exposing a public URL, enabling Private API or disabling SIP. Do not change those settings just to send ordinary text through Poki.

The official 1.9.12 release is signed and notarized. If macOS blocks it, inspect the system warning and consult the [release notes](https://github.com/BlueBubblesApp/bluebubbles-server/releases/tag/v1.9.12); this installer does not remove quarantine attributes or bypass Gatekeeper.

## Check, then start

Install the agent dependencies and complete its model login as described in the [agent guide](../agent/README.md). For a custom destination, include `--config-dir /path/to/clean/imessage` in both commands below.

```sh
node bin/poki-imessage.mjs --check
```

This loads the password privately, authenticates and reads only the configured conversation. It sends no reply and starts no phone task. A successful check confirms the gateway connection and scoped read, not phone automation or message delivery.

Once you have prepared Poki's MCP service, the selected device and model access, start the channel explicitly:

```sh
node bin/poki-imessage.mjs
```

Only new messages after the first startup become tasks. Keep this process running. Do not run two workers for the same conversation or delete its state directory to restart it. Stop the worker with Ctrl-C before moving or removing its private configuration. The launcher uses the configuration directory for state; it does not use the checkout's `agent/.runtime`.

## Verification scope

The install path was exercised with the official Apple Silicon release into a clean directory, with version and file permissions checked. Failure and opt-out paths use the same command. The private-config launcher was checked against a local fake gateway without sending messages. The Intel asset is pinned from the official release metadata but has not been installed on an Intel Mac. Apple Account login, macOS permissions and a real message exchange remain steps for the user; installing an app does not prove those steps work.
