# Handoff: the `standalone` branch and the first pre-alpha

Written Nov 8 2026, 4:20 am ET (Philadelphia time), for Joseph and the agents working for him. It covers
what `standalone` is, how it was put together, how releases and channels work now, what Poki Setup
does, what was checked and what was not, and what is still open. Read `HANDOFF.md` (the
`poki/ios-integration` handoff) and `docs/NOTE-FOR-JOSEPHS-AGENT.md` (the earlier
`dev/ios-standalone` note) for the history before this.

## In one paragraph

`standalone` is the full state of Zhehan's standalone iPhone work as of the first pre-alpha. It has
full history and no squashes. It is the native SwiftUI revamp of the iPhone app (`native/ios-app`),
plus on-device self-signing (Poki re-signs and updates itself, free Apple accounts included), plus
Poki Setup for Mac and Windows (`desktop/`), plus a release-channel system (Stable, Beta, Alpha,
Pre-alpha) on this repository's GitHub Releases. The first pre-alpha is tag `ios-prealpha-0.2.8-499`
on this file's commit (the head of `standalone` when it was cut): Poki 0.2.8 (499) with Poki Setup 0.2.1 (307). Nothing on `main` was touched and no
PR is open.

## Ground rules (unchanged, please keep them)

- Never push to `main`; no PR unless Zhehan or Joseph asks for one.
- Never force-push. Fast-forward only; if someone else's work is on a branch, pull first.
- Commits meant for this repository are authored as ZhehanZhang (`github@zhehanz.com`), with no
  `Co-Authored-By` trailers and no agent session links.
- Branch names use the `dev/` prefix (except the user-named `standalone`).
- CI runs only on tags or by hand on this repository; nothing builds on a branch push except the
  `dev/desktop-*` desktop workflows (see below).
- A claim about the phone counts only when it was seen on a real device. Simulator-only and
  compile-only facts are marked as such below.

## How `standalone` was built

The first-parent history of `standalone` is a series of merges. From oldest to newest:

| Commit | What |
| --- | --- |
| `4b2f26f` and earlier | Fork `dev/ios-native-revamp`: the native SwiftUI revamp of the app, built on `poki/ios-integration` (it contains `ea223c5`, `c9343e1` and the `22cad01` HANDOFF). The self-refresh work (`dev/self-refresh`) is merged into it. |
| `03c5a83`, `012e5e3` | Release channels: `channel-release.yml`, `cut-release.sh`, `docs/release-channels.md` (first Pre-alpha, then Alpha). |
| `b4a67d2` | The iOS IPA workflow can be called by `channel-release.yml` (inputs `version`, `build`, `editions`). |
| `53ff4aa`, `a4e09bb` | Releases attach the relay Worker (`poki-relay-worker.js`, listed in `SHA256SUMS`) and the release notes link it. |
| `ea68952`, `9ebaf1e`, `8905942` | Merges of fork `dev/desktop-setup` (Poki Setup 0.2.1 builds 297 to 299). `8905942` resolved conflicts in `desktop/core/src/relay.rs` and `desktop/core/src/apple/store.rs`; see "Rust core features" below. |
| `1a0e05c` | CI split: `ios-app.yml` is the full workflow again (tests, simulator, screenshots, restored from before `dc2cb40`), and `ios-ipa.yml` is the fast unsigned IPA build that `channel-release.yml` calls. |
| `3ad8e56`, `c48e15f`, `bff458e` | Merges of `dev/ios-native-revamp` up to `b8c243a`: pairing fixes (`422788e`, `7ca2b55`), aws-lc pinned as the TLS provider (`f5fb69c`), the voice restart fix, the separate on-device pairing file, and chat scrolling. |
| `5c42d82`, `297ba04`, `71e16b7`, `13656d7`, then the `c465a5a` merge | Merges of `dev/desktop-setup` up to `c465a5a` (Poki Setup 0.2.1 build 307: the signer renames `BGTaskSchedulerPermittedIdentifiers` to the signed bundle id, and the Mac sidebar fix). Before that `a121d41` (build 304). |
| `02fd595`, `2afe565`, the `8519c32` merge, then the `41509e8` merge | Merges of `dev/ios-native-revamp` up to `41509e8` (one in-process automation session per launch, so turning Poki back on after Off relaunches it from a notice; stand-by drops the banner but keeps the session; ask_poki off by default under Settings › Diagnostics › Testing). Before that `8519c32` (approval switches with the auto-classifier, background keep-alive, ask_poki for repetitive tasks); before that `2b9ec5b` (approvals off by default for this alpha; Settings › Approvals › Ask Before Sensitive Steps turns them back on). Before that, `d7e91b2`: Install button fix, Stop ignored right after Allow, the session stays open while idle, screen reader recovery after a reopen, Hide Banner When Idle. |

