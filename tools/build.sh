#!/bin/sh
# Packs the committed state (HEAD) into dist/yard-wars-<build>.love with build.txt
# (build number = commit count, only ever grows) and version.txt (shown in the lobby).
# Without build.txt (git checkout) the game never updates itself, see src/updater.lua.
# Prints the path of the .love file.
set -eu
cd "$(dirname "$0")/.."
if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
    echo "build.sh: uncommitted changes - commit first" >&2
    exit 1
fi
build=$(git rev-list --count HEAD)
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
git archive HEAD | tar -x -C "$tmp"
echo "$build" > "$tmp/build.txt"
git log -1 --date=format:'%Y-%m-%d %H:%M' --format='%h %cd' > "$tmp/version.txt"
mkdir -p dist
out="$PWD/dist/yard-wars-$build.love"
rm -f -- "$out"
(cd "$tmp" && zip -q -9 -r -X "$out" .)
echo "$out"
