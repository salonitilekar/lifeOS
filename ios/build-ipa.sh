#!/usr/bin/env bash
# Build an unsigned LifeOS.ipa locally (requires full Xcode + XcodeGen).
# SideStore / AltStore will re-sign the IPA with your Apple ID at install time.
set -euo pipefail

cd "$(dirname "$0")"

if ! command -v xcodebuild >/dev/null 2>&1 || ! xcodebuild -version >/dev/null 2>&1; then
  echo "ERROR: full Xcode is required (Command Line Tools alone is not enough)."
  echo "Install Xcode from the App Store, then: sudo xcode-select -s /Applications/Xcode.app"
  exit 1
fi

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "ERROR: xcodegen not found. Install with: brew install xcodegen"
  echo "(or download a release from https://github.com/yonaskolb/XcodeGen/releases)"
  exit 1
fi

echo "==> Staging web assets"
rm -rf www
mkdir -p www
cp ../index.html www/index.html

echo "==> Generating Xcode project"
xcodegen generate

echo "==> Building unsigned app"
xcodebuild \
  -project LifeOS.xcodeproj \
  -scheme LifeOS \
  -configuration Release \
  -sdk iphoneos \
  -derivedDataPath build \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  clean build

echo "==> Packaging IPA"
APP="build/Build/Products/Release-iphoneos/LifeOS.app"
rm -rf Payload LifeOS.ipa
mkdir -p Payload
cp -R "$APP" Payload/
zip -r LifeOS.ipa Payload >/dev/null
rm -rf Payload

echo "==> Done: $(pwd)/LifeOS.ipa"