Fork sources, all on ZhehanZhang/poki-remote: `dev/ios-native-revamp` at `41509e8` and
`dev/desktop-setup` at `c465a5a`. The prepared branch was `dev/standalone-cand`.

### Not in `standalone`

`main` is not an ancestor of `standalone`. About 71 commits on `main` are not in it (counted Nov 8).
`dev/ios-standalone` is fully included.

`poki/ios-integration` moved on after `standalone` forked from it. Its `db0e8ea` and the four
commits before it (PRs #48, #50, #51, #52, #54: in-process session idle end, voice listening and
background fixes, voice with the phone's own OpenAI key) are **not** in `standalone`. The revamp
has its own bridgeless voice that uses the phone's OpenAI key (`fd6cec8` and later), so expect
conflicts in `native/ios-app/Poki/Voice` and the in-process session code when the two lines are
merged. Nobody has done that merge yet.

## The iPhone app (`native/ios-app`)

- Version in `native/ios-app/VERSION` (0.2.8). The build number is always
  `git rev-list --count HEAD` (full-history checkout), so a later commit always has a bigger one.
- Minimum iOS 18.0. iOS 17.6 is blocked only by PiSwift.
- **UI rule from Zhehan:** native SwiftUI only. Standard components, Liquid Glass on iOS 26 and
  later with fallbacks to iOS 18. No custom UI and no overlays. Review every screen against this
  before you add one.
- Tabs: Poki (sessions and chat), Agents (connectors), Setup (status, checklist, signing).
- The default is one app: automation runs in Poki's own process. Poki Runner is optional
  (Settings › Diagnostics).
- Chat and voice run on the phone: PiSwift (`pi`) is the model loop, accounts are Anthropic,
  OpenAI, DeepSeek, Gemini or Sign in with ChatGPT (PiSwift `loginOpenAIChatGPT`). Live voice uses
  OpenAI Realtime with the phone's key; other models get hold-to-dictate plus TTS.
- Gotcha: PiSwiftAI exports a type called `Context`. In a file that imports it, a
  `UIViewRepresentable` must write `UIViewRepresentableContext<Self>`.

### Self-signing (`native/ios-app/Poki/Signing`, `native/launcher/src/signer.rs`)

- Poki Setup writes the signing identity into Poki's container as
  `Documents/PokiSetup/signing-identity.json` (schema `poki.signing-identity/1`) on install and on
  renewal. Poki moves it into its own Keychain.
- The Rust signer is Poki Setup's core (`desktop/core`), linked into `native/launcher` as a static
  library. It installs through installation_proxy and misagent over the 10.7.0.1 loopback.
  Anisette comes from remote v3 servers (`new.ani.sidestore.io`, then fallbacks).
- Zhehan's rules for it: refresh status and a countdown on the Setup page; updates are
  pre-downloaded and pre-signed for the chosen channel (same code as the desktop, `release.rs`);
  an install never lands by itself. Poki holds a ready build until it is idle and the owner taps
  Install (buttons "Prepare Refresh Now", then "Install Refresh"; the row "Signed Until").
- **TLS gotcha (cost us a night):** the signer's anisette client installed `ring` as rustls'
  process-wide provider, and after that the phone's lockdown TLS failed with "device socket io
  failed". `f5fb69c` pins aws-lc as the process provider in PokiLauncher before anything
  connects. Don't let any crate install a different default provider.
- **Pairing gotcha:** on-device pairing works, but only after the iPhone passcode is entered when
  iOS asks. A failure at that step looks like "no pairing code ever appears". Check the passcode
  step before you debug the code path.

## Poki Setup (`desktop/`)

- `desktop/core`: everything, no UI (Rust). `desktop/cli`: `poki-setup`. `desktop/bridge`:
  JSON lines over stdio for the Mac app. `desktop/mac`: native SwiftUI Mac app (SwiftPM, macOS 14+,
  Liquid Glass on 26). `desktop/app`: Tauri 2 Windows app with the same layout.
- Version 0.2.1 in `desktop/Cargo.toml`, `tauri.conf.json` and `package.json`. The build number is
  **not stored**: CI computes it as the commit count of the commit it builds (`POKI_SETUP_BUILD`).
  307 is `c465a5a` on `dev/desktop-setup`. An installer built from `standalone` would say 499
  instead, so the release attaches installers built from the desktop branch.
- Release channels (`desktop/core/src/release.rs`): `Channel` = Stable, Beta, Alpha, PreAlpha,
  saved in `state/channel.json`, overridable with env `POKI_RELEASE_CHANNEL`. Each channel includes
  the more stable ones. If a channel has no release yet, it steps down toward Stable. The default is
  Stable. CLI: `poki-setup channel [name]`, `poki-setup release --all`. Mac: the Poki row on the Setup
  page. Windows: Settings › Updates.
- Self-update reads **any** release on the channel, `ios-*` included, for assets named
  `PokiSetup-<ver>-<build>-macos.dmg` or `PokiSetup-<ver>-<build>-windows-x64-setup.exe`. Keep
  those names exact.
- Relay: Update Relay downloads `poki-relay-worker.js` from the release that matches the installed
  Poki and checks it against `SHA256SUMS`, with the bundled copy as a fallback. Zhehan called
  shipping an old relay "unacceptable", so keep it this way. The Cloudflare API token is kept in the
  keychain (`cloudflare-relay-token`), and Forget removes it.
- Sign-in: Apple GSA (SRP-6a, 2FA by trusted device or SMS). Anisette is remote by default
  everywhere (macOS 27's AOSKit gives no X-Apple-MD). `ani.sidestore.io` serves Android data under
  Mac client info and causes ec -80045; use `new.ani.sidestore.io` and rotate on -80045/-80046.
- Any Apple ID works. Each team gets `nz.zheha.poki.<TEAM>`, `.widgets` and
  `group.nz.zheha.poki.<TEAM>`. The packet-tunnel extension is always left out (a team profile
  can't carry it), so tester-signed builds need a proxy app for the loopback (Karing, Stash,
  Quantumult X, Clash Mi, plus the modules in `deploy/proxy-modules`).
- Builds 300 and 301 had a pairing QR "data too long" bug. 302 fixes it, makes a Remote Pairing
  (RPPairing) record over USB for iOS 26.4+, and never overwrites a pairing Poki made itself.
- Mac notarization was done on Zhehan's Mac (Developer ID Application: Zhehan Zhang, team
  Q64ZL36CJN, notarytool profile `console-neo`). CI supports `MACOS_CERT_P12` and `NOTARY_*`
  secrets, but none are set here.

### Rust core features (read before touching `desktop/core`)

- Features `device` and `os-keychain` are on by default. Poki on the iPhone builds the core with
  **no default features** and installs its own vault (`crate::vault`).
- `apple/store.rs` `secret_get/set/delete` try `crate::vault::installed()` first, then file mode,
  then the OS keyring (only with `os-keychain`).
- Anything that talks to a device over USB needs `#[cfg(feature = "device")]` (for example
  `setup.rs` `hand_signing_identity`).
- Always run `cargo check -p poki-setup-core --no-default-features` as well as the normal build,
  or the iPhone build breaks without anyone noticing on the desktop.
- Linux needs `libdbus-1-dev` and `pkg-config` for the keyring crate.

## Approvals are off in this alpha

Zhehan's call (Nov 8, 5:14 am ET): this alpha approves everything by default (payments, deleting, sending, calls,
passwords, Wallet input), because the prompts slowed tasks down and the in-app prompt could not be answered while an
agent drove the phone. Since `41509e8` Settings › Diagnostics › Testing has three switches, all off by default: ask_poki Tool (outside agents drive with look and do unless it is on), Ask Before
Sensitive Steps (the manual prompts; testers are told not to turn it on, it does not fully work yet) and
Auto-Classifier (Permissiveness Strict, Balanced or Permissive; the chat model decides each sensitive step out of
sight from what the owner said, shows "Approved by model" or "Not approved by model", and a refused step goes
through after the owner says yes in the chat). The release notes warn about all of this in every language.

