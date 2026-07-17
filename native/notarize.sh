#!/bin/sh
# Notarize + staple a path (app or dmg) with Apple.
# Requires a stored notarytool keychain profile "bubblesearch-notary".
# Usage: ./notarize.sh <path-to-app-or-dmg>
set -e
TARGET="$1"
PROFILE="bubblesearch-notary"
[ -z "$TARGET" ] && { echo "usage: ./notarize.sh <path>"; exit 1; }

case "$TARGET" in
    *.app)
        # notarytool needs a zip/dmg/pkg; zip the app for submission.
        SUB="$(dirname "$TARGET")/_notarize-submit.zip"
        ditto -c -k --keepParent "$TARGET" "$SUB"
        ;;
    *) SUB="$TARGET" ;;
esac

echo "submitting $(basename "$TARGET") to Apple notary…"
xcrun notarytool submit "$SUB" --keychain-profile "$PROFILE" --wait

echo "stapling…"
xcrun stapler staple "$TARGET"
xcrun stapler validate "$TARGET"

[ "$SUB" != "$TARGET" ] && rm -f "$SUB"
echo "notarized + stapled: $TARGET"
