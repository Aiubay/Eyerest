#!/bin/zsh
set -e
cd "$(dirname "$0")"
swift build -c release
APP=build/EyeRule.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/EyeRule "$APP/Contents/MacOS/EyeRule"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>EyeRule</string>
<key>CFBundleIdentifier</key><string>com.local.eyerule</string>
<key>CFBundleExecutable</key><string>EyeRule</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSCameraUsageDescription</key><string>EyeRule uses the camera during breaks to count blinks. Frames are analyzed on this Mac and never saved or sent.</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
echo "Built $APP"
