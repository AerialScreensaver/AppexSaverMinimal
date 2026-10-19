//
//  ScreenSaverPrivate.h
//  AppexSaverMinimalExtension
//
//  Declarations for the ScreenSaver framework classes that app-extension
//  screensavers subclass. The framework exports these classes (they appear in
//  the SDK's ScreenSaver.tbd) but its public headers do not declare them, so
//  the extension links against them through this header.
//
//  Verified against macOS 27.2 (build 26B5112a) and the Xcode 27 SDK on
//  2026-10-18 by inspecting Apple's own screensaver bundles and the
//  framework's exported symbols. Apple has not documented this interface for
//  third-party developers; it can change in any macOS release.
//

#import <ScreenSaver/ScreenSaver.h>
#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark - ScreenSaverExtension

/// Principal class of a screensaver app extension: the object the system
/// instantiates when it loads the extension. Declared as
/// NSExtensionPrincipalClass in Info.plist. Apple's screensavers override
/// only init().
@interface ScreenSaverExtension : NSObject

- (instancetype)init;

@end

#pragma mark - ScreenSaverViewController

/// View controller that provides the screensaver's view. Declared as
/// ScreenSaverViewControllerClass in Info.plist. Apple's screensavers override
/// only loadView(); the host creates and sizes the view's window.
@interface ScreenSaverViewController : NSViewController

/// The host sends startAnimation when a session starts and the framework
/// forwards it to the ScreenSaverView. It does not send stopAnimation to the
/// views it releases at the end of a session: stop your work when the view
/// leaves its window. (Selectors read from the runtime on macOS 27.2.)
- (void)startAnimation;
- (void)stopAnimation;

/// Called when the host resizes the remote view, with the new size in points.
/// Call super if you override it; the sample only logs it in Debug builds.
- (BOOL)remoteViewSizeChanged:(NSSize)size transaction:(nullable id)transaction;

@end

#pragma mark - ScreenSaverConfigurationViewController

/// View controller for the configuration sheet that System Settings presents
/// when SSEHasConfigureSheet is true. Declared as
/// ScreenSaverConfigurationSheetViewControllerClass in Info.plist.
@interface ScreenSaverConfigurationViewController : NSViewController

/// Called by the framework right before System Settings shows the sheet.
/// Call super, then refresh your controls from the stored settings.
- (void)configureSheetWillPresent;

/// Call this to close the sheet. The sheet window belongs to System Settings;
/// dismissing the view controller locally only empties the remote view.
- (void)configureSheetDidEnd;

@end

NS_ASSUME_NONNULL_END
