# OLED Shade

A tiny native macOS menu bar app for OLED displays. After **1, 2, 3, or 5 minutes without keyboard, mouse, or tablet activity**, it covers every connected display with solid black. Any new activity removes the cover, normally within a few tens of milliseconds. It works across Spaces and full-screen apps. The default delay is two minutes.

## Use

Open **OLED Shade.app** and click the moon in the menu bar:

- Use **Black out after …** to enable or pause automatic blackout. A filled moon means enabled; an outline moon means paused.
- Choose **Blackout Delay → 1 minute / 2 minutes / 3 minutes / 5 minutes**. A checkmark shows the selected delay. Both the delay and enabled/paused setting survive relaunches.
- Use **Black Out Now** to try it immediately. Move the pointer or press a key to return.
- Use **Quit OLED Shade** to remove all overlays and exit. There is no Dock icon.

The app starts enabled on its first launch. Launching, enabling, changing the delay, waking, and unlocking start a fresh countdown with your selected delay. Changing the delay while paused keeps the app paused.

It does not add itself to Login Items. To start it automatically, move the built app to Applications and add it through **System Settings → General → Login Items & Extensions**.

## Privacy and system behavior

No Accessibility, Input Monitoring, Screen Recording, network, or administrator permissions are needed. The app only asks macOS for the elapsed time since the last input event; it does not read keystrokes or capture your screen. Input passes through to the app you were using, so the key or click that wakes the display can also act in that app.

This paints black pixels; it does not power off your monitor or lock your Mac. Existing company-managed screen saver, locking, and display sleep policies continue to apply. It does not keep your Mac awake. Protected system interfaces may appear above an ordinary app overlay. All connected displays, including the built-in one, are covered.

## Build

Requires **macOS 13 or later** and **Apple's Command Line Tools** (including the Swift compiler). Xcode is also supported. If the tools are missing, run `xcode-select --install` and complete Apple's installer first.

Clone and build from a terminal:

```sh
git clone https://github.com/JH1ller/OLED-fade.git
cd OLED-fade
bash build.sh
open 'build/OLED Shade.app'
```

The script runs the idle-policy tests, compiles for **Apple silicon and Intel**, combines both architectures into `build/OLED Shade.app`, generates the icon, and ad-hoc signs and verifies the bundle. It is built locally, with no Developer ID certificate or notarization. No dependencies or package downloads are required. Build output is ignored by Git.

You can choose a build destination with `bash build.sh /absolute/path/to/build`. To install, quit any running copy, drag the built **OLED Shade.app** into Applications, and open it there. Locally built versions can run without a Developer ID; distributing to other Macs may require signing and notarization appropriate to your environment.

## Test

The build automatically tests inactivity thresholds for every preset, immediate wake transitions, changing delays, pause/resume, and invalid saved preferences.

For native integration checks, run:

```sh
bash test-integration.sh
```

Run this in a logged-in desktop session with at least one connected display. It briefly shows black overlays, then verifies coverage, focus preservation, activity transitions, every delay menu choice, saved settings, and suspend/resume. The integration binary uses a separate preferences domain and does not change the main app's saved settings. These checks exercise native window state and simulated activity transitions; they do not inject keyboard or mouse events.

## Implementation

`Sources/IdlePolicy.swift` contains the preset values and the idle state machine. `Sources/main.swift` contains the native AppKit menu, settings persistence, idle polling, display overlays, and integration checks. `Tests/main.swift` tests the state machine without needing a desktop session. `make-icon.swift` generates the app icon during the build.

The idle policy checks every 250 ms during normal use and every 16.7 ms while black. Real wake latency depends on macOS scheduling. Sleep, session changes, locking notifications, and display changes are handled without taking focus from the current app.