Also from `8519c32`: on iOS 26 and later Poki keeps running with a BGContinuedProcessingTask instead of silent audio
and location. `desktop/core` `sign/mod.rs` now rewrites `BGTaskSchedulerPermittedIdentifiers` to the signed bundle
id. Poki Setup 307 has that change; with an older Setup (304) iOS refuses the task and Poki falls back to silent audio
(safe).

## Tag ruleset

This repository's "Protect tags" ruleset (rules/26676466) blocks tag creation for everyone without admin, except
`ios-prealpha-*`, `ios-alpha-*` and `ios-beta-*`, which are excluded (since Nov 8). Any other tag name needs Joseph.

## Releases and channels (`docs/release-channels.md`)

| Channel | Tag | GitHub release |
| --- | --- | --- |
| Stable | `ios-vX.Y.Z` | full release |
| Beta | `ios-vX.Y.Z` | prerelease (every `ios-v*` starts as one) |
| Alpha | `ios-alpha-<VERSION>-<count>` | prerelease |
| Pre-alpha | `ios-prealpha-<VERSION>-<count>` | prerelease |

- `release.yml` handles `ios-v*`. `channel-release.yml` handles `ios-alpha-*` and `ios-prealpha-*`.
  Both run only on tags, and a tag push runs the workflow file **at the tagged commit**, so the
  workflow must be in that commit.
