# Install Poki for your client

To install the Poki app on the user's iPhone (the standalone app with Poki Setup), follow the skill [skills/install-poki/SKILL.md](skills/install-poki/SKILL.md) instead. This file installs Poki MCP for an MCP client.

Choose the installation path first:

- **MCP only.** If the user already uses Claude Code, Codex, or another MCP client and only asks to install this repository, connect Poki MCP to that client. Use the user's existing subscription and model. No extra model account or Poki login is needed. Follow steps 1–5 and the MCP checks in step 7, then end the installation. Skip step 6, including model login and the optional unlock question.
- **Poki Agent.** If the user explicitly wants Poki's standalone terminal agent or its messaging channels, also follow step 6. Poki Agent needs its own model access setup through `poki login`.

Follow these steps for the selected path. At each **STOP**, tell the user what they must do and wait for confirmation. Report completed steps and the remaining steps. Never describe a stopped installation as complete.

1. **Check prerequisites.** Read [requirements](docs/install.md#requirements). Check macOS, full Xcode, Git, Python 3, Node.js 24+, npm, Rust/Cargo, ffmpeg, and ffprobe. **STOP if Xcode is missing or unfinished.** Ask the user to install full Xcode, open it, and complete its setup. For another missing prerequisite, report the exact tool and installation hint before continuing.

2. **Clone and build.** Use the repository URL supplied by the user, or `https://github.com/JosssphZhou/poki.git`. Clone into a new directory, enter it, and run `./bin/setup`. If already in the intended checkout, use it. Continue only when setup exits successfully. Setup fetches its pinned dependency and builds the native helpers. See [installation troubleshooting](docs/install.md#fix-common-problems) on failure.

3. **Start the daemon in the background.** Run `npm start` with a persistent background process and a private log. Wait for a log line containing `"event":"ready"`. Keep the process running and report its PID and log path. For an isolated installation, set `POKI_MCP_STATE_DIR` to a new absolute directory and run `npm start -- --port 0`. Pass that same state directory to every client and terminal command below. Keep existing services and their state directories unchanged. Never print the token in `mcp.json`.

4. **Register your own client and install its skill.** Preserve existing configuration. From the checkout, choose only your client:

   - Claude Code: `claude mcp add --scope user poki-mcp -- node "$PWD/src/stdio.mjs"`. With an isolated state directory, add `--env POKI_MCP_STATE_DIR="$POKI_MCP_STATE_DIR"` before `poki-mcp`. Install the skill at `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills/poki-mcp` (normally `~/.claude/skills/poki-mcp`).
   - Codex: `codex mcp add poki-mcp -- node "$PWD/src/stdio.mjs"`. With an isolated state directory, add `--env POKI_MCP_STATE_DIR="$POKI_MCP_STATE_DIR"` before `poki-mcp`. Install the skill at `${CODEX_HOME:-$HOME/.codex}/skills/poki-mcp` (normally `~/.codex/skills/poki-mcp`).

   Create the parent skill directory, then copy the whole `skills/poki-mcp` directory to that destination. If a skill or MCP entry already exists, inspect it and preserve unrelated changes. Read the installed `SKILL.md` before any phone operation. Verify the registered absolute path and the installed skill contents. Other clients use [the MCP configuration examples](docs/install.md#2-connect-an-mcp-client) and their supported skill directory. If tools or skills need a new session to load, tell the user.

5. **Pair the iPhone. STOP before any device command unless the user has confirmed this phone is prepared.** Ask the user to connect the iPhone over USB, unlock it, and accept **Trust This Computer**. **STOP for Developer Mode** until the user enables it and completes any restart prompts. **STOP for UI Automation** until the user enables it in Developer Settings. Read [physical iPhone setup](docs/physical-iphone.md) for developer support files and `node bin/prepare-device.mjs YOUR_DEVICE_ID`. Run that helper only after confirmation. If Apple support files are missing, ask the user to finish device preparation in Xcode. After pairing, keep the phone unlocked on the same network as the Mac. Device discovery alone does not prove screen capture or input works.

6. **Install Poki Agent and choose channels, only when requested.** From the repository root, run `npm ci --prefix agent` and add this checkout to the current terminal path with `export PATH="$PWD/bin:$PATH"`. Present the optional unlock question below together with the model-login stop. **STOP for model account login.** Give the user the checkout path and the same `export PATH="$PWD/bin:$PATH"` command for their own terminal. Ask them to run `poki login` there and complete their chosen login method themselves. Read [Poki Agent](agent/README.md) for the API-key alternative and terminal tasks. Keep secrets out of chat, logs, and committed files. iMessage is optional. Skip it with `./bin/setup-channels --channel none`. If requested, read [the iMessage guide](docs/imessage-gateway.md) before `./bin/setup-channels --channel imessage`. Stop for the user's Messages sign-in, BlueBubbles onboarding, and macOS permissions. Confirm the sender and destination before starting `poki imessage`. For Telegram, follow the channel configuration in [Poki Agent](agent/README.md) before `poki telegram`. Both commands start workers that can send replies.

   **Optional unlock configuration. Ask this exact question after installing Poki Agent, and include the three disclosures in the same message:** "Do you want Poki Agent to unlock this iPhone when it is locked?" **STOP for the answer. Default to no configuration.** Asking this question does not operate the phone. Ask it even when pairing or phone operations are skipped. Skip the question only if the user has already explicitly declined optional unlock. Poki Agent can use `POKI_IPHONE_PASSCODE` when the phone is locked. Explain all three points before asking for a decision: the passcode stays on this Mac and does not enter the model or logs; anyone or any program with access to this Mac may be able to read it; verification covers only iPhone17,1 with a 402-by-874-point keypad, portrait orientation, and six digits. If the user declines, skip this option. Other features remain available. Only the user may configure this value in their private local launcher environment. Never read or write the user's passcode for them. The host passes it locally to the helper over stdin, outside model inputs and logs. If the user agrees, give them the hidden-input commands in [optional iPhone unlock](agent/README.md#optional-iphone-unlock) to run in their own terminal. Never ask them to send the passcode in chat. Setup builds `build/native-target/release/examples/unlock_iphone`. Check that this executable exists before offering the option. Without configuration, ask the user to unlock manually.

7. **Verify and report.** After the relevant user confirmations, run from the checkout with the daemon's state directory:

   ```sh
   node bin/call.mjs poki_mcp_status
   node bin/call.mjs list_devices
   ```

   Report the version, commit, `total_tools`, and whether the intended device appears. The default MCP `tools/list` exposes the tools for phone tasks. `total_tools` counts the complete catalog, including tools callable without default discovery. `POKI_MCP_TOOLS=all` exposes the complete list. Verify current output instead of treating either count as proof that installation works. For the Poki Agent path, run `poki status` after login. After authorization for a phone task, use `poki "<user task>"` and verify its actual result. With multiple devices, pass `--device '<device UUID>'`. Report any untested pairing, login, channel, or phone operation explicitly.

## Update

When the user asks to update Poki, run `./bin/poki update` from this installation. A source checkout must be on `main` with no local changes, including untracked files. The command runs `git fetch`, then `git merge --ff-only --no-overwrite-ignore @{upstream}`, then `./bin/setup`. If incoming files conflict with local ignored files, the merge stops and preserves them. If it stops, report the reason and preserve the user's changes. Do not reset, stash, or switch branches on their behalf. For a prebuilt package, follow the download steps printed by the command.

After a successful source update, reinstall Poki Agent dependencies with `npm ci --prefix agent` if the user uses Poki Agent. Tell the user to stop their existing service and restart it with `npm start`, using the same `POKI_MCP_STATE_DIR`. Updating does not restart the service. After restart, call `poki_mcp_status` and, for Poki Agent users, run `poki status`. Report the installed version and any remaining update notice.

Poki checks `https://api.github.com/repos/JosssphZhou/poki/releases/latest` at service startup and once per day. This anonymous request sends no token, device information, or conversation data. Results and failed attempts are cached for 24 hours in `POKI_MCP_STATE_DIR/update-check.json`. With the default state directory, this file is in `~/Library/Application Support/PokiMCP`. Startup does not wait for the request. Requests time out after 1.5 seconds, and failures stay silent. Status includes a newer stable version, the first sentence of its release notes, a release link, and `poki update`. Tell the user when that notice appears.

To disable checks and notices, set `POKI_NO_UPDATE_CHECK=1` before starting the service. Set it in your terminal too to hide notices in `poki status` from an already running service.

## File an issue

When the user asks you to report a problem or request a feature, file the issue so it matches one of the [issue forms](.github/ISSUE_TEMPLATE). `gh issue create --body` skips the forms, so write the body in the form's shape yourself. A check on new issues labels any issue that matches no form `needs-template` and asks for an edit.

1. **Search first.** Run `gh issue list --repo JosssphZhou/poki --state all --search "<key words>"`. If an issue already covers the problem, add a comment with your new evidence instead of opening another one.
2. **Pick one form.** One problem per issue.

   | Form | Use it for | Required headings, in order |
   | --- | --- | --- |
   | `bug_report.yml` | Poki MCP, Poki Agent, iMessage or Telegram, setup, native helper, relay on a computer | What happened, Steps to reproduce, Component, Connection, Versions |
   | `ios_app_bug.yml` | The standalone Poki iPhone app (Alpha or Pre-alpha) or Poki Setup | What happened, Steps to reproduce, Area, App version, Installed with, iPhone and iOS |
   | `task_failure.yml` | The tools work, but a real task in a specific app does not finish | Task, Where it stopped, Driven by, Versions |
   | `feature_request.yml` | A capability, speed-up, or design proposal | What you want to do, What happens today, Area |
   | `field_report.yml` | A working setup, port, install path, or test results, with no fix requested | Summary, Environment |

3. **Write the body.** Read the chosen form file. Make one `### <label>` heading for each field, using the label exactly as written in English, in the form's order. Put the answer under each heading. For a dropdown, use one of its options verbatim. Leave out no required heading. Write `_No response_` under an optional heading you cannot fill. The answers can be in the user's language.
4. **Keep it reviewable.** State what you observed and what you inferred separately. Give versions and commits from `poki_mcp_status` or the app's Settings. Quote exact error text. Remove passcodes, tokens, Apple account details, pairing records, phone numbers, and private screen contents.
5. **Create it.** Write the body to a file and run `gh issue create --repo JosssphZhou/poki --title "<specific title>" --body-file <file>`. Ask the user before creating it, and show them the title and body. Report vulnerabilities through [private reporting](https://github.com/JosssphZhou/poki/security/advisories/new), never in an issue.

If the check flags an issue you filed, edit that issue with `gh issue edit <number> --body-file <file>`. Do not open a duplicate. The label comes off once the body matches a form.

Example body for `bug_report.yml`:

```markdown
### What happened

`terminate_app` returned `already_stopped: true`, but Calculator stayed in the foreground with the same PID.

### Steps to reproduce

1. `launch_app` with `com.apple.calculator`.
2. `terminate_app` with the same bundle ID.

### Component

Poki MCP

### Connection

Physical iPhone over USB

### Versions

0.1.1 f4fd51e, macOS 27.0, Xcode 27.1, iPhone 15 Pro, iOS 27.3

### Logs

_No response_

### Suspected cause or fix

_No response_
```

## Contribute code

These rules are for agents changing this repository. The full release flow is in [docs/release-channels.md](docs/release-channels.md).

1. **Branch from `main`.** `main` is the only long-lived branch and it is protected: never push to it, force-push it, or rebase it. Name your branch `dev/<topic>` (one change per branch), never `claude/...` or a session name. Older branches such as `standalone` and `poki/ios-integration` are retired; do not base new work on them.
2. **Open a pull request into `main`.** Fill in [the template](.github/PULL_REQUEST_TEMPLATE.md). The `PR checks` workflow runs on Linux (Poki Setup core tests, Cargo lockfiles, actionlint) and must pass. After a change to `desktop/` or `native/launcher/` dependencies, run `cargo metadata --locked` for that manifest before pushing.
3. **A fix for a version already in Beta** lands on `main` first, then a separate PR cherry-picks it into `release/X.Y`. Release branches never take features.
4. **Do not cut releases by hand.** Every merge into `main` becomes a pre-alpha automatically (`prealpha.yml`, tag `ios-prealpha-X.Y.Z-N`, N = commit count of `main`). Alpha, Beta and Stable are promotions of that same build, started by a maintainer: Promote to Alpha, then Propose promotion (a bot PR on `promote/<channel>-<version>`). Do not push `ios-*` or `desktop-*` tags, do not edit `.github/channels.json` or `native/ios-app/VERSION` except in a promotion PR, and do not dispatch macOS workflows unless the user asks: GitHub runs at most 5 macOS jobs at once for this repository.
5. **Leave other people's branches alone.** Never force-push or rewrite a branch you did not create.
