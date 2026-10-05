#!/bin/sh
# Uploads the static website (website/) to the web root of yardwars.zeromips.org via FTPS
# (login in ~/.netrc, see tools/publish.conf). The game downloads it links to
# (download/yard-wars.love + .zip) are uploaded by tools/publish.sh.
set -eu
cd "$(dirname "$0")/../website"
. ../tools/publish.conf
# The legal pages must be filled in before anything goes online
if grep -rl "TODO-" --include="*.html" .; then
    echo "placeholders (TODO-...) left in the files above - not uploading" >&2
    exit 1
fi
find . -type f | sed 's|^\./||' | sort | while read -r f; do
    echo "uploading $f"
    curl --fail --silent --show-error --ssl-reqd --netrc --ftp-create-dirs \
        -T "$f" "ftp://$FTP_HOST/$f"
done
echo "done: ${HTTP_URL%updates/}"
