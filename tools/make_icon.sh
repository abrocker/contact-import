#!/bin/bash
# Erzeugt AppIcon.icns aus tools/make_icon.swift
set -e

cd "$(dirname "$0")/.."

TMP=$(mktemp -d)
ICONSET="$TMP/AppIcon.iconset"
mkdir -p "$ICONSET"

swift tools/make_icon.swift "$TMP/icon_1024.png"

for s in 16 32 128 256 512; do
  sips -z $s $s "$TMP/icon_1024.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  d=$((s * 2))
  sips -z $d $d "$TMP/icon_1024.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done

iconutil -c icns "$ICONSET" -o AppIcon.icns
mkdir -p docs
sips -z 256 256 "$TMP/icon_1024.png" --out docs/icon.png >/dev/null
rm -rf "$TMP"
echo "Fertig: AppIcon.icns"
