#!/usr/bin/env bash
# Builds Ardia's iPhone/iPad app (apps/phone) and installs it on your own iPad or iPhone over USB,
# signed with a free Apple ID ("Personal Team"). See IPAD.md.
#
# The signing changes it makes (your bundle id, no App Group) stay in your working tree only.
# Never commit them: `scripts/ipad/build-for-my-ipad.sh --undo` puts the files back.
#
#   scripts/ipad/build-for-my-ipad.sh                      # finds your team and the connected device
#   scripts/ipad/build-for-my-ipad.sh --team ABCDE12345 --bundle-prefix com.yourname.ardia --device <UDID>
#   scripts/ipad/build-for-my-ipad.sh --undo               # restore the signing files
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
IOS="$ROOT/apps/phone/ios"
PBXPROJ="$IOS/Ardia.xcodeproj/project.pbxproj"
ENTITLEMENTS=("$IOS/Config/Ardia.entitlements" "$IOS/Config/Open.entitlements" "$IOS/Config/Share.entitlements" "$IOS/Config/Widgets.entitlements")
DERIVED="${DERIVED_DATA:-$HOME/Library/Developer/Xcode/DerivedData/ardia-phone-device}"

TEAM="" PREFIX="" DEVICE="" UNDO=0 SKIP_INSTALL=0
while [ $# -gt 0 ]; do
  case "$1" in
    --team) TEAM="$2"; shift 2 ;;
    --bundle-prefix) PREFIX="$2"; shift 2 ;;
    --device) DEVICE="$2"; shift 2 ;;
    --undo) UNDO=1; shift ;;
    --build-only) SKIP_INSTALL=1; shift ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "Unknown option: $1 (try --help)" >&2; exit 2 ;;
  esac
done

trap 'printf "\nError: the step above failed (line %s). Scroll up for its message.\n" "$LINENO" >&2' ERR

say() { printf '\n==> %s\n' "$*"; }
die() { printf '\nError: %s\n' "$*" >&2; exit 1; }

if [ "$UNDO" = 1 ]; then
  git -C "$ROOT" checkout -- "$PBXPROJ" "${ENTITLEMENTS[@]}"
  echo "Restored the project file and entitlements to what's committed."
  exit 0
fi

say "Checking tools"
command -v xcodebuild >/dev/null || die "Xcode isn't installed. Install it from the App Store, open it once, then run this again."
command -v pnpm >/dev/null || die "pnpm is missing. Install it with: brew install pnpm"
command -v pod >/dev/null || die "CocoaPods is missing. Install it with: brew install cocoapods"
xcodebuild -version | sed -n 1p

if [ -z "$TEAM" ]; then
  TEAM="$(security find-certificate -a -c "Apple Development" -p 2>/dev/null | openssl x509 -noout -subject 2>/dev/null | sed -nE 's/.*OU ?= ?([A-Z0-9]{10}).*/\1/p' | sed -n 1p || true)"
  [ -n "$TEAM" ] || die "Couldn't find your team. Sign in to Xcode › Settings › Accounts with your Apple ID, then pass --team <TEAM ID> (shown there)."
  echo "Team: $TEAM (from your Apple Development certificate)"
fi

if [ -z "$PREFIX" ]; then
  PREFIX="com.$(whoami | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9').ardia"
fi
[[ "$PREFIX" =~ ^[A-Za-z0-9.-]+$ ]] || die "--bundle-prefix may only hold letters, digits, dots and hyphens."
echo "Bundle id: $PREFIX (app), $PREFIX.share, $PREFIX.open, $PREFIX.widgets"

if [ -z "$DEVICE" ] && [ "$SKIP_INSTALL" = 0 ]; then
  DEVICES="$(xcrun devicectl list devices 2>/dev/null | awk '/ connected / && /physical/ && /(iPad|iPhone)/ { for (i = 1; i <= NF; i++) if ($i ~ /^[0-9A-F]{8}-[0-9A-F]{16}$/) print ($0 ~ /iPad/ ? "1" : "2"), $i }' | sort | cut -d' ' -f2)"
  DEVICE="$(printf '%s\n' "$DEVICES" | sed -n 1p)"
  [ "$(printf '%s\n' "$DEVICES" | grep -c .)" -gt 1 ] && echo "More than one device is connected; using $DEVICE. Pass --device <UDID> to choose."
  [ -n "$DEVICE" ] || die "No iPad or iPhone is connected. Plug it in with a data cable, unlock it, tap Trust, and turn on Settings › Privacy & Security › Developer Mode."
fi
[ -n "$DEVICE" ] && echo "Device: $DEVICE"

say "Applying local signing changes (not for committing)"
sed -i '' -E "s/PRODUCT_BUNDLE_IDENTIFIER = com\.ardia\.browser\.ios/PRODUCT_BUNDLE_IDENTIFIER = $PREFIX/" "$PBXPROJ"
for file in "${ENTITLEMENTS[@]}"; do
  printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>' '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' '<plist version="1.0">' '<dict/>' '</plist>' > "$file"
done
grep -E 'PRODUCT_BUNDLE_IDENTIFIER' "$PBXPROJ" | sort -u | sed 's/^[[:space:]]*/  /'

say "Installing JavaScript packages"
"$ROOT/scripts/agent/locked" pod -- pnpm -C "$ROOT/apps/phone" install

say "Installing CocoaPods"
"$ROOT/scripts/agent/locked" pod -- bash -c "cd '$IOS' && LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 pod install"

say "Building (Release, JavaScript bundled in; the first build takes a while)"
DESTINATION="generic/platform=iOS"
[ -n "$DEVICE" ] && DESTINATION="platform=iOS,id=$DEVICE"
"$ROOT/scripts/agent/locked" xcodebuild -- xcodebuild -workspace "$IOS/Ardia.xcworkspace" -scheme Ardia -configuration Release \
  -destination "$DESTINATION" -derivedDataPath "$DERIVED" \
  DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_STYLE=Automatic -allowProvisioningUpdates build \
  | grep -E '( error: |warning: Provisioning|BUILD (SUCCEEDED|FAILED))' || true
APP="$DERIVED/Build/Products/Release-iphoneos/Ardia.app"
[ -d "$APP" ] || die "The build didn't produce Ardia.app. Scroll up for the first error."

if [ "$SKIP_INSTALL" = 1 ]; then
  echo "Built: $APP"
  exit 0
fi

say "Installing on the device"
xcrun devicectl device install app --device "$DEVICE" "$APP"

say "Opening Ardia"
if ! xcrun devicectl device process launch --device "$DEVICE" "$PREFIX" >/dev/null 2>&1; then
  echo "Installed. It didn't open by itself: unlock the device and open Ardia. If it says \"Untrusted Developer\","
  echo "go to Settings › General › VPN & Device Management, tap your Apple ID and choose Trust."
fi

cat <<DONE

Done. Ardia is on your device.
- Free-team builds stop opening after 7 days. Run this script again to renew it.
- Turn on Pinch to Summarize in Settings › Experimental (see IPAD.md for ChatGPT and Claude).
- Before you commit anything, restore the signing files: scripts/ipad/build-for-my-ipad.sh --undo
DONE
