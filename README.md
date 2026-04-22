# solartools

macOS tools for monitoring a **Logitech K750** solar-powered wireless keyboard's battery charge and ambient-light level.

The K750 reports its solar state over Logitech's vendor-specific HID++ protocol via the Unifying Receiver (USB `046d:c52b`). These tools talk to the receiver through the IOKit HID Manager — no kernel extension or DriverKit entitlement required.

## Components

| Target      | Type             | Description                                                                                             |
|-------------|------------------|---------------------------------------------------------------------------------------------------------|
| `solarcli`  | CLI executable   | Print the current reading once, or poll continuously on a timer.                                        |
| `solarbar`  | Menu bar app     | Menu bar widget with a popover showing circular gauges for charge (0–100%) and ambient light (0–500 lux). |
| `SolarCore` | Library          | Shared HID++ transport used by both executables.                                                        |

## Requirements

- macOS 13 or later
- Swift 5.9 toolchain (Xcode 15 or the matching [Swift.org](https://swift.org) release)
- Logitech Unifying Receiver paired to a K750

On first run macOS will prompt for **Input Monitoring** permission. Grant it under *System Settings → Privacy & Security → Input Monitoring*. Only one process at a time can seize the HID++ collection, so don't run `solarbar` and `solarcli --monitor` simultaneously.

## Build

```sh
swift build              # debug
swift build -c release   # optimized
```

## Development / running from the repo

```sh
swift run solarcli --once
swift run solarcli --monitor --interval 30
swift run solarbar
```

Running via `swift run` is fine for iteration, but `solarbar` is a menu bar app — you'll get the best experience by packaging it as a real `.app` bundle (next section).

## Packaging `solarbar` as a `.app`

All of the following can be done using the `buildapp.sh` script.

### Details

SwiftPM produces a plain Mach-O executable. Wrapping it in an `.app` bundle lets you:

- move it to `/Applications`,
- hide the Dock icon cleanly (via `LSUIElement`),
- have macOS remember its Input Monitoring grant between builds,
- add it to Login Items so it starts automatically.

Run these commands from the repo root:

```sh
# 1. Release build
swift build -c release

# 2. Bundle skeleton
APP="SolarBar.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# 3. Drop the executable in
cp .build/release/solarbar "$APP/Contents/MacOS/solarbar"

# 4. Write Info.plist
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

# 5. Ad-hoc codesign so macOS gives the bundle a stable identity
codesign --force --deep --sign - "$APP"
```

Key pieces of `Info.plist`:

- **`LSUIElement = true`** keeps the Dock icon from flashing at launch. The app also calls `NSApp.setActivationPolicy(.accessory)` at runtime, but setting it in the plist makes it clean from the first frame.
- **`CFBundleIdentifier`** gives the bundle a stable identity so macOS's TCC database remembers Input Monitoring grants across rebuilds. Change the string if you want your own namespace.

### Install and run

```sh
mv SolarBar.app /Applications/
open /Applications/SolarBar.app
```

When macOS prompts for Input Monitoring, toggle **SolarBar** on under *System Settings → Privacy & Security → Input Monitoring*, then quit and reopen the app once.

**NOTE**
If the app does not display any updates, click the light test button on the K750 keyboard to trigger an update.

### Start automatically at login

Pick either:

- **GUI:** *System Settings → General → Login Items & Extensions → Open at Login → `+` → `/Applications/SolarBar.app`*.
- **One-liner:**
  ```sh
  osascript -e 'tell application "System Events" to make login item at end with properties {path:"/Applications/SolarBar.app", hidden:false}'
  ```

To remove later, delete the entry from the same Login Items pane.

### Uninstall

```sh
rm -rf /Applications/SolarBar.app
```

Then remove it from Login Items and (optionally) revoke its Input Monitoring permission.

## License

MIT. See [LICENSE](LICENSE).
