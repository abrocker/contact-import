#!/bin/bash
# Baut ContactImporter.app aus main.swift + Info.plist
set -e

cd "$(dirname "$0")"

APP_NAME="ContactImporter"
BIN_NAME="ContactImporter"

echo "Kompiliere $BIN_NAME ..."
# Universal Binary, damit die App auf Apple-Silicon- und Intel-Macs läuft.
swiftc -O -target arm64-apple-macos26.0 -o "$BIN_NAME-arm64" main.swift -framework Cocoa -framework Contacts
swiftc -O -target x86_64-apple-macos26.0 -o "$BIN_NAME-x86_64" main.swift -framework Cocoa -framework Contacts
lipo -create -output "$BIN_NAME" "$BIN_NAME-arm64" "$BIN_NAME-x86_64"
rm -f "$BIN_NAME-arm64" "$BIN_NAME-x86_64"

echo "Baue App-Bundle ..."
rm -rf "$APP_NAME.app"
mkdir -p "$APP_NAME.app/Contents/MacOS"
mkdir -p "$APP_NAME.app/Contents/Resources"
cp "$BIN_NAME" "$APP_NAME.app/Contents/MacOS/"
cp Info.plist "$APP_NAME.app/Contents/Info.plist"
if [ -f AppIcon.icns ]; then
  cp AppIcon.icns "$APP_NAME.app/Contents/Resources/AppIcon.icns"
fi
rm -f "$BIN_NAME"

# Entfernt eine eventuelle Quarantäne-Markierung, damit macOS die App
# beim ersten Start nicht als "aus dem Internet" blockiert.
xattr -cr "$APP_NAME.app" 2>/dev/null || true

# Ganzes Bundle ad-hoc signieren. Ohne diese Signatur meldet macOS die App
# auf anderen Macs als "beschädigt".
chmod 644 "$APP_NAME.app/Contents/Resources/"* 2>/dev/null || true
codesign --force --deep --sign - "$APP_NAME.app"
codesign --verify --strict "$APP_NAME.app"

# ZIP zum Weitergeben (ditto erhält Signatur und Bundle-Struktur).
rm -f "$APP_NAME.zip"
ditto -c -k --keepParent "$APP_NAME.app" "$APP_NAME.zip"

echo ""
echo "Fertig: $APP_NAME.app"
echo "Verschiebe die App z.B. mit:"
echo "  mv $APP_NAME.app /Applications/"
echo ""
echo "Zum Weitergeben: $APP_NAME.zip"
echo "Auf dem anderen Mac nach dem Entpacken einmalig:"
echo "  xattr -cr /Applications/$APP_NAME.app"
echo "oder: Systemeinstellungen > Datenschutz & Sicherheit > 'Trotzdem öffnen'."
