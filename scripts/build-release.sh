#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT="${GIMME_OUTPUT_DIR:-$ROOT/build}"
VERSION="${GIMME_VERSION:-0.1.0}"
BUILD_NUMBER="${GIMME_BUILD_NUMBER:-1}"
ARCH="${GIMME_ARCH:-universal}"
UNSIGNED=false
for arg in "$@"; do
  case "$arg" in
    --unsigned) UNSIGNED=true ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ || ! "$BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
  echo "GIMME_VERSION must be MAJOR.MINOR.PATCH; build number must be numeric." >&2; exit 2
fi
cd "$ROOT/web"
npm ci
npm test
npm run build
cd "$ROOT"
mkdir -p "$OUTPUT"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
APP="$STAGE/GimmeRemote.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Web"
cp mac/Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"
cp -R web/dist/. "$APP/Contents/Resources/Web/"

case "$ARCH" in
  universal) architectures=(arm64 x86_64) ;;
  arm64|x86_64) architectures=("$ARCH") ;;
  *) echo "GIMME_ARCH must be universal, arm64 or x86_64" >&2; exit 2 ;;
esac
for architecture in "${architectures[@]}"; do
  swift build --package-path mac -c release --arch "$architecture" --jobs 4 --disable-index-store
  BIN="$(swift build --package-path mac -c release --arch "$architecture" --show-bin-path)"
  mkdir -p "$STAGE/$architecture"
  cp "$BIN/GimmeRemote" "$BIN/gimme" "$STAGE/$architecture/"
  # SwiftPM dependency resource bundles (e.g. privacy manifests) accompany the executable.
  while IFS= read -r -d '' bundle; do
    resource="$APP/Contents/Resources/$(basename "$bundle")"
    if [[ -d "$resource" ]]; then
      # Privacy manifests are architecture-neutral and may be read-only.
      # Verify duplicates instead of overwriting the first architecture's files.
      diff -qr "$bundle" "$resource"
    else
      cp -R "$bundle" "$APP/Contents/Resources/"
    fi
  done < <(find "$BIN" -maxdepth 1 -name '*.bundle' -print0)
done
for executable in GimmeRemote gimme; do
  if [[ "$ARCH" == universal ]]; then
    lipo -create "$STAGE/arm64/$executable" "$STAGE/x86_64/$executable" -output "$APP/Contents/MacOS/$executable"
  else
    cp "$STAGE/$ARCH/$executable" "$APP/Contents/MacOS/$executable"
  fi
done
if [[ "$UNSIGNED" == false ]]; then
  # Ad-hoc signing needs no certificate, account, keychain import or Apple service.
  # Sign the embedded CLI first, then seal the App after combining architectures.
  codesign --force --options runtime --timestamp=none --sign - "$APP/Contents/MacOS/gimme"
  codesign --force --options runtime --timestamp=none --sign - "$APP"
  codesign --verify --strict --all-architectures --verbose=2 "$APP/Contents/MacOS/gimme"
  codesign --verify --deep --strict --all-architectures --verbose=2 "$APP"
fi
DESTINATION="$OUTPUT/GimmeRemote.app"
if [[ -e "$DESTINATION" ]]; then
  echo "Output already exists: $DESTINATION. Choose a fresh GIMME_OUTPUT_DIR." >&2; exit 1
fi
cp -R "$APP" "$DESTINATION"
if [[ "$UNSIGNED" == false ]]; then
  ZIP="$OUTPUT/GimmeRemote-$VERSION-$ARCH.zip"
  ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
  (cd "$OUTPUT" && shasum -a 256 "$(basename "$ZIP")" > SHA256SUMS)
  echo "Ad-hoc signed release (not notarized): $ZIP"
else
  echo "Unsigned validation bundle (not for distribution): $DESTINATION"
fi
