#!/bin/sh
# Assemble a double-clickable BubbleSearch.app from a release build.
# VERSION env (default 1.0.0) sets the bundle version.
set -e
cd "$(dirname "$0")"

VERSION="${VERSION:-1.0.2}"
PUBKEY=$(cat sparkle-public-ed-key.txt)

swift build -c release

APP="build/BubbleSearch.app"
rm -rf "$APP" build/isearch.app
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp .build/release/bubblesearch "$APP/Contents/MacOS/BubbleSearch"

# Embed Sparkle (rpath @executable_path/../Frameworks is set in Package.swift)
cp -R .build/release/Sparkle.framework "$APP/Contents/Frameworks/"

# Copy the SPM resource bundle if the package declares any resources.
# (Tapback glyphs are NOT bundled — they load at runtime from the user's
# own macOS via CoreUI, so we ship no Apple artwork.)
if [ -d .build/release/bubblesearch_bubblesearch.bundle ]; then
    cp -R .build/release/bubblesearch_bubblesearch.bundle "$APP/Contents/Resources/"
fi

# App icon
cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>BubbleSearch</string>
    <key>CFBundleDisplayName</key>     <string>BubbleSearch</string>
    <key>CFBundleIdentifier</key>      <string>com.ananayarora.bubblesearch</string>
    <key>CFBundleExecutable</key>      <string>BubbleSearch</string>
    <key>CFBundleVersion</key>         <string>$VERSION</string>
    <key>CFBundleShortVersionString</key> <string>$VERSION</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleIconFile</key>        <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>  <string>14.0</string>
    <key>NSHighResolutionCapable</key> <true/>
    <key>NSHumanReadableCopyright</key> <string>Local-only iMessage search. Nothing leaves this Mac except an optional anonymous daily ping.</string>
    <key>SUFeedURL</key>               <string>https://bst.0xaa.io/appcast.xml</string>
    <key>SUPublicEDKey</key>           <string>$PUBKEY</string>
    <key>SUEnableAutomaticChecks</key> <true/>
</dict>
</plist>
EOF

# ── Code signing ──
# Prefer Developer ID + hardened runtime (notarizable); fall back to ad-hoc
# for local dev builds when no Developer ID cert is present.
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | sed -E 's/.*"(.*)".*/\1/')}"
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"

if [ -n "$IDENTITY" ]; then
    echo "signing with: $IDENTITY"
    # Sign nested Sparkle helpers first (deepest → shallowest), hardened + timestamped.
    for item in \
        "$SPARKLE/Versions/B/XPCServices/Downloader.xpc" \
        "$SPARKLE/Versions/B/XPCServices/Installer.xpc" \
        "$SPARKLE/Versions/B/Updater.app" \
        "$SPARKLE/Versions/B/Autoupdate" \
        "$SPARKLE"; do
        codesign --force --options runtime --timestamp --sign "$IDENTITY" "$item"
    done
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
    codesign --verify --deep --strict "$APP" && echo "signature verified"
else
    echo "no Developer ID cert — ad-hoc signing (runs locally, not distributable)"
    codesign --force --sign - --deep "$SPARKLE"
    codesign --force --sign - "$APP"
fi

echo "built: $PWD/$APP (v$VERSION)"
