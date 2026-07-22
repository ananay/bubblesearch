#!/bin/sh
# Build BubbleSearch.app, notarize it, and package a signed+notarized
# drag-to-install DMG. The DMG opens with zero Gatekeeper warnings anywhere.
# Usage: ./make-dmg.sh [version]
set -e
cd "$(dirname "$0")"

VERSION="${1:-1.0.6}"
VERSION="$VERSION" ./make-app.sh

IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | sed -E 's/.*"(.*)".*/\1/')}"
HAVE_NOTARY=$(security find-generic-password -s "com.apple.gke.notary.bubblesearch-notary" >/dev/null 2>&1 && echo yes || xcrun notarytool history --keychain-profile bubblesearch-notary >/dev/null 2>&1 && echo yes || echo no)

# Notarize + staple the app BEFORE packaging so the app inside is trusted.
if [ "$HAVE_NOTARY" = "yes" ]; then
    ./notarize.sh build/BubbleSearch.app
fi

STAGING=$(mktemp -d)
cp -R build/BubbleSearch.app "$STAGING/BubbleSearch.app"
ln -s /Applications "$STAGING/Applications"

DMG="build/BubbleSearch-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -volname "BubbleSearch $VERSION" -srcfolder "$STAGING" -ov -format UDZO "$DMG"
rm -rf "$STAGING"

# Sign + notarize + staple the DMG itself so the download opens clean.
if [ -n "$IDENTITY" ] && [ "$HAVE_NOTARY" = "yes" ]; then
    codesign --force --sign "$IDENTITY" --timestamp "$DMG"
    ./notarize.sh "$DMG"
fi

echo "built: $PWD/$DMG"
