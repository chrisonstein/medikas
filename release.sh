#!/usr/bin/env bash
# Publiceert een nieuwe versie: iedereen met MediKas krijgt hem via ‘Zoek naar updates…’ of de dagelijkse controle.
#   1. Verhoog CFBundleShortVersionString én CFBundleVersion in Support/Info.plist
#   2. Optioneel: Support/ReleaseNotes/<versie>.md ("- " punten; getoond in het updatevenster)
#   3. ./release.sh
# Vereist de GitHub CLI, eenmalig ingelogd met: gh auth login
set -euo pipefail
cd "$(dirname "$0")"
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

VERSION="$(plutil -extract CFBundleShortVersionString raw Support/Info.plist)"
NAME="MediKas-$VERSION"
FEED="$(plutil -extract SUFeedURL raw Support/Info.plist)"
REPO="$(echo "$FEED" | sed -E 's|https://github.com/([^/]+/[^/]+)/.*|\1|')"

if gh release view "v$VERSION" --repo "$REPO" >/dev/null 2>&1; then
  echo "v$VERSION bestaat al — verhoog eerst de versie in Support/Info.plist."; exit 1
fi

./package.sh

NOTES_FILE="Support/ReleaseNotes/$VERSION.md"
NOTES_ARGS=(--notes "MediKas $VERSION")
[[ -f "$NOTES_FILE" ]] && NOTES_ARGS=(--notes-file "$NOTES_FILE")

# De nieuwe release wordt ‘latest’, dus …/releases/latest/download/appcast.xml wijst ernaar.
gh release create "v$VERSION" --repo "$REPO" --title "MediKas $VERSION" "${NOTES_ARGS[@]}" \
  "dist/$NAME.zip" "dist/$NAME.dmg" "dist/appcast.xml"
echo "Gepubliceerd: https://github.com/$REPO/releases/tag/v$VERSION"
