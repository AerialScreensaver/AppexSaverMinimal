//
//  AppexDiagnostics.swift
//  AppexSaverMinimalExtension
//
//  Copyright © 2026 Guillaume Louel. Licensed under the MIT License.
//
//  DEBUG-only instrumentation used to document the screensaver extension
//  lifecycle: process identity and lifetime, window geometry as the host sizes
//  the remote view, animation calls, system notifications, and a dump of the
//  framework's undocumented classes through the Objective-C runtime.
//
//  Everything logs at `.notice` with public privacy so `log show` keeps it.
//  Nothing here ships in Release builds.
//

#if DEBUG

import AppKit
import ObjectiveC
import ScreenSaver
import os.log

enum AppexDiagnostics {

    static let logger = AppexLog.logger("Diag.Process")

    /// Set when the extension process started; static so it spans activations.
    static let processStart = Date()
    static var activationCount = 0

    /// Set to true to log every method, property and ivar of the framework's
    /// undocumented classes at launch (about 500 lines per process).
    static let dumpsFrameworkClasses = false

    private static var didRunOnce = false
    private static var signalSource: DispatchSourceSignal?

    /// Called once from the principal class's initializer.
    static func runOnce() {
        guard !didRunOnce else { return }
        didRunOnce = true
        logProcessIdentity()
        installNotificationObservers()
        installExitHooks()
        if dumpsFrameworkClasses {
            dumpClasses()
        }
    }

    /// Called from the view controller's `loadView()`.
    static func didLoadView() {
        activationCount += 1
        let uptime = Date().timeIntervalSince(processStart)
        logger.notice("loadView activation=\(activationCount, privacy: .public) uptime=\(uptime, format: .fixed(precision: 1), privacy: .public)s pid=\(ProcessInfo.processInfo.processIdentifier, privacy: .public)")
        logger.notice("NSScreen.main=\(NSScreen.main.map { NSStringFromRect($0.frame) } ?? "nil", privacy: .public) screens=\(NSScreen.screens.map { NSStringFromRect($0.frame) + "@" + String(describing: $0.backingScaleFactor) }.joined(separator: " "), privacy: .public)")
        logManagerState("loadView")
    }

    /// Reads the framework's service-side manager through KVC: whether the host
    /// asked for a preview, and how many view controllers it holds.
    static func logManagerState(_ tag: String) {
        guard let managerClass = NSClassFromString("ScreenSaverExtensionManager") as? NSObject.Type,
              managerClass.responds(to: NSSelectorFromString("sharedManager")),
              let manager = managerClass.perform(NSSelectorFromString("sharedManager"))?.takeUnretainedValue() as? NSObject else {
            logger.notice("manager[\(tag, privacy: .public)] unavailable")
            return
        }
        let isPreview = String(describing: manager.value(forKey: "isPreview"))
        let isAnimating = String(describing: manager.value(forKey: "isAnimating"))
        let count = (manager.value(forKey: "viewControllers") as? [Any])?.count ?? -1
        let bundle = String(describing: manager.value(forKey: "bundleIdentifier"))
        logger.notice("manager[\(tag, privacy: .public)] isPreview=\(isPreview, privacy: .public) isAnimating=\(isAnimating, privacy: .public) viewControllers=\(count, privacy: .public) bundle=\(bundle, privacy: .public)")
    }

    // MARK: - Process identity

    static func logProcessIdentity() {
        let info = ProcessInfo.processInfo
        logger.notice("pid=\(info.processIdentifier, privacy: .public) name=\(info.processName, privacy: .public) bundle=\(Bundle.main.bundlePath, privacy: .public)")
        logger.notice("NSApp=\(NSApp.map { NSStringFromClass(type(of: $0)) } ?? "nil", privacy: .public)")
        for key in ["XPC_SERVICE_NAME", "__CFBundleIdentifier", "APP_SANDBOX_CONTAINER_ID", "HOME"] {
            logger.notice("env \(key, privacy: .public)=\(info.environment[key] ?? "-", privacy: .public)")
        }
        if let pid = responsiblePID() {
            let app = NSRunningApplication(processIdentifier: pid)
            logger.notice("responsible pid=\(pid, privacy: .public) bundle=\(app?.bundleIdentifier ?? "?", privacy: .public) name=\(app?.localizedName ?? "?", privacy: .public)")
        } else {
            logger.notice("responsible pid unavailable")
        }
    }

