#!/usr/bin/env bash
# Maakt een deelbare MediKas in ./dist:
#   dist/MediKas-<versie>.dmg   schijfkopie: slepen naar Programma's, met installatie-uitleg
#   dist/MediKas-<versie>.zip   dezelfde app als zip (gebruikt voor updates)
#   dist/appcast.xml            update-feed, ondertekend met de Sparkle-sleutel
# Universeel (Apple silicon + Intel), macOS 14+, ondertekend met "MediKas Local Signing"
# (niet genotariseerd — eenmalig toestaan, zie Support/INSTALL.txt).
set -euo pipefail
cd "$(dirname "$0")"

if ! security find-identity -p codesigning | grep -q "MediKas Local Signing"; then
  echo "Draai eerst Support/setup-signing.sh, zodat elke release dezelfde handtekening heeft."
  exit 1
fi

UNIVERSAL=1 ./build.sh

VERSION="$(plutil -extract CFBundleShortVersionString raw Support/Info.plist)"
NAME="MediKas-$VERSION"
DIST="dist"
mkdir -p "$DIST"
rm -f "$DIST/$NAME.dmg" "$DIST/$NAME.zip" "$DIST/appcast.xml"

# Schijfkopie: de app, een snelkoppeling naar Programma's en de installatie-uitleg.
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R build/MediKas.app "$STAGE/"
ln -s /Applications "$STAGE/Programma's"
cp Support/INSTALL.txt "$STAGE/Zo installeer je MediKas.txt"
hdiutil create -quiet -volname "MediKas $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DIST/$NAME.dmg"

# Zip (ditto houdt de handtekening intact).
ditto -c -k --keepParent build/MediKas.app "$DIST/$NAME.zip"

# Sparkle-appcast: de app leest die uit de nieuwste GitHub-release (SUFeedURL in Info.plist).
# De zip wordt ondertekend met de privésleutel in je sleutelhanger (account "MediKas").
BUILD="$(plutil -extract CFBundleVersion raw Support/Info.plist)"
MIN_OS="$(plutil -extract LSMinimumSystemVersion raw Support/Info.plist)"
FEED="$(plutil -extract SUFeedURL raw Support/Info.plist)"
REPO="$(echo "$FEED" | sed -E 's|https://github.com/([^/]+/[^/]+)/.*|\1|')"
SIGN_UPDATE="$(find .build/artifacts -path "*Sparkle/bin/sign_update" | head -1)"
ED="$("$SIGN_UPDATE" --account MediKas "$DIST/$NAME.zip")"   # sparkle:edSignature="…" length="…"
# Release notes: Support/ReleaseNotes/<versie>.md, één "- " punt per regel (optioneel).
NOTES_FILE="Support/ReleaseNotes/$VERSION.md"
NOTES_HTML=""
if [[ -f "$NOTES_FILE" ]]; then
  NOTES_HTML="<ul>$(sed -nE 's/^[-*] (.*)$/<li>\1<\/li>/p' "$NOTES_FILE" | tr -d '\n')</ul>"
fi
cat > "$DIST/appcast.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>MediKas</title>
    <item>
      <title>Versie $VERSION</title>
      <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$MIN_OS</sparkle:minimumSystemVersion>
      <description><![CDATA[$NOTES_HTML]]></description>
      <enclosure url="https://github.com/$REPO/releases/download/v$VERSION/$NAME.zip" type="application/octet-stream" $ED />
    </item>
  </channel>
</rss>
XML

codesign --verify --deep --strict build/MediKas.app && echo "Handtekening OK"
echo "Klaar om te delen:"
ls -lh "$DIST/$NAME.dmg" "$DIST/$NAME.zip" "$DIST/appcast.xml" | awk '{print "  " $NF "  (" $5 ")"}'
