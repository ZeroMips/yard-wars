#!/bin/sh
# Publishes the committed state as a signed update (see src/updater.lua):
#   tools/publish.sh              build, sign, upload (.love first, latest.txt last; also
#                                 download/yard-wars.zip for the website), delete old builds
#   tools/publish.sh --local DIR  same, but copy into DIR instead (tests with a local
#                                 http server: love x.love --update-url http://127.0.0.1:8000/)
#   tools/publish.sh --init-key   make the signing key once, print the modulus for
#                                 Updater.PUBLIC_KEY
set -eu
cd "$(dirname "$0")/.."
. tools/publish.conf

modulus() { openssl rsa -in "$KEY" -noout -modulus | cut -d= -f2; }

if [ "${1:-}" = "--init-key" ]; then
    if [ -e "$KEY" ]; then
        echo "publish.sh: $KEY exists already" >&2
    else
        mkdir -p "$(dirname "$KEY")"
        (umask 077 && openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "$KEY")
    fi
    echo "Updater.PUBLIC_KEY (src/updater.lua):"
    modulus
    exit 0
fi

[ -r "$KEY" ] || { echo "publish.sh: no key $KEY (tools/publish.sh --init-key)" >&2; exit 1; }
if ! grep -q "$(modulus)" src/updater.lua; then
    echo "publish.sh: the key doesn't match Updater.PUBLIC_KEY in src/updater.lua" >&2
    exit 1
fi

love=$(tools/build.sh)
file=$(basename "$love")
build=${file#yard-wars-}
build=${build%.love}
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
{
    echo "build $build"
    echo "version $(git log -1 --date=format:'%Y-%m-%d %H:%M' --format='%h %cd')"
    echo "file $file"
    echo "size $(stat -c %s "$love")"
    echo "sha256 $(sha256sum "$love" | cut -d' ' -f1)"
} > "$tmp/signed"
sig=$(openssl dgst -sha256 -sign "$KEY" "$tmp/signed" | xxd -p | tr -d '\n')
{ cat "$tmp/signed"; echo "sig $sig"; } > "$tmp/latest.txt"
printf 'RewriteEngine Off\n' > "$tmp/.htaccess"

if [ "${1:-}" = "--local" ]; then
    dir=${2:?"--local needs a directory"}
    mkdir -p "$dir"
    cp "$love" "$dir/$file"
    cp "$tmp/latest.txt" "$dir/latest.txt"
    echo "published build $build to $dir"
    exit 0
fi

# The web space is small (~5 MB): only the current build stays on the server, and the
# website's download is one file (download/yard-wars.zip; yard-wars.love is a rewrite to it,
# a .love is a zip anyway).
ftp() { curl --fail --silent --show-error --ssl-reqd --netrc --ftp-create-dirs "$@"; }
upload() { ftp -T "$1" "ftp://$FTP_HOST$FTP_DIR/$2"; }
# Builds in /updates/ except $1 (and the new one)
stale() {
    ftp --list-only "ftp://$FTP_HOST$FTP_DIR/" | tr -d '\r' |
        grep '^yard-wars-[0-9]*\.love$' | grep -v -x -e "$1" -e "$file" || true
}
delete() { ftp -o /dev/null -Q "DELE $1" "ftp://$FTP_HOST/"; }

# Make room first: keep only the build latest.txt points to right now
live=$(curl --silent "${HTTP_URL}latest.txt" | sed -n 's/^file //p')
for f in $(stale "$live"); do echo "deleting $f"; delete "$FTP_DIR/$f"; done

upload "$tmp/.htaccess" .htaccess
upload "$love" "$file"
upload "$tmp/latest.txt" latest.txt # last: the game never sees a half-published build
for f in $(stale "$file"); do echo "deleting $f"; delete "$FTP_DIR/$f"; done

printf 'RewriteEngine On\nRewriteRule ^yard-wars\\.love$ yard-wars.zip [L]\n' > "$tmp/download.htaccess"
ftp -T "$tmp/download.htaccess" "ftp://$FTP_HOST/download/.htaccess"
ftp -T "$love" "ftp://$FTP_HOST/download/yard-wars.zip"

echo "published build $build: ${HTTP_URL}latest.txt"
curl --silent --show-error --include "${HTTP_URL}latest.txt" | head -n 12
