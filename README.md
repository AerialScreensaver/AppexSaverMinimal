# AppexSaverMinimal

A minimal sample project for building a macOS screensaver as an **app extension** (`.appex`), the format Apple has been moving its own screensavers to since macOS 10.15, maintained by [Guillaume Louel](https://github.com/glouel).

Use this as a starting point for your own app-extension screensaver. The companion project [ScreenSaverMinimal](https://github.com/AerialScreensaver/ScreenSaverMinimal) builds the same rainbow screensaver as a legacy `.saver` plug-in, for comparison.

> **Before you build on this.** Apple's own screensavers use the `com.apple.screensaver` extension point this sample targets, but Apple has not documented it for third-party developers. The classes and property-list keys involved were recovered from the system's framework and bundles; they can change in any macOS release. The supported way to write a screensaver remains a `.saver` bundle built with the public [ScreenSaver framework](https://developer.apple.com/documentation/screensaver). An app built on this extension point uses private API and will be rejected from the Mac App Store; distribute it outside the store, signed with Developer ID and notarized.

## Documentation

The full write-up lives on the Aerial website, as a four-part series:

1. [Build a screensaver as an app extension](https://aerialscreensaver.github.io/developers/appex-screensaver/) — the property list, the three framework classes, rendering, the in-app preview.
2. [Understand the screensaver extension lifecycle](https://aerialscreensaver.github.io/developers/appex-lifecycle/) — hosts, one process per host serving every display, start/stop, notifications, lock and sleep.
3. [Add a configuration sheet and persist settings](https://aerialscreensaver.github.io/developers/appex-configuration-sheet/) — the Options sheet, `configureSheetDidEnd()`, `ScreenSaverDefaults` across two processes.
4. [Register, install and distribute the screensaver](https://aerialscreensaver.github.io/developers/appex-distribution/) — pluginkit, duplicate registrations, thumbnails, entitlements, notarization.

[BACKGROUND.md](BACKGROUND.md) is the condensed technical reference behind those articles.

## What this sample shows

- A host app plus an embedded `.appex`, wired up to build, sign, register and install
- The three `ScreenSaver.framework` classes an app-extension screensaver subclasses, declared in [`PrivateHeaders/ScreenSaverPrivate.h`](AppexSaverMinimalExtension/PrivateHeaders/ScreenSaverPrivate.h)
- A six-color rainbow animation (matching [Aerial](https://github.com/AerialScreensaver/Aerial)'s fallback view) driven by `CABasicAnimation`, shared with an in-app preview window
- A configuration sheet with two settings (cycle speed, version label) stored with `ScreenSaverDefaults` and applied live in the running screensaver
- Registration via `pluginkit` and activation via [PaperSaver](https://github.com/AerialScreensaver/PaperSaver)
- Debug-only diagnostics (`AppexSaverMinimalExtension/Diagnostics/`) that log the process, window geometry, animation calls and system notifications, and can dump the framework's undocumented classes through the Objective-C runtime

## Building and installation

### Prerequisites

- Xcode 15 or newer (tested with Xcode 27)
- macOS 14.0 (Sonoma) or newer. Tested on macOS 14 through macOS 27 (behaviour documented on macOS 27.2); earlier releases are untested
- An Apple Developer Team ID if you want to distribute the screensaver to other machines

### Getting started

1. **Clone the repository:**

   ```bash
   git clone https://github.com/AerialScreensaver/AppexSaverMinimal.git
   cd AppexSaverMinimal
   ```

2. **Open the project in Xcode:**

   ```bash
   open AppexSaverMinimal.xcodeproj
   ```

3. **Set your own Team ID:** open the project settings, select the `AppexSaverMinimal` target, and under **Signing & Capabilities** set your **Team**. Repeat for the `AppexSaverMinimalExtension` target. The project ships with `DEVELOPMENT_TEAM = ""`.

### Project targets

- **AppexSaverMinimal** — A SwiftUI host application that embeds the screensaver extension. Run it (⌘R) to register, enable and preview the screensaver from a normal app window.
- **AppexSaverMinimalExtension** — The screensaver itself, packaged as an `.appex` and embedded inside the host app's `Contents/PlugIns/`.

### Building

```bash
xcodebuild -project AppexSaverMinimal.xcodeproj -scheme AppexSaverMinimal -configuration Debug build
```

The `AppexSaverMinimal` scheme has a pre-action that writes the build number (`YYMMDD.HHMM`) into `BuildNumber.xcconfig`, so every build is distinguishable in System Settings and in the logs. Do not edit that file by hand; commit it with the change it was built for.

### Registering

The host target's **Register Extensions** build phase runs after signing:

```bash
find "$CODESIGNING_FOLDER_PATH" -name '*.appex' -exec pluginkit -a {} \;
```

So every build registers the freshly built extension with PlugInKit, the system's extension registry, and System Settings lists it right away (the phase needs `ENABLE_USER_SCRIPT_SANDBOXING = NO`). The host app's **Install** button runs the same command on demand. Check the registration with:

```bash
pluginkit -m -v -D -A -i net.aerialscreensaver.AppexSaverMinimal.Extension
```

Then pick **AppexSaverMinimal** in System Settings (Wallpaper pane on macOS 26 and later, Screen Saver pane before that), or click **Enable as Screensaver** in the host app.

After a rebuild, the instances of the extension that are already running keep the old code. Restart the Wallpaper agent (it comes back on its own, with a brief desktop flicker, and starts a fresh instance) and reopen System Settings:

```bash
killall WallpaperAgent
```

#### Important: pick ONE location per machine

PlugInKit can hold several registrations of the same extension (a DerivedData build, an archive, a copy in `/Applications/`), and the system may load the one you did not expect; the symptom is a screensaver that initialises but never gets a view, and stays black. Keep one location per machine:

- **Always use DerivedData** — develop in Xcode, never copy to `/Applications/`. Simplest while iterating.
- **Always use `/Applications/`** — add a build phase or post-build script that copies `AppexSaverMinimal.app` there before you trigger the screensaver.

If you have mixed both, remove the registration you do not want with `pluginkit -r <path to the .appex>`, and look at `pluginkit -m -v -A` to see every version. The extension logs the path it was loaded from at launch.

### Distribution

To distribute a signed and notarized build to others:

1. **Archive** in Xcode (Product → Archive), then export from the Organizer with Developer ID.
2. **Notarize via command line:**

   ```bash
   xcrun notarytool submit "AppexSaverMinimal.app.zip" \
     --keychain-profile "AC_PASSWORD" \
     --wait

   xcrun stapler staple "AppexSaverMinimal.app"
   xcrun stapler validate "AppexSaverMinimal.app"
   ```

   You need a keychain profile set up first:

   ```bash
   xcrun notarytool store-credentials "AC_PASSWORD" \
     --apple-id "your@email.com" \
     --team-id "TEAMID" \
     --password "app-specific-password"
   ```

## Logs

Both the host app and the extension log to a single subsystem so you can watch their lifecycles side by side. In Console.app, filter by:

```
subsystem:net.aerialscreensaver.AppexSaverMinimal
```

From a terminal, call the tool by its full path (in zsh, `log` is a shell builtin):

```bash
/usr/bin/log stream --info --debug --predicate 'subsystem == "net.aerialscreensaver.AppexSaverMinimal"'
/usr/bin/log show --last 10m --info --predicate 'subsystem == "net.aerialscreensaver.AppexSaverMinimal"'
```

You will see lines from two or three processes: the host app, the instance of the extension that System Settings hosts (preview and Options sheet), and the instance that the Wallpaper agent hosts (the desktop picture and the screensaver). Log lifecycle facts at `.notice` or above; `.info` lines are not reliably kept for a later `log show`.

## Project structure

```
AppexSaverMinimal/
├── AppexSaverMinimal/                      # Host app (SwiftUI)
│   ├── AppexSaverMinimalApp.swift          # @main app entry, main window + Preview window
│   ├── ContentView.swift                   # Install / uninstall / enable / preview UI
│   ├── PluginManager.swift                 # pluginkit + PaperSaver wrappers
│   ├── PreviewView.swift                   # NSView for the host's preview window
│   ├── PreviewViewRepresentable.swift      # SwiftUI wrapper around PreviewView
│   ├── RainbowAnimator.swift               # Shared six-color animation
│   ├── Helpers/Logger.swift                # Shared OSLog subsystem
│   └── Info.plist
├── AppexSaverMinimalExtension/             # The screensaver (.appex)
│   ├── AppexSaverMinimalExtension.swift            # Principal class (ScreenSaverExtension)
│   ├── AppexSaverMinimalViewController.swift       # ScreenSaverViewController
│   ├── AppexSaverMinimalView.swift                 # ScreenSaverView (uses RainbowAnimator)
│   ├── AppexSaverMinimalConfigurationViewController.swift  # Options sheet
│   ├── AppexSaverSettings.swift                    # ScreenSaverDefaults store
│   ├── Diagnostics/AppexDiagnostics.swift          # Debug-only instrumentation
│   ├── PrivateHeaders/ScreenSaverPrivate.h         # Declarations of the undocumented classes
│   ├── AppexSaverMinimalExtension.entitlements
│   └── Info.plist                                  # NSExtension dictionary, SSE* keys
├── BuildNumber.xcconfig                    # Written by the scheme pre-action
└── BACKGROUND.md                           # Condensed technical reference
```

## Comparison to the legacy `.saver` format

If you need to target older macOS versions, see the companion repo [ScreenSaverMinimal](https://github.com/AerialScreensaver/ScreenSaverMinimal). The two projects intentionally share the same rainbow look so you can read them as a pair.

| | `.appex` (this repo) | `.saver` (companion) |
|---|---|---|
| **Bundle type** | `XPC!` (app extension) | `BNDL` (NSBundle plug-in) |
| **Process** | Separate sandboxed process per host | In-process with `legacyScreenSaver.appex` |
| **Hosts** | System Settings' Wallpaper pane; the Wallpaper agent | The screensaver engine, through `legacyScreenSaver` |
| **Min macOS** | 14.0 (tested through 27; earlier untested) | All supported macOS |
| **Distribution** | Embedded in a `.app` | Standalone `.saver` file |
| **Public API** | No; see the notice above | Yes, `ScreenSaverView` |

## License

[MIT](LICENSE) © 2026 Guillaume Louel
