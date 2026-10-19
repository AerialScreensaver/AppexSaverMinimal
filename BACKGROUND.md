# macOS app-extension screensavers — technical background

Condensed reference behind the four-part series on the Aerial website (see [README](README.md#documentation)). Everything marked *measured* was observed with this sample's Debug diagnostics on macOS 27.2 (build 26B5112a) with Xcode 27 on 2026-10-18; Apple has not documented this extension point for third-party developers, and any of it can change in a macOS release.

## 1. Architecture

Apple has been moving the screensavers that ship with macOS from `.saver` plug-ins to **app extensions** since macOS 10.15, and on macOS 27 all but two are app extensions: sandboxed `.appex` bundles, declared with the classic `NSExtension` dictionary, embedded in an app and hosted as **view services** (their views reach the host through ViewBridge remote views). They are not ExtensionKit extensions, although Apple's live in `/System/Library/ExtensionKit/Extensions/`. Legacy `.saver` bundles still work; macOS runs them inside `legacyScreenSaver.appex`, found in `ScreenSaver.framework/PlugIns/`.

| | `.appex` | `.saver` |
|---|---|---|
| Bundle type | `CFBundlePackageType = XPC!` | `BNDL` |
| Process model | One sandboxed process per host | Loaded into `legacyScreenSaver.appex` |
| Declaration | `NSExtension` dictionary + root `SSE*`/`ScreenSaver*` keys | `NSPrincipalClass` |
| Distribution | Embedded in a host `.app`, registered by PlugInKit | Standalone bundle in a Screen Savers folder |

The extension point is defined in `/System/Library/Frameworks/ScreenSaver.framework/Resources/Info.plist` under `NSExtensionSDK`:

- `NSExtensionPointName = com.apple.screensaver`, version `1.0`
- `NSExtensionProtocol = ScreenSaverExtension`
- `NSExtensionContextClass = ScreenSaverExtensionContext`, `NSExtensionContextHostClass = ScreenSaverHostExtensionContext`
- `NSExtensionHostEntitlement = com.apple.developer.extension-host.screensaver`
- subsystems `NSViewService_PKSubsystem`, `NSSharingService_Subsystem`; XPCService with `viewbridge`

## 2. Hosts (measured)

Selecting the screensaver in System Settings starts **two instances** of the extension at once (also seen on macOS 26 with Aerial):

- **System Settings' Wallpaper pane** (`Wallpaper.appex`, `com.apple.Wallpaper-Settings.extension`; on macOS 26+ the screensaver settings are in the Wallpaper pane) hosts the first. That instance gets a view controller whose window is never sized (0×0 for its lifetime) and hosts the configuration sheet. Its `ScreenSaverExtensionManager.isPreview` is true. It receives `SIGTERM` about 30 s after the pane is left.
- **The Wallpaper agent** (`WallpaperAgent`) starts a second instance that renders the screensaver as the desktop picture (windows at level −2147483625, one per display) and keeps it across activations. The screensaver proper is those windows with the lock UI on top. The pane's live preview is this instance's full-size render, scaled.
- **`ScreenSaverEngine.app`** is a thin launcher: `open -a ScreenSaverEngine` calls `SACScreenSaverStartNow` and the Wallpaper agent does the work ("Take Assertion … contentType: screenSaver", `WallpaperScreenSaverWindow`).

Activity Monitor labels the instances "AppexSaverMinimal (Wallpaper (System Settings))" and "AppexSaverMinimal (Wallpaper)". `NSApp` is `NSViewServiceApplication`; the process's home is the extension's container.

## 3. Classes

`ScreenSaver.framework`'s public headers declare only `ScreenSaverView` and `ScreenSaverDefaults`. The SDK's `ScreenSaver.tbd` exports the classes below (and more); declarations are in `PrivateHeaders/ScreenSaverPrivate.h`.

| Class | Role | Read from the runtime (measured) |
|---|---|---|
| `ScreenSaverExtension : NSObject` | Principal class (`NSExtensionPrincipalClass`). Instantiated per request and released; keep it stateless. | `beginRequestWithExtensionContext:` |
| `ScreenSaverViewController : NSServiceViewController` | Provides the view (`ScreenSaverViewControllerClass`). Override `loadView()` only. | `startAnimation`, `stopAnimation`, `invalidate`, `awakeFromRemoteView`, `remoteViewSizeChanged:transaction:` (BOOL, `(NSSize, id)`), properties `initialAnimationState`, `didFirstResize` |
| `ScreenSaverConfigurationViewController : NSServiceViewController` | Options sheet (`ScreenSaverConfigurationSheetViewControllerClass`). | `configureSheetWillPresent`, `configureSheetDidEnd`, `extensionContext` |
| `ScreenSaverExtensionContext : NSExtensionContext` | Context class (`NSExtensionContextClass`). | `+_extensionAuxiliaryHostProtocol`, `+_extensionAuxiliaryVendorProtocol` |
| `ScreenSaverExtensionManager` | Service-side manager (`+sharedManager`). | `isPreview`, `isAnimating`, `viewControllers`, `bundleIdentifier`, `processExtensionRequest:replyInfo:` |

`loadViewForFrame:isPreview:` belongs to the host-side `ScreenSaverModule` / `ScreenSaverExtensionModule`, not to the view controller.

## 4. Info.plist keys

Inside `NSExtension`: `NSExtensionPointIdentifier = com.apple.screensaver`, `NSExtensionPointVersion = 1.0`, `NSExtensionPrincipalClass = $(PRODUCT_MODULE_NAME).YourExtension`.

Root level:

| Key | Type | Meaning |
|---|---|---|
| `NSExtensionContextClass` | String | `ScreenSaverExtensionContext`. Without it a host that opens an auxiliary connection crashes the extension before the principal class runs (Aerial 4.0.14, macOS 14/15). 8 of Apple's 12 savers declare it. |
| `ScreenSaverViewControllerClass` | String | The `ScreenSaverViewController` subclass. |
| `SSEHasConfigureSheet` | Boolean | Shows the Options button. |
| `ScreenSaverConfigurationSheetViewControllerClass` | String | The `ScreenSaverConfigurationViewController` subclass. |
| `SSENeedsAnimationTimer` | Boolean | `true`: the host calls `animateOneFrame()` every `animationTimeInterval` (measured 60/s per view at 1/60; default interval 1/30). `false`: called once at start. `startAnimation` arrives either way; `stopAnimation` is not sent to the views the host releases (§5). |
| `ScreenSaverConfigurationViewControllerClass`, `ScreenSaverExtensionManagerClass` | String | Seen in the framework and in `legacyScreenSaver`; not needed by a normal screensaver. |

Apple's savers on macOS 27.2 (`SSENeedsAnimationTimer` / `SSEHasConfigureSheet` / `NSExtensionContextClass`): Album Artwork false/true/yes · Arabesque true/false/no · Computer Name true/true/yes · Drift false/true/yes · Flurry true/true/yes · Hello false/true/yes · iLifeSlideshows false/true/yes · Monterey false/false/yes · Shell true/false/no · Ventura false/false/yes · Word of the Day true/true/no.

## 5. Lifecycle (measured)

One activation on two displays, agent-hosted instance: `loadView()` per display → `viewDidMoveToWindow()` with a 0×0 window at the main display's origin → `remoteViewSizeChanged(_:transaction:)` 15–25 ms later with the display size (second window moved to its display) → `startAnimation()` per view (+ one `animateOneFrame()` with the timer off) → … → distributed `com.apple.screensaver.willstop`, `didstop` → view controllers and views released ≈400 ms later **without `stopAnimation()`** (each view gets `viewDidMoveToWindow()` with a nil window, then `deinit`); the `stopAnimation()` calls that do arrive go to views the instance keeps, and kept views get `startAnimation()` again when a session starts. The process stays alive across activations; the principal class is created/released around every request (eleven pairs in one activation).

Notifications received: `com.apple.screensaver.didstart` (object `runFromPref` when started from the pane's Preview), `com.apple.screenIsLocked` (≈150 ms after `didstart`), `willstop`, `didstop`, `com.apple.screenLockUIIsHidden`, `com.apple.screenIsUnlocked`; Control-Command-Q delivers `screenIsLocked` + `screenLockUIIsShown`. The agent keeps the process after it releases the views and reuses it for the next session (one process served 19 view controllers over two minutes); only the pane's instance received `SIGTERM`. Keep per-session state in the view, stop timers when the view leaves its window, re-read settings per view, persist as you go. Ending the Options sheet makes the agent recreate its view (the preview restarts; Apple's Hello does the same). No key focus.

On macOS 14/15 (Aerial 4.0): windows were placed on the main display and migrated 30–200 ms later (`NSWindow.didChangeScreenNotification`; `window.screen` reliable at settle), and `startAnimation`/`stopAnimation` were not reliably delivered — drive from `viewDidMoveToWindow()` as well.

## 6. Rendering

- **Core Animation / own timer** (this sample): `SSENeedsAnimationTimer = false`, start and stop from `viewDidMoveToWindow()`; `startAnimation()` as a second, idempotent start trigger; never rely on `stopAnimation()`.
- **Per-frame drawing**: `SSENeedsAnimationTimer = true`, set `animationTimeInterval`, override `animateOneFrame()`/`draw(_:)`.
- **SwiftUI**: add an `NSHostingView` as a subview of the `ScreenSaverView`.

`isPreview` is not conveyed to the extension; create the view with `frame: .zero, isPreview: false` and an autoresizing mask, like Apple's savers. The only preview-ish instance (System Settings') never gets a sized window.

## 7. Configuration sheet and settings (measured)

- Subclass `ScreenSaverConfigurationViewController`; set `preferredContentSize`; refresh controls in `configureSheetWillPresent()`; end the sheet with `configureSheetDidEnd()`. `dismiss(_:)`/`sheetParent` do not work from a remote view (the sheet stays with an empty area and the next click raises an uncaught exception that terminates the extension).
- Store with `ScreenSaverDefaults(forModuleWithName: <bundle identifier>)` → `~/Library/Containers/<bundle id>/Data/Library/Preferences/ByHost/<bundle id>.<hardware UUID>.plist`. Inside the sandbox only the extension's own domain is writable.
- Cross-process updates: `UserDefaults.didChangeNotification` is in-process only; KVO on the defaults object fires in the other instance within milliseconds, but the cached value there is stale until `synchronize()` is called; the plist on disk is written later still. Re-read (`synchronize()`) before applying.

## 8. Registration and discovery

PlugInKit (`pkd`) scans `/Applications` and launched apps; `pluginkit -a <appex>` registers any path (the sample's "Register Extensions" build phase does it on every build; needs `ENABLE_USER_SCRIPT_SANDBOXING = NO`); `pluginkit -r` removes; `pluginkit -m -v -p com.apple.screensaver` lists (`-D` all copies, `-A` all versions, `-i <id>` by identifier). Election marks: `+` use, `-` ignore, `!` debugger, `=` superseded, `?` unknown. Duplicate registrations make the system load an unexpected copy (black screensaver, no view controller); log the loaded bundle path. After a rebuild, `killall WallpaperAgent` (it restarts on its own and relaunches the extension) and reopen System Settings. PaperSaver identifies an appex saver by the `.appex` file stem.

## 9. Thumbnails

Asset-catalog image set `thumbnail`, 107×65 @1x and 214×130 @2x, landscape. Apple's savers ship theirs in `Assets.car` with `CFBundleIconFile`. System Settings caches thumbnails for days (through restarts); no cache file was identified. Verify a new thumbnail on a VM or a second Mac rather than on the development machine.

## 10. Entitlements (measured)

Sample: `com.apple.security.app-sandbox` plus mach-lookup exceptions `com.apple.CARenderServer` and `com.apple.CoreDisplay.master`, the two Apple's Flurry/Hello carry (they also carry `com.apple.nsurlstorage-cache`; none carries a library-validation exception or a ViewBridge lookup). On macOS 27.2 the sample rendered with the sandbox entitlement alone; the lookups stay for macOS 14/15. The extension is not hardened (the host app is), so `disable-library-validation` on the extension was a no-op and is gone, as are the network entitlements Xcode added from build settings. Read the signed set with `codesign -d --entitlements :- <appex>`.

## References

- `ScreenSaver.framework` SDK headers and `ScreenSaver.tbd`
- `/System/Library/ExtensionKit/Extensions/*.appex` (Apple's screensavers)
- `/System/Library/Frameworks/ScreenSaver.framework/Resources/Info.plist` (the extension-point definition)
- [Aerial](https://github.com/AerialScreensaver/Aerial), [ScreenSaverMinimal](https://github.com/AerialScreensaver/ScreenSaverMinimal), [PaperSaver](https://github.com/AerialScreensaver/PaperSaver)
