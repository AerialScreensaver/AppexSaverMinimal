//
//  AppexSaverMinimalView.swift
//  AppexSaverMinimalExtension
//
//  Copyright © 2026 Guillaume Louel. Licensed under the MIT License.
//
//  ScreenSaverView that displays the rainbow color animation. The animation
//  logic lives in RainbowAnimator (shared with the host app's PreviewView);
//  the two user settings come from AppexSaverSettings.
//
//  Two equally valid rendering options exist for an app-extension screensaver:
//    1. Drive the drawing yourself, with Core Animation or your own timer, and
//       set SSENeedsAnimationTimer to false in Info.plist (this sample).
//    2. Set SSENeedsAnimationTimer to true and override animateOneFrame():
//       the framework then calls it at animationTimeInterval, on every view.
//       Measured on macOS 27.2: 60 calls per second per display at 1/60.
//
//  SwiftUI can also be used for screensaver content via NSHostingView: create
//  the SwiftUI root view, wrap it in NSHostingView, and add it as a subview
//  of this ScreenSaverView. The Aerial screensaver used this pattern for
//  weather/clock overlays on top of video playback.
//

import ScreenSaver
import QuartzCore

private let logger = AppexLog.logger("View")

final class AppexSaverMinimalView: ScreenSaverView {

    private let animator = RainbowAnimator()
    private let settings = AppexSaverSettings.shared
    private var settingsObserver: NSObjectProtocol?

    #if DEBUG
    private let diagnostics = ViewDiagnostics()
    #endif

    override init?(frame: NSRect, isPreview: Bool) {
        logger.info("init(frame: \(NSStringFromRect(frame), privacy: .public), isPreview: \(isPreview))")
        super.init(frame: frame, isPreview: isPreview)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    deinit {
        if let observer = settingsObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        animator.stop()
        logger.info("deinit")
    }

    // MARK: - Layer Setup

    override func makeBackingLayer() -> CALayer {
        let layer = CALayer()
        layer.backgroundColor = animator.currentBackgroundColor.cgColor
        layer.isOpaque = true
        return layer
    }

    // MARK: - ScreenSaverView Overrides
    //
    // Measured on macOS 27.2: the host calls startAnimation() once per view
    // after sizing its window, but it releases the views at the end of a
    // session without calling stopAnimation(). The sample therefore starts and
    // stops the animator from viewDidMoveToWindow() as well (the last call a
    // released view receives, with a nil window) and treats these two as
    // optional. RainbowAnimator.start() is idempotent, so either path is safe.

    override func startAnimation() {
        logger.info("startAnimation()")
        #if DEBUG
        diagnostics.didStartAnimation(self)
        #endif
        super.startAnimation()
        applySettings()
        animator.start()
    }

    override func stopAnimation() {
        logger.info("stopAnimation()")
        #if DEBUG
        diagnostics.didStopAnimation(self)
        #endif
        animator.stop()
        super.stopAnimation()
    }

    override func animateOneFrame() {
        super.animateOneFrame()
        #if DEBUG
        diagnostics.didAnimateFrame()
        #endif
    }

    // MARK: - View Lifecycle

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        logger.info("viewDidMoveToWindow() hasWindow=\(self.window != nil)")
        #if DEBUG
        diagnostics.logGeometry(self, "viewDidMoveToWindow")
        #endif

        if self.window != nil {
            if let layer = self.layer {
                animator.attach(to: layer)
                animator.updateBounds(bounds)
            }
            applySettings()
            observeSettings()
            animator.start()
        } else {
            animator.stop()
        }
    }

    override func layout() {
        super.layout()
        animator.updateBounds(bounds)
        #if DEBUG
        diagnostics.logGeometryIfChanged(self, "layout")
        #endif
    }

    // The host attaches the window at zero size and resizes it a few
    // milliseconds later (see remoteViewSizeChanged in the view controller).
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        #if DEBUG
        diagnostics.logGeometry(self, "setFrameSize")
        #endif
    }

    // MARK: - Settings

    /// Called when a view starts and whenever the store changes. The Wallpaper
    /// agent keeps one instance of the extension running across activations,
    /// so each new view must read the store afresh rather than trust values
    /// cached by an earlier one.
    private func applySettings() {
        settings.reload()
        animator.interval = settings.cycleInterval
        animator.showsLabel = settings.showsVersionLabel
        logger.info("applySettings interval=\(self.animator.interval, privacy: .public) showsLabel=\(self.animator.showsLabel, privacy: .public)")
    }

    private func observeSettings() {
        guard settingsObserver == nil else { return }
        settingsObserver = NotificationCenter.default.addObserver(
            forName: AppexSaverSettings.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.applySettings()
        }
    }
}
