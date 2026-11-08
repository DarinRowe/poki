#!/usr/bin/env bash
# Cuts a Poki pre-alpha: tags a commit ios-prealpha-<VERSION>-<commit count> and pushes the tag, which
# starts .github/workflows/prealpha.yml (build, then a GitHub prerelease). The commit must already be
# on the remote and must contain prealpha.yml.
#
#   native/ios-app/scripts/cut-prealpha.sh [ref] [remote]    # defaults: origin/poki/ios-integration, origin
#   DRY_RUN=1 native/ios-app/scripts/cut-prealpha.sh          # print the tag, push nothing
set -euo pipefail

remote="${2:-origin}"
ref="${1:-$remote/poki/ios-integration}"
git fetch --quiet "$remote" --tags
git fetch --quiet "$remote" "+refs/heads/*:refs/remotes/$remote/*"

sha="$(git rev-parse --verify "$ref^{commit}")"
git cat-file -e "$sha:.github/workflows/prealpha.yml" 2>/dev/null || { echo "$ref has no .github/workflows/prealpha.yml, so a tag there would build nothing." >&2; exit 1; }
if ! git branch -r --contains "$sha" | grep -q "^ *$remote/"; then
  echo "$sha is not on $remote yet. Push it first." >&2; exit 1
fi
version="$(git show "$sha:native/ios-app/VERSION" | tr -d ' \n')"
build="$(git rev-list --count "$sha")"
tag="ios-prealpha-$version-$build"

if git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
  echo "$tag already exists (this commit, or one with the same count, was already cut)." >&2; exit 1
fi
echo "Poki $version ($build) from $(git log -1 --format='%h %s' "$sha")"
echo "tag: $tag"
[ "${DRY_RUN:-}" = 1 ] && exit 0
git tag -a "$tag" -m "Poki $version ($build) pre-alpha" "$sha"
git push "$remote" "refs/tags/$tag"
echo "Pushed. Follow the build under Actions > Pre-alpha."
