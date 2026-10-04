#!/bin/sh
# Publishes the committed state as a signed update (see src/updater.lua):
#   tools/publish.sh              build, sign, upload (.love first, latest.txt last; also
#                                 download/yard-wars.love + .zip for the website)
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

upload() {
    curl --fail --silent --show-error --ssl-reqd --netrc --ftp-create-dirs \
        -T "$1" "ftp://$FTP_HOST$FTP_DIR/$2"
}
upload "$tmp/.htaccess" .htaccess
upload "$love" "$file"
# Stable names for the website's download links (a .love is a zip: Android users unzip it)
curl --fail --silent --show-error --ssl-reqd --netrc --ftp-create-dirs \
    -T "$love" "ftp://$FTP_HOST/download/yard-wars.love"
curl --fail --silent --show-error --ssl-reqd --netrc --ftp-create-dirs \
    -T "$love" "ftp://$FTP_HOST/download/yard-wars.zip"
upload "$tmp/latest.txt" latest.txt # last: the game never sees a half-published build
echo "published build $build: ${HTTP_URL}latest.txt"
curl --silent --show-error --include "${HTTP_URL}latest.txt" | head -n 12