- `channel-release.yml` checks that the tag is exactly `ios-<channel>-<VERSION>-<count>`, calls
  `ios-ipa.yml` with `editions: local external` (a failed local edition only warns; a failed external
  edition fails the release), and publishes `Poki-external-<V>-<B>.ipa`, `Poki-<V>-<B>.ipa` when it
  built, `Poki-signing.zip`, `poki-relay-worker.js` and `SHA256SUMS`. The release is a prerelease
  with `--latest=false`, so the Mac server's update check (`releases/latest`) never sees it.
- To cut one: `native/ios-app/scripts/cut-release.sh pre-alpha <ref>` (or `alpha`). `DRY_RUN=1`
  prints the tag. **Always pass the ref.** The default is `origin/poki/ios-integration`, which lacks
  `channel-release.yml` today. The script refuses a commit that isn't on the remote or that lacks
  `channel-release.yml`.
- Then attach the Poki Setup installers (exact names) and `SHA256SUMS-desktop.txt` by hand, and
  replace the generated notes with the final text (`gh release edit --notes-file`).
- The `desktop-*.yml` workflows run on `desktop-v*` tags, on `dev/desktop-*` pushes, or by hand. No
  workflow publishes `desktop-prealpha-*` releases yet. Self-update works anyway because it reads
  the installers attached to `ios-*` releases.

### Superseded pre-alpha candidates (never pushed, do not push)

| Tag that would have been | Commit | Why it was dropped |
| --- | --- | --- |
| `ios-prealpha-0.2.8-450` | `9ebaf1e` | Poki Setup 298; superseded by the token-in-keychain build |
| `ios-prealpha-0.2.8-453` | `1a0e05c` | iOS `4b2f26f`: pairing reported broken (it was the passcode step) |
| `ios-prealpha-0.2.8-458` | `5c42d82` | Poki Setup 300: pairing QR "data too long" |
| `ios-prealpha-0.2.8-467` | `bff458e` | Poki Setup 301: same QR bug |
| `ios-prealpha-0.2.8-469` | `71e16b7` | Poki Setup 302: Windows installers failed in CI; 304 is the same code |
| `ios-prealpha-0.2.8-472` | `13656d7` | iOS `b8c243a`; replaced by iOS `d7e91b2` |
| `ios-prealpha-0.2.8-478` | `02fd595` | iOS `d7e91b2`; replaced by `2b9ec5b` (approvals off by default) |
| `ios-prealpha-0.2.8-482` | `ecd655d` | iOS `2b9ec5b`; replaced by `8519c32` (Approvals (Testing), auto-classifier, keep-alive) |
| `ios-prealpha-0.2.8-490` | `6c73cff` | iOS `8519c32` and Poki Setup 304; replaced by `41509e8` and Setup 307 |
| **`ios-prealpha-0.2.8-499`** | **this file's commit** | **The release.** iOS `41509e8` and Poki Setup 307 (`c465a5a`) |

