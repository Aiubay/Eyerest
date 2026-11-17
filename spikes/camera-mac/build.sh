#!/bin/zsh
set -e
cd "$(dirname "$0")"
swift build -c release
APP=build/CameraSpike.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/CameraSpike "$APP/Contents/MacOS/CameraSpike"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>CameraSpike</string>
<key>CFBundleIdentifier</key><string>com.local.cameraspike</string>
<key>CFBundleExecutable</key><string>CameraSpike</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSCameraUsageDescription</key><string>CameraSpike reads camera frames locally to test blink detection. No frames are saved or sent.</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
echo "Built $APP"
