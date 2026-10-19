//
//  AppexSaverSettings.swift
//  AppexSaverMinimalExtension
//
//  Copyright © 2026 Guillaume Louel. Licensed under the MIT License.
//
//  The screensaver's two settings, stored with ScreenSaverDefaults, the
//  UserDefaults subclass the ScreenSaver framework provides for screensavers.
//  The configuration sheet (presented by System Settings) and the screensaver
//  view (shown by System Settings' preview or by ScreenSaverEngine) are
//  instances of this same extension, so they share one sandbox container and
//  therefore one preference domain.
//

import Foundation
import ScreenSaver

final class AppexSaverSettings: NSObject {

    static let shared = AppexSaverSettings()

    /// Posted on the main queue after a value changes in this process or in the
    /// other instance of the extension, so a live view (the wallpaper or the
    /// System Settings preview while the sheet is open) can apply it at once.
    static let didChangeNotification = Notification.Name("net.aerialscreensaver.AppexSaverMinimal.settingsDidChange")

    enum Key {
        static let cycleInterval = "cycleInterval"
        static let showsVersionLabel = "showsVersionLabel"
    }

    /// The cycle intervals the configuration sheet offers, in seconds (Slow, Normal, Fast).
    static let cycleIntervals: [TimeInterval] = [6, 3, 1]

    struct Snapshot {
        let cycleInterval: TimeInterval
        let showsVersionLabel: Bool
    }

    private let defaults: UserDefaults
    private var isObserving = false
    private let moduleName: String
    private let logger = AppexLog.logger("Settings")

    private override init() {
        // The module name must be this bundle's identifier: inside the sandbox,
        // cfprefsd lets the extension write only its own preference domain.
        let module = Bundle(for: AppexSaverSettings.self).bundleIdentifier
            ?? "net.aerialscreensaver.AppexSaverMinimal.Extension"
        moduleName = module
        defaults = ScreenSaverDefaults(forModuleWithName: module) ?? .standard
        defaults.register(defaults: [
            Key.cycleInterval: 3.0,
            Key.showsVersionLabel: true,
        ])
        super.init()
        // The sheet runs in the instance System Settings hosts, while the live
        // wallpaper and the screensaver run in the instance the Wallpaper agent
        // hosts. Both read the same domain. UserDefaults.didChangeNotification
        // is only posted for writes made in the same process; key-value
        // observing on the defaults object reports writes from any process.
        for key in [Key.cycleInterval, Key.showsVersionLabel] {
            defaults.addObserver(self, forKeyPath: key, options: [.new], context: nil)
        }
        isObserving = true
    }

    deinit {
        if isObserving {
            for key in [Key.cycleInterval, Key.showsVersionLabel] {
                defaults.removeObserver(self, forKeyPath: key)
            }
        }
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?,
                               change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        guard keyPath == Key.cycleInterval || keyPath == Key.showsVersionLabel else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
            return
        }
        logger.notice("KVO \(keyPath ?? "?", privacy: .public) -> \(String(describing: change?[.newKey]), privacy: .public)")
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
        }
    }

    /// Re-reads the store before a view applies it.
    ///
    /// Measured on macOS 27.2: when the sheet (in the instance System Settings
    /// hosts) writes a value, the agent-hosted instance receives the KVO
    /// change, but its ScreenSaverDefaults object keeps returning the previous
    /// value until synchronize() is called.
    func reload() {
        #if DEBUG
        let cached = "\(defaults.double(forKey: Key.cycleInterval))/\(defaults.bool(forKey: Key.showsVersionLabel))"
        #endif
        defaults.synchronize()
        #if DEBUG
        let current = "\(defaults.double(forKey: Key.cycleInterval))/\(defaults.bool(forKey: Key.showsVersionLabel))"
        if cached != current {
            logger.notice("reload refreshed \(cached, privacy: .public) -> \(current, privacy: .public)")
        }
        #endif
    }

    /// Seconds between two colours.
    var cycleInterval: TimeInterval {
        get { defaults.double(forKey: Key.cycleInterval) }
        set {
            defaults.set(newValue, forKey: Key.cycleInterval)
            didChange()
        }
    }

    /// Whether the version label is drawn over the colours.
    var showsVersionLabel: Bool {
        get { defaults.bool(forKey: Key.showsVersionLabel) }
        set {
            defaults.set(newValue, forKey: Key.showsVersionLabel)
            didChange()
        }
    }

    func snapshot() -> Snapshot {
        Snapshot(cycleInterval: cycleInterval, showsVersionLabel: showsVersionLabel)
    }

    func restore(_ snapshot: Snapshot) {
        cycleInterval = snapshot.cycleInterval
        showsVersionLabel = snapshot.showsVersionLabel
    }

    /// Flush to disk so the other instance of the extension sees the value;
    /// the key-value observer above posts `didChangeNotification` for this
    /// process as well as for the other one.
    private func didChange() {
        defaults.synchronize()
    }
}