    /// launchd marks an app-extension process as "responsible to" its host,
    /// which is how TCC attributes prompts. Private; DEBUG only.
    private typealias ResponsibleFunction = @convention(c) (pid_t) -> pid_t
    static func responsiblePID() -> pid_t? {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid") else {
            return nil
        }
        let function = unsafeBitCast(symbol, to: ResponsibleFunction.self)
        let pid = function(getpid())
        return pid > 0 ? pid : nil
    }

    // MARK: - Notifications and exit

    static func installNotificationObservers() {
        let distributed = DistributedNotificationCenter.default()
        for name in ["com.apple.screensaver.willstart", "com.apple.screensaver.didstart",
                     "com.apple.screensaver.willstop", "com.apple.screensaver.didstop",
                     "com.apple.screenIsLocked", "com.apple.screenIsUnlocked",
                     "com.apple.screenLockUIIsShown", "com.apple.screenLockUIIsHidden"] {
            distributed.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { notification in
                logger.notice("DNC \(name, privacy: .public) object=\(String(describing: notification.object), privacy: .public)")
            }
        }
        let hostNames = ["NSExtensionHostWillEnterBackgroundNotification", "NSExtensionHostDidEnterBackgroundNotification",
                         "NSExtensionHostWillResignActiveNotification", "NSExtensionHostDidBecomeActiveNotification"]
            .map { Notification.Name(rawValue: $0) }
        for name in hostNames {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { notification in
                logger.notice("NSExtensionHost \(name.rawValue, privacy: .public) object=\(String(describing: notification.object), privacy: .public)")
            }
        }
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification,
                     NSWorkspace.screensDidSleepNotification, NSWorkspace.screensDidWakeNotification,
                     NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { _ in
                logger.notice("NSWorkspace \(name.rawValue, privacy: .public)")
            }
        }
    }

    static func installExitHooks() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler {
            logger.notice("SIGTERM uptime=\(Date().timeIntervalSince(processStart), format: .fixed(precision: 1), privacy: .public)s activations=\(activationCount, privacy: .public)")
            exit(0)
        }
        source.resume()
        signalSource = source
        atexit {
            AppexDiagnostics.logger.notice("atexit uptime=\(Date().timeIntervalSince(AppexDiagnostics.processStart), format: .fixed(precision: 1), privacy: .public)s")
        }
    }

    // MARK: - Runtime dump of the framework's classes

    static func dumpClasses() {
        for name in ["ScreenSaverExtension", "ScreenSaverViewController", "ScreenSaverConfigurationViewController",
                     "ScreenSaverExtensionContext", "ScreenSaverExtensionView", "ScreenSaverExtensionManager",
                     "ScreenSaverRemoteViewController"] {
            ObjCDump.dump(name)
        }
        let keywords = ["remote", "Remote", "Service", "service", "host", "Host", "auxiliary", "Auxiliary",
                        "sheet", "Sheet", "configur", "Configur", "dismiss", "nimation", "review", "xtension"]
        let filter: (String) -> Bool = { selector in keywords.contains { selector.contains($0) } }
        ObjCDump.dump("NSExtensionContext", filter: filter)
        ObjCDump.dump("NSViewController", filter: filter)
        if let app = NSApp {
            ObjCDump.dump(NSStringFromClass(type(of: app)), filter: filter)
        }
    }
}

enum ObjCDump {

    private static let logger = AppexLog.logger("Diag.ObjC")

