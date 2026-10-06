#!/bin/zsh
# Builds build/Gong.app (universal) from the SwiftPM executable and signs it (needed for notifications + login item).
set -euo pipefail
cd "$(dirname "$0")/.."
# Universal binary (Apple silicon + Intel). Needs a full Xcode install (also for actool below).
xcode-select -p | grep -q Xcode.app || { echo "error: needs Xcode (xcode-select -s /Applications/Xcode.app)"; exit 1; }
swift build -c release --product Gong --arch arm64 --arch x86_64
APP="build/Gong.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --product Gong --arch arm64 --arch x86_64 --show-bin-path)/Gong" "$APP/Contents/MacOS/Gong"
cp "Resources/Info.plist" "$APP/Contents/Info.plist"
# Pixel font for the retro modal (Info.plist ATSApplicationFontsPath = Fonts); optional, falls back to SF Mono.
if ls Resources/Fonts/*.ttf >/dev/null 2>&1; then
  mkdir -p "$APP/Contents/Resources/Fonts"
  cp Resources/Fonts/*.ttf "$APP/Contents/Resources/Fonts/"
  cp Resources/Fonts/OFL.txt "$APP/Contents/Resources/Fonts/"   # SIL OFL: the licence must travel with the font
fi
# Translations: one <lang>.lproj/Localizable.strings per language (English = key; see scripts/l10n.py).
for lproj in Resources/*.lproj(N); do cp -R "$lproj" "$APP/Contents/Resources/"; done
# App icon: compile the asset catalog (Assets.car + AppIcon.icns). Notification banners on recent macOS
# only pick up the icon from the compiled catalog (CFBundleIconName), not from a loose .icns.
xcrun actool "Resources/Assets.xcassets" --compile "$APP/Contents/Resources" --platform macosx \
  --minimum-deployment-target 14.0 --app-icon AppIcon --output-partial-info-plist /dev/null >/dev/null
# Sign with an Apple Development identity when one exists (needed for macOS notifications);
# fall back to ad-hoc signing otherwise.
IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | grep -o '"Apple Development: [^"]*"' | head -1 | tr -d '"')
if [ -n "$IDENTITY" ]; then
  codesign --force --sign "$IDENTITY" "$APP"
  echo "Signed with: $IDENTITY"
else
  codesign --force --sign - "$APP"
  echo "Signed ad-hoc (no Apple Development identity found; notifications will not work)"
  echo "warning: to get notifications, create a free certificate in Xcode → Settings → Accounts →" \
    "Manage Certificates… → + → Apple Development, then run this script again (see README, Install step 2)." >&2
fi
if [ "${1:-}" = "--install" ]; then
  pkill -x Gong 2>/dev/null || true
  rm -rf /Applications/Gong.app
  cp -R "$APP" /Applications/Gong.app
  echo "Installed to /Applications/Gong.app"
fi
echo "Built $APP"