`6e46a8e` (the 478 candidate plus this file) was pushed to `standalone` before the approvals change, so the
release is a fast-forward on top of it: the merges `2afe565` (`2b9ec5b`), `8519c32`, `41509e8` and desktop `c465a5a`, with this file's updates; the last one carries the tag.

## The relay (`deploy/cf-relay`)

- A Cloudflare Worker, frames v1 (spec in `docs/ios-core.md`). It stores nothing except a budget
  Durable Object.
- Zhehan's live relay is `poki-relay` at `pokimcp.zheha.nz/v1/*` and `/.well-known/*`. As of Nov 8,
  2:00 am ET it runs the revamp's relay with `REDIRECT_HOSTS` removed: any https redirect plus
  loopback and agent app schemes register, and a callback outside `KNOWN_HOSTS` needs the owner's
  OK on the phone (consent frames, 90 s). That fixed upstream issue #43 (Poke, Meta AI). Rollback:
  version `1d0fc696-2b45-4d58-bccf-caf2aa33acef`.
- Testers update their own relay with Poki Setup's Update Relay, or paste `poki-relay-worker.js`
  into the Worker's Edit code. Address and secret stay the same.

## What was checked

- Pairing works on Zhehan's iPhone 17 Pro (iOS 27.3 beta) with `b8c243a`, after the passcode step (build 145, `d7e91b2`, was being tested when this was written).
- iOS CI is green for `b8c243a` (run 42465254776) and `d7e91b2` (run 42468937314). It is compile-and-package only; simulator
  checks are in the full `ios-app.yml`.
- `cargo check -p poki-setup-core --no-default-features` passes at `02fd595`, and the core's 19
  tests passed at the `8905942` merge.
- `git rev-list --count` of this file's commit is 499, so the tag is `ios-prealpha-0.2.8-499`.

## What was not checked

- `channel-release.yml` has never run end to end. The first real run is the pre-alpha tag itself.
  Watch it: the version job, the `ios-ipa.yml` call and the publish step.
- Installs with anyone else's Apple ID, a free account, another paid team, or on Windows. Free
  accounts allow one development certificate, so an AltStore, SideStore or Xcode certificate on the
  same Apple ID blocks Poki Setup. They also allow 3 apps at a time and 10 App IDs a week (Poki uses
  2). Apple's raw error comes through for the App ID limit.
- The full test list for pre-alpha testers is in the release notes: first install and pairing,
  self-renewal, relay deploy plus an external agent, chat and live voice, and Lock Screen approvals.

## Open items

1. Merge `poki/ios-integration` (`db0e8ea`, PRs #48 to #54) with `standalone`, and resolve voice
   and in-process session conflicts.
2. A `desktop-prealpha-*` or `desktop-v*` release path for Poki Setup in CI, with the notarization
   secrets, so installers no longer come from Zhehan's Mac.
3. A friendly message for Apple's App ID limit on free accounts, and for the one-certificate
   conflict with other sideloading tools.
4. Five stray "Poki Setup on this computer" certificates on team Q64ZL36CJN from early testing
   should be revoked.
5. Poki Runner is still built and documented. Decide whether it stays an option or goes.
6. Known limitations in 499, listed in the release notes as fixes pending: the iOS automation banner stays on
   screen for the whole time an agent works and whenever Poki is awake, and restarting Poki (Off, then on) quits the app and relaunches it, coming back from
   the Tap to Open Poki notice when iOS does not reopen it, because there is one automation session per launch.

## Where things are

- Release notes for this pre-alpha: the GitHub release `ios-prealpha-0.2.8-499`. Testers are told to switch to Alpha after installing; Zhehan tests on Pre-alpha and proven fixes ship as Alpha versions.
- Fork with all `dev/` branches: https://github.com/ZhehanZhang/poki-remote
- Release channels: `docs/release-channels.md`. Poki Setup: `desktop/README.md`,
  `desktop/mac/README.md`. App: `native/ios-app/README.md`. Relay: `deploy/cf-relay/DEPLOY.md`,
  `OPS.md`, `PRIVACY.md`.