    static func dump(_ className: String, filter: ((String) -> Bool)? = nil) {
        guard let cls: AnyClass = NSClassFromString(className) else {
            logger.notice("[\(className, privacy: .public)] class not found")
            return
        }
        var chain: [String] = []
        var current: AnyClass? = cls
        while let klass = current {
            chain.append(NSStringFromClass(klass))
            current = class_getSuperclass(klass)
        }
        logger.notice("[\(className, privacy: .public)] chain: \(chain.joined(separator: " -> "), privacy: .public)")

        var count: UInt32 = 0
        if let protocols = class_copyProtocolList(cls, &count) {
            for index in 0..<Int(count) {
                logger.notice("[\(className, privacy: .public)] <\(String(cString: protocol_getName(protocols[index])), privacy: .public)>")
            }
        }
        count = 0
        if let properties = class_copyPropertyList(cls, &count) {
            defer { free(properties) }
            for index in 0..<Int(count) {
                let attributes = property_getAttributes(properties[index]).map { String(cString: $0) } ?? ""
                logger.notice("[\(className, privacy: .public)] @property \(String(cString: property_getName(properties[index])), privacy: .public) (\(attributes, privacy: .public))")
            }
        }
        count = 0
        if let ivars = class_copyIvarList(cls, &count) {
            defer { free(ivars) }
            for index in 0..<Int(count) {
                let name = ivar_getName(ivars[index]).map { String(cString: $0) } ?? "?"
                let encoding = ivar_getTypeEncoding(ivars[index]).map { String(cString: $0) } ?? "?"
                logger.notice("[\(className, privacy: .public)] ivar \(name, privacy: .public) : \(encoding, privacy: .public)")
            }
        }
        methods(of: cls, tag: className, prefix: "-", filter: filter)
        if let meta: AnyClass = object_getClass(cls) {
            methods(of: meta, tag: className, prefix: "+", filter: filter)
        }
    }

    private static func methods(of cls: AnyClass, tag: String, prefix: String, filter: ((String) -> Bool)?) {
        var count: UInt32 = 0
        guard let list = class_copyMethodList(cls, &count) else { return }
        defer { free(list) }
        for index in 0..<Int(count) {
            let selector = NSStringFromSelector(method_getName(list[index]))
            if let filter, !filter(selector) { continue }
            let encoding = method_getTypeEncoding(list[index]).map { String(cString: $0) } ?? "?"
            logger.notice("[\(tag, privacy: .public)] \(prefix, privacy: .public)\(selector, privacy: .public)  \(encoding, privacy: .public)")
        }
    }
}

/// Per-view geometry and animation counters.
final class ViewDiagnostics {

    private let logger = AppexLog.logger("Diag.View")
    private var attachTime: Date?
    private var lastBounds = NSRect.null
    private var startCount = 0
    private var stopCount = 0
    private var frameCount = 0
    private var lastRateLog = Date()

    func logGeometry(_ view: NSView, _ tag: String) {
        if attachTime == nil, view.window != nil { attachTime = Date() }
        let elapsed = attachTime.map { Int(Date().timeIntervalSince($0) * 1000) } ?? -1
        let window = view.window
        lastBounds = view.bounds
        logger.notice("[geo +\(elapsed, privacy: .public)ms] \(tag, privacy: .public) bounds=\(NSStringFromRect(view.bounds), privacy: .public) win=\(window.map { NSStringFromRect($0.frame) } ?? "nil", privacy: .public) winClass=\(window.map { NSStringFromClass(type(of: $0)) } ?? "nil", privacy: .public) level=\(window?.level.rawValue ?? -1, privacy: .public) visible=\(window?.isVisible ?? false, privacy: .public) screen=\(window?.screen.map { NSStringFromRect($0.frame) } ?? "nil", privacy: .public) scale=\(window?.backingScaleFactor ?? 0, privacy: .public) screens=\(NSScreen.screens.count, privacy: .public)")
    }

    func logGeometryIfChanged(_ view: NSView, _ tag: String) {
        guard view.bounds != lastBounds else { return }
        logGeometry(view, tag)
    }

    func didStartAnimation(_ view: ScreenSaverView) {
        startCount += 1
        logger.notice("startAnimation #\(self.startCount, privacy: .public) isAnimating(before)=\(view.isAnimating, privacy: .public) interval=\(view.animationTimeInterval, privacy: .public) needsTimer=\(Self.needsAnimationTimer(view), privacy: .public)")
    }

    func didStopAnimation(_ view: ScreenSaverView) {
        stopCount += 1
        logger.notice("stopAnimation #\(self.stopCount, privacy: .public) frames=\(self.frameCount, privacy: .public)")
    }

    func didAnimateFrame() {
        frameCount += 1
        let now = Date()
        if now.timeIntervalSince(lastRateLog) >= 1 {
            logger.notice("animateOneFrame rate=\(self.frameCount, privacy: .public)/s")
            frameCount = 0
            lastRateLog = now
        }
    }

    /// Reads the framework's private `_needsAnimationTimer` through KVC.
    static func needsAnimationTimer(_ view: NSObject) -> String {
        guard view.responds(to: NSSelectorFromString("_needsAnimationTimer")) else { return "n/a" }
        return String(describing: view.value(forKey: "_needsAnimationTimer"))
    }
}

#endif
