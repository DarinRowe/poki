# Release channels

Poki's iPhone builds are published as GitHub Releases on this repository. Poki Setup (the desktop
installer) reads them and lets each person pick a channel in Settings. A channel decides which
releases Poki Setup installs and renews with.

| Channel | Tags | GitHub release | Who it is for |
| --- | --- | --- | --- |
| Stable | `ios-vX.Y.Z` | full release | everyone |
| Beta | `ios-vX.Y.Z` | prerelease | testers (the default while every `ios-v*` release is a prerelease) |
| Pre-alpha | `ios-prealpha-X.Y.Z-N` | prerelease | developers who want every snapshot |

A channel includes the channels above it: Beta installs the newest Stable or Beta release, and
Pre-alpha installs the newest release of any kind. Poki Setup's own updates (`desktop-v*` and
`desktop-prealpha-*` tags) follow the same channel.

## Cutting a release

- Stable or Beta: push `ios-vX.Y.Z` (`.github/workflows/release.yml`). It is published as a
  prerelease (Beta); to promote it to Stable, untick "Set as a pre-release" on the release page.
- Pre-alpha: run `native/ios-app/scripts/cut-prealpha.sh` (defaults to the head of
  `poki/ios-integration`; pass another ref as the first argument). It tags the commit
  `ios-prealpha-<VERSION>-<commit count>` and pushes the tag; `.github/workflows/prealpha.yml`
  builds the app and publishes the prerelease with the same files as a Beta: `Poki-external-*.ipa`,
  `Poki-*.ipa`, `Poki-signing.zip` and `SHA256SUMS`. The build number is the commit count, so a later
  commit always has a bigger one. `DRY_RUN=1` prints the tag without pushing it.

Both workflows run only on their tags, never on branch pushes. The Mac server's update notice
(`src/update-check.mjs`) reads `releases/latest`, which never returns a prerelease, so neither Beta
nor Pre-alpha releases reach it.
