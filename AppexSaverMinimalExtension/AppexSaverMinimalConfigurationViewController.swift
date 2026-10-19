//
//  AppexSaverMinimalConfigurationViewController.swift
//  AppexSaverMinimalExtension
//
//  Copyright © 2026 Guillaume Louel. Licensed under the MIT License.
//
//  Configuration sheet shown when the user clicks "Options…" next to the
//  screensaver in System Settings. Specified as
//  ScreenSaverConfigurationSheetViewControllerClass in Info.plist as
//  `$(PRODUCT_MODULE_NAME).AppexSaverMinimalConfigurationViewController`.
//
//  The sheet is presented by System Settings, in its process; this controller
//  and its view live in the extension's process and reach the sheet through a
//  remote view. That is why the controller subclasses
//  ScreenSaverConfigurationViewController and ends the sheet with
//  configureSheetDidEnd() rather than through its window.
//
//  SwiftUI works here too: build an NSHostingController(rootView:) and use its
//  view as self.view, keeping the same preferredContentSize.
//

import AppKit
import ScreenSaver

private let logger = AppexLog.logger("Configuration")

@objc(AppexSaverMinimalConfigurationViewController)
class AppexSaverMinimalConfigurationViewController: ScreenSaverConfigurationViewController {

    private let settings = AppexSaverSettings.shared
    /// Values when the sheet opened, restored on Cancel.
    private var snapshot: AppexSaverSettings.Snapshot?

    private let speedPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    private let labelCheckbox = NSButton(checkboxWithTitle: "Show version label", target: nil, action: nil)

    override init(nibName nibNameOrNil: NSNib.Name?, bundle nibBundleOrNil: Bundle?) {
        logger.info("init(nibName:bundle:)")
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
    }

    required init?(coder: NSCoder) {
        logger.info("init(coder:)")
        super.init(coder: coder)
    }

    deinit {
        logger.info("deinit")
    }

    // MARK: - View

    override func loadView() {
        logger.info("loadView()")
        #if DEBUG
        AppexDiagnostics.logManagerState("configuration loadView")
        #endif

        let title = NSTextField(labelWithString: "AppexSaverMinimal")
        title.font = .systemFont(ofSize: 15, weight: .semibold)

        speedPopUp.addItems(withTitles: ["Slow (6 seconds)", "Normal (3 seconds)", "Fast (1 second)"])
        speedPopUp.target = self
        speedPopUp.action = #selector(speedChanged(_:))

        labelCheckbox.target = self
        labelCheckbox.action = #selector(labelToggled(_:))

        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "Cycle speed:"), speedPopUp],
            [NSGridCell.emptyContentView, labelCheckbox],
        ])
        grid.rowAlignment = .firstBaseline
        grid.column(at: 0).xPlacement = .trailing

        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelPressed(_:)))
        cancel.keyEquivalent = "\u{1b}"
        let ok = NSButton(title: "OK", target: self, action: #selector(okPressed(_:)))
        ok.keyEquivalent = "\r"
        let buttons = NSStackView(views: [cancel, ok])
        buttons.orientation = .horizontal
        buttons.spacing = 12

        let root = NSView(frame: NSRect(x: 0, y: 0, width: 380, height: 170))
        for subview in [title, grid, buttons] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),
            title.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            grid.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 16),
            grid.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            grid.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -20),
            buttons.topAnchor.constraint(greaterThanOrEqualTo: grid.bottomAnchor, constant: 20),
            buttons.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            buttons.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -20),
        ])

        self.view = root
        self.preferredContentSize = root.frame.size
        reloadControls()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        logger.info("viewWillAppear()")
    }

    /// The framework calls this right before System Settings shows the sheet.
    override func configureSheetWillPresent() {
        logger.info("configureSheetWillPresent()")
        super.configureSheetWillPresent()
        snapshot = settings.snapshot()
        reloadControls()
    }

    private func reloadControls() {
        let index = AppexSaverSettings.cycleIntervals.firstIndex(of: settings.cycleInterval) ?? 1
        speedPopUp.selectItem(at: index)
        labelCheckbox.state = settings.showsVersionLabel ? .on : .off
    }

    // MARK: - Actions

    /// Changes apply immediately so the preview next to the sheet reflects them;
    /// Cancel restores the snapshot taken when the sheet opened.
    @objc private func speedChanged(_ sender: Any?) {
        let index = speedPopUp.indexOfSelectedItem
        guard AppexSaverSettings.cycleIntervals.indices.contains(index) else { return }
        settings.cycleInterval = AppexSaverSettings.cycleIntervals[index]
    }

    @objc private func labelToggled(_ sender: Any?) {
        settings.showsVersionLabel = labelCheckbox.state == .on
    }

    @objc private func okPressed(_ sender: Any?) {
        logger.info("OK")
        endSheet()
    }

    @objc private func cancelPressed(_ sender: Any?) {
        logger.info("Cancel")
        if let snapshot {
            settings.restore(snapshot)
        }
        endSheet()
    }

    private func endSheet() {
        // The sheet window belongs to System Settings and this view is a remote
        // view inside it: `view.window?.sheetParent` is nil, and `dismiss(_:)`
        // would only empty the remote view while the sheet stays up.
        // `configureSheetDidEnd()` asks the host to end the sheet.
        logger.info("endSheet() -> configureSheetDidEnd()")
        configureSheetDidEnd()
    }
}
