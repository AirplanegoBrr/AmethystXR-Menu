#!/bin/sh
# Builds Amlib and copies its .aar files into addons/amlib/bin for the Android export.
# Usage: tools/update_amlib.sh [path to the Amlib repo] [debug|release]
set -e
AMLIB=${1:-../Amlib}
VARIANT=${2:-debug}
BIN="$(cd "$(dirname "$0")/.." && pwd)/addons/amlib/bin"
VARIANT_CAP=$(printf '%s' "$VARIANT" | sed 's/^./\U&/')

(cd "$AMLIB" && ./gradlew ":app_pojavlauncher:assemble$VARIANT_CAP" ":androidnsbypass:assemble$VARIANT_CAP")

rm -rf "$BIN" && mkdir -p "$BIN"
cp "$AMLIB/app_pojavlauncher/build/outputs/aar/app_pojavlauncher-$VARIANT.aar" "$BIN/amlib.aar"
cp "$AMLIB/androidnsbypass/build/outputs/aar/androidnsbypass-$VARIANT.aar" "$BIN/androidnsbypass.aar"
# Libraries Amlib compiles against but can't bundle (renderers, SDL, LWJGL natives, ...)
cp "$AMLIB"/app_pojavlauncher/libs/*.aar "$BIN/"
echo "Amlib ($VARIANT) copied to $BIN"
