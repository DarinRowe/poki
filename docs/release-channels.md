# Release channels

Poki's iPhone builds are published as GitHub Releases on this repository. Poki Setup (the desktop
installer) reads them and lets each person pick a channel in Settings. A channel decides which
releases Poki Setup installs and renews with.

| Channel | Tags | GitHub release | Who it is for |
| --- | --- | --- | --- |
| Stable | `ios-vX.Y.Z` | full release | everyone |
| Beta | `ios-vX.Y.Z` | prerelease | testers (the default while every `ios-v*` release is a prerelease) |
| Alpha | `app-X.Y.Z-alpha.N` (before Nov 9 2026: `ios-alpha-X.Y.Z-N`) | prerelease | early testers: builds picked by a maintainer, rough edges expected |
| Pre-alpha | `app-X.Y.Z-prealpha.N` (before Nov 9 2026: `ios-prealpha-X.Y.Z-N`) | prerelease | developers who want every snapshot |

A channel includes the channels above it: Beta installs the newest Stable or Beta release, Alpha
the newest Stable, Beta or Alpha, and Pre-alpha the newest release of any kind. Poki Setup's own
updates (`desktop-v*`, `desktop-alpha-*` and `desktop-prealpha-*` tags) follow the same channel.

## Cutting a release

- Stable or Beta: push `ios-vX.Y.Z` (`.github/workflows/release.yml`). It is published as a
  prerelease (Beta); to promote it to Stable, untick "Set as a pre-release" on the release page.
- Alpha or Pre-alpha: run `native/ios-app/scripts/cut-release.sh alpha` or `... pre-alpha` (defaults
  to the head of `poki/ios-integration`; pass another ref as the second argument). It tags the commit
  `app-<VERSION>-alpha.<commit count>` or `app-<VERSION>-prealpha.<commit count>` and pushes the tag;
  `.github/workflows/channel-release.yml` builds the app and puts it into the channel's one rolling
  prerelease, `app-alpha-latest` or `app-prealpha-latest`, mirrored to `ios-alpha-latest` or `ios-prealpha-latest` for apps and Poki Setup that read only those (replacing the previous build's files, title
  and notes, so the Releases page never fills up with test builds), with the same files as a Beta: `Poki-external-*.ipa`, `Poki-*.ipa`, `Poki-signing.zip`, `poki-relay-worker.js` (the relay Worker Poki Setup deploys) and `SHA256SUMS`. The build
  number is the commit count, so a later commit always has a bigger one. The versioned tag stays as
  the record of each build; Poki Setup reads the version from the IPA's name. Poki Setup's own
  installers (`PokiSetup-<version>-<build>-macos.dmg` / `-windows-x64-setup.exe` with
  `SHA256SUMS-desktop.txt`) are added to the same rolling release and replaced the same way. Only a
  Stable release is ever marked Latest. The same commit can be both a
  pre-alpha and, once it looks good, an alpha. `DRY_RUN=1` prints the tag without pushing it.

Both workflows run only on their tags, never on branch pushes. The Mac server's update notice
(`src/update-check.mjs`) reads `releases/latest`, which never returns a prerelease, so neither Beta
nor Alpha nor Pre-alpha releases reach it.
