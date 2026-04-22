#!/bin/zsh
#
# Script for building SolarBar.app
#

swift build -c release

APP="SolarBar.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/release/solarbar "$APP/Contents/MacOS/solarbar"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>     <string>en</string>
    <key>CFBundleExecutable</key>            <string>solarbar</string>
    <key>CFBundleIdentifier</key>            <string>com.wyllys.solarbar</string>
    <key>CFBundleInfoDictionaryVersion</key> <string>6.0</string>
    <key>CFBundleName</key>                  <string>SolarBar</string>
    <key>CFBundleDisplayName</key>           <string>SolarBar</string>
    <key>CFBundlePackageType</key>           <string>APPL</string>
    <key>CFBundleShortVersionString</key>    <string>1.0</string>
    <key>CFBundleVersion</key>               <string>1</string>
    <key>LSMinimumSystemVersion</key>        <string>13.0</string>
    <key>LSUIElement</key>                   <true/>
    <key>NSHumanReadableCopyright</key>      <string>Copyright (c) 2026 Wyllys Ingersoll. MIT License.</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP"
