//
//  RainbowAnimator.swift
//  AppexSaverMinimal
//
//  Copyright © 2026 Guillaume Louel. Licensed under the MIT License.
//
//  Six-color fallback animation modeled on the Aerial screensaver's fallback
//  view. Cross-fades a CALayer's backgroundColor through the six hues of the
//  1977 Apple rainbow logo. `interval` sets the time between colours (3 s by
//  default) and the cross-fade takes two thirds of it, at most 2 s.
//
//  Shared between AppexSaverMinimalView (the app extension) and PreviewView
//  (the host app preview window) so the two render identically. The extension
//  drives `interval` and `showsLabel` from its settings.
//

import AppKit
import QuartzCore

final class RainbowAnimator {

    /// Six hues from the 1977–1998 Apple rainbow logo (top → bottom).
    private let colors: [NSColor] = [
        NSColor(red: 0x61/255.0, green: 0xBB/255.0, blue: 0x46/255.0, alpha: 1.0), // green
        NSColor(red: 0xFD/255.0, green: 0xB8/255.0, blue: 0x27/255.0, alpha: 1.0), // yellow
        NSColor(red: 0xF5/255.0, green: 0x82/255.0, blue: 0x1F/255.0, alpha: 1.0), // orange
        NSColor(red: 0xE0/255.0, green: 0x3A/255.0, blue: 0x3E/255.0, alpha: 1.0), // red
        NSColor(red: 0x96/255.0, green: 0x3D/255.0, blue: 0x97/255.0, alpha: 1.0), // purple
        NSColor(red: 0x00/255.0, green: 0x9D/255.0, blue: 0xDC/255.0, alpha: 1.0)  // blue
    ]

    /// Seconds between two colours. Changing it while running restarts the timer.
    var interval: TimeInterval = 3.0 {
        didSet {
            guard interval != oldValue, timer != nil else { return }
            stop()
            start()
        }
    }

    /// Whether the version label is drawn over the colours.
    var showsLabel: Bool = true {
        didSet { labelLayer?.isHidden = !showsLabel }
    }

    /// Two thirds of the interval, capped at 2 s, so Fast (1 s) still shows distinct colours.
    private var fadeDuration: TimeInterval { min(2.0, interval * 0.66) }

    private weak var parentLayer: CALayer?
    private var labelLayer: CATextLayer?
    private var timer: Timer?
    private var index: Int = 0

    /// Used by the view's `makeBackingLayer()` to set the initial background color.
    var currentBackgroundColor: NSColor { colors[index] }

    func attach(to layer: CALayer) {
        parentLayer = layer
        layer.backgroundColor = colors[index].cgColor
        layer.isOpaque = true
        if labelLayer == nil {
            installLabel(in: layer)
        }
    }

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.advance()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func updateBounds(_ bounds: CGRect) {
        recenterLabel(in: bounds)
    }

    // MARK: - Implementation

    private func advance() {
        guard let layer = parentLayer else { return }
        index = (index + 1) % colors.count
        let nextColor = colors[index]

        let animation = CABasicAnimation(keyPath: "backgroundColor")
        animation.fromValue = layer.backgroundColor
        animation.toValue = nextColor.cgColor
        animation.duration = fadeDuration
        layer.add(animation, forKey: "backgroundColorAnimation")
        layer.backgroundColor = nextColor.cgColor
    }

    private func installLabel(in parent: CALayer) {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"

        let text = CATextLayer()
        text.string = "AppexSaverMinimal · v\(version) (\(build))"
        text.font = NSFont.systemFont(ofSize: 22, weight: .medium)
        text.fontSize = 22
        text.isHidden = !showsLabel
        text.foregroundColor = NSColor.white.cgColor
        text.alignmentMode = .center
        text.shadowColor = NSColor.black.cgColor
        text.shadowOpacity = 0.6
        text.shadowRadius = 6
        text.shadowOffset = .zero
        text.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
        parent.addSublayer(text)
        labelLayer = text
        recenterLabel(in: parent.bounds)
    }

    private func recenterLabel(in bounds: CGRect) {
        guard let text = labelLayer else { return }
        let width: CGFloat = 640
        let height: CGFloat = 32
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        text.frame = CGRect(
            x: bounds.midX - width / 2,
            y: bounds.midY - height / 2,
            width: width,
            height: height
        )
        CATransaction.commit()
    }
}
