# Contributing

Open an issue before a large change. For a small fix, open a pull request into `main` from a `dev/<topic>` branch. Branches, checks and how releases are made: [AGENTS.md](AGENTS.md#contribute-code) and [docs/release-channels.md](docs/release-channels.md).

Run `npm test` before you submit. Say in the pull request whether you also tested on a Simulator or a physical iPhone.

## How to open a pull request

You do not have write access to `JosssphZhou/poki`, so `git push` to it fails with `permission denied`. That is expected. Push to your own fork and open the pull request from there.

With the GitHub CLI, from your clone with the branch already made:

```sh
gh repo fork --remote            # creates your fork, adds it as origin, renames the old origin to upstream
git push -u origin <branch>
gh pr create --base main
```

Without it: click **Fork** on GitHub, then

```sh
git remote add fork https://github.com/<you>/poki.git
git push -u fork <branch>
```

and open a pull request from that branch into `main` of `JosssphZhou/poki` on the website.

Before you open it, run `npm test` and fill in the [pull request template](.github/PULL_REQUEST_TEMPLATE.md): what changes, how you tested it, and the two checkboxes. The `PR checks` workflow must pass.

By submitting a contribution, you release it under the [AGPL-3.0-only license](LICENSE).

Use third-party code only if its license is compatible with AGPL-3.0-only. Keep the original copyright notice and list the code in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

Do not commit device screenshots, clipboard contents, pairing records, passcodes, or tokens.
