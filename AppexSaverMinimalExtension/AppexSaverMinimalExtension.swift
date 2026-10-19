//
//  AppexSaverMinimalExtension.swift
//  AppexSaverMinimalExtension
//
//  Copyright © 2026 Guillaume Louel. Licensed under the MIT License.
//
//  Principal class for the screensaver extension. Specified as
//  NSExtensionPrincipalClass in Info.plist as
//  `$(PRODUCT_MODULE_NAME).AppexSaverMinimalExtension`.
//
//  Following Apple's own screensavers (e.g. Arabesque.appex), this class stays
//  minimal: it implements only init() and lets the framework drive the lifecycle.
//

import Foundation
import ScreenSaver

private let logger = AppexLog.logger("Extension")

@objc(AppexSaverMinimalExtension)
class AppexSaverMinimalExtension: ScreenSaverExtension {

    @objc override init() {
        logger.info("AppexSaverMinimalExtension.init() PID=\(ProcessInfo.processInfo.processIdentifier, privacy: .public)")
        super.init()
        // When several copies of the extension are registered with pluginkit
        // (an old build in /Applications and a new one in DerivedData), the
        // system may load the one you did not expect. This path tells which.
        logger.info("loaded from \(Bundle(for: type(of: self)).bundlePath, privacy: .public)")
        #if DEBUG
        AppexDiagnostics.runOnce()
        #endif
    }

    deinit {
        logger.info("AppexSaverMinimalExtension.deinit")
    }
}
