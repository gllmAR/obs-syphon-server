#!/usr/bin/env bash
# release.sh — bump version in CMakeLists.txt, tag, push.
#
# Usage:
#   ./release.sh <version>     # e.g. ./release.sh 2.0.1
#   ./release.sh patch|minor|major
#
# What it does:
#   1. Refuses to run if the working tree is dirty or you're not on master/main.
#   2. Refuses if the tag already exists locally or on origin.
#   3. Updates `project(... VERSION X.Y.Z ...)` in CMakeLists.txt.
#   4. Commits the bump, creates an annotated tag vX.Y.Z, pushes both.
#   5. The push triggers the build workflow → GitHub Release with the .plugin.zip.

set -euo pipefail

cd "$(dirname "$0")"

die() { echo "error: $*" >&2; exit 1; }

[[ $# -eq 1 ]] || die "usage: $0 <version|patch|minor|major>"

# --- preflight ---------------------------------------------------------------
branch=$(git rev-parse --abbrev-ref HEAD)
[[ "$branch" == "master" || "$branch" == "main" ]] \
  || die "must be on master/main (currently on '$branch')"

[[ -z "$(git status --porcelain)" ]] \
  || die "working tree not clean — commit or stash first"

git fetch --tags origin >/dev/null

current=$(awk -F'[ )]' '/project\(/{for(i=1;i<=NF;i++) if($i=="VERSION") print $(i+1)}' CMakeLists.txt)
[[ -n "$current" ]] || die "could not extract current VERSION from CMakeLists.txt"

# --- compute new version -----------------------------------------------------
arg=$1
case "$arg" in
  major|minor|patch)
    IFS=. read -r maj min pat <<< "$current"
    case "$arg" in
      major) maj=$((maj+1)); min=0; pat=0 ;;
      minor) min=$((min+1)); pat=0 ;;
      patch) pat=$((pat+1)) ;;
    esac
    new="${maj}.${min}.${pat}"
    ;;
  [0-9]*.[0-9]*.[0-9]*)
    new=$arg
    ;;
  *)
    die "version must be 'major'|'minor'|'patch' or 'X.Y.Z' (got '$arg')"
    ;;
esac

tag="v${new}"
git rev-parse -q --verify "refs/tags/${tag}" >/dev/null 2>&1 \
  && die "tag ${tag} already exists locally"
git ls-remote --exit-code --tags origin "refs/tags/${tag}" >/dev/null 2>&1 \
  && die "tag ${tag} already exists on origin"

echo "  current: ${current}"
echo "  new:     ${new}"
read -r -p "Proceed? [y/N] " ok
[[ "$ok" == "y" || "$ok" == "Y" ]] || { echo "aborted"; exit 1; }

# --- bump, commit, tag, push -------------------------------------------------
# Match the exact `VERSION X.Y.Z` token inside the project() line.
sed -i.bak -E "s/(project\\([^)]*VERSION )${current//./\\.}( )/\\1${new}\\2/" CMakeLists.txt
rm -f CMakeLists.txt.bak

# Sanity-check the rewrite worked
got=$(awk -F'[ )]' '/project\(/{for(i=1;i<=NF;i++) if($i=="VERSION") print $(i+1)}' CMakeLists.txt)
[[ "$got" == "$new" ]] || die "version bump failed (CMakeLists shows '$got')"

git add CMakeLists.txt
git commit -m "Release ${tag}"
git tag -a "${tag}" -m "Release ${tag}"
git push origin "${branch}"
git push origin "${tag}"

echo
echo "  Pushed ${tag}. CI will publish the release at:"
echo "  https://github.com/gllmAR/obs-syphon-server/releases/tag/${tag}"
