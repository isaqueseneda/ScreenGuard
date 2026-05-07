# ScreenGuard

macOS menu bar app for accountability. Takes random screenshots at configurable intervals, analyzes them locally for adult content using a CoreML model, and sends an iMessage alert if detected.

## How It Works

1. Sits silently in the menu bar
2. At a **random second** within each interval (default 15 min), captures the screen
3. Runs the screenshot through **Yahoo's Open NSFW** CoreML model (23MB, milliseconds)
4. If NSFW score exceeds threshold → sends `🚨 PORN DETECTED` via iMessage
5. Tampering notifications: contact is alerted if you quit, pause, or change the interval

## Resource Usage

- **CPU:** 0.0% idle, brief spike during capture+analysis
- **RAM:** ~57 MB (CoreML model + AppKit)
- **Disk:** ~23 MB (model weights)

## Requirements

- macOS 14+ (Sonoma or later)
- Screen Recording permission
- Messages/Automation permission

## Build

```bash
swift build -c release
```

## Install

```bash
# Create app bundle
mkdir -p /Applications/ScreenGuard.app/Contents/{MacOS,Resources}
cp .build/release/ScreenGuard /Applications/ScreenGuard.app/Contents/MacOS/
cp -R Sources/Resources/OpenNSFW.mlmodelc /Applications/ScreenGuard.app/Contents/Resources/
cp Info.plist /Applications/ScreenGuard.app/Contents/  # see below
```

### Info.plist

Already included at `/Applications/ScreenGuard.app/Contents/Info.plist` after first install.

### LaunchAgent (auto-start at login)

```xml
<!-- ~/Library/LaunchAgents/com.screenguard.plist -->
<plist version="1.0">
<dict>
    <key>Label</key><string>com.screenguard</string>
    <key>ProgramArguments</key>
    <array><string>/Applications/ScreenGuard.app/Contents/MacOS/ScreenGuard</string></array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
</dict>
</plist>
```

### Permissions

After first launch, grant Screen Recording in:
**System Settings → Privacy & Security → Screen & System Audio Recording → add ScreenGuard.app**

> **Important:** Do NOT re-sign the app after granting permission. Each `codesign` invalidates the TCC grant.

## Updating

```bash
# Stop, replace binary, restart (do NOT re-sign)
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.screenguard.plist
cp .build/release/ScreenGuard /Applications/ScreenGuard.app/Contents/MacOS/
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.screenguard.plist
```

## Architecture

| Component | Tech |
|-----------|------|
| App framework | AppKit (NSStatusItem menu bar) |
| Screenshot | ScreenCaptureKit (SCScreenshotManager) |
| NSFW detection | CoreML + Vision (Yahoo Open NSFW, ResNet-50) |
| iMessage | AppleScript via osascript |
| Auto-start | LaunchAgent (KeepAlive) |
| Logging | os.Logger (subsystem: com.screenguard) |
| Config | UserDefaults (domain: com.screenguard.app) |

## Tampering Alerts

The contact receives iMessage notifications for:
- `⚠️ SCREENGUARD: APP CLOSED`
- `⚠️ SCREENGUARD: MONITORING PAUSED`
- `⚠️ SCREENGUARD: INTERVAL CHANGED: 15m → 60m`

## Logs

```bash
# Live stream
log stream --predicate 'subsystem == "com.screenguard"' --level info

# Recent history
log show --predicate 'subsystem == "com.screenguard"' --last 10m
```
