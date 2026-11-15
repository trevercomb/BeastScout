#!/usr/bin/env bash
# Upload a release zip to WoWInterface (project 27309) with its own API.
# The BigWigs packager skips WoWInterface for Forever builds, so the release
# workflow calls this instead. Needs WOWI_API_TOKEN in the environment.
#   tools/upload_wowi.sh <zip> <tag, e.g. v0.12.3>
# Listed as Classic 1.15.7; the changelog is that version's section of
# CHANGELOG.md. WoWInterface answers 202 when it accepts the file.
set -euo pipefail

zip="${1:?zip path}"
tag="${2:?tag}"
[ -f "$zip" ] || { echo "No such zip: $zip"; exit 1; }
[ -n "${WOWI_API_TOKEN:-}" ] || { echo "WOWI_API_TOKEN isn't set"; exit 1; }

awk -v v="## ${tag#v}" '$0 == v {on=1; next} /^## / {on=0} on' CHANGELOG.md > wowi-changelog.txt
echo "Uploading $zip as $tag with $(grep -c '^- ' wowi-changelog.txt) changelog lines"

status=$(curl -sS -o wowi-response.txt -w "%{http_code}" \
  -H "x-api-token: $WOWI_API_TOKEN" \
  -F "id=27309" -F "version=$tag" -F "compatible=1.15.7" \
  -F "changelog=<wowi-changelog.txt" -F "updatefile=@$zip" \
  https://api.wowinterface.com/addons/update)
cat wowi-response.txt; echo
if [ "$status" != "202" ]; then echo "WoWInterface upload failed (HTTP $status)"; exit 1; fi
echo "WoWInterface accepted it."
