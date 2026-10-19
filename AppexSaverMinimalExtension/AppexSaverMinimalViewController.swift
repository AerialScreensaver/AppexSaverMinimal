//
//  AppexSaverMinimalViewController.swift
//  AppexSaverMinimalExtension
//
//  Copyright © 2026 Guillaume Louel. Licensed under the MIT License.
//
//  Main view controller for the screensaver. Specified as
//  ScreenSaverViewControllerClass in Info.plist as
//  `$(PRODUCT_MODULE_NAME).AppexSaverMinimalViewController`.
//
//  Mirrors Apple's own screensavers (Arabesque, Flurry, Hello): override the
//  standard initializers and loadView(), and let the framework drive the rest.
//

import AppKit
import ScreenSaver

private let logger = AppexLog.logger("ViewController")

@objc(AppexSaverMinimalViewController)
class AppexSaverMinimalViewController: ScreenSaverViewController {

    /// Strong reference so the framework can't drop the view while this controller still owns it.
    private var saverView: AppexSaverMinimalView?

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

    /// Called by the framework to create the view.
    ///
    /// The host sizes the remote view after attaching it, so the frame is not
    /// known here, and the host cannot feed `isPreview` into the view's
    /// initializer. Apple's own screensavers do the same as below: a zero frame,
    /// `isPreview: false`, and autoresizing to follow the host's resizes.
    override func loadView() {
        logger.info("loadView()")
        #if DEBUG
        AppexDiagnostics.didLoadView()
        #endif

        let view = AppexSaverMinimalView(frame: .zero, isPreview: false)
        view?.autoresizingMask = [.width, .height]
        saverView = view
        self.view = view ?? NSView(frame: .zero)
    }

    #if DEBUG
    override func remoteViewSizeChanged(_ size: NSSize, transaction: Any?) -> Bool {
        let result = super.remoteViewSizeChanged(size, transaction: transaction)
        logger.notice("remoteViewSizeChanged(\(NSStringFromSize(size), privacy: .public)) transaction=\(transaction.map { String(describing: type(of: $0)) } ?? "nil", privacy: .public) -> \(result, privacy: .public)")
        return result
    }
    #endif

    override func viewWillAppear() {
        super.viewWillAppear()
        logger.info("viewWillAppear()")
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        logger.info("viewDidAppear()")
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        logger.info("viewWillDisappear()")
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        logger.info("viewDidDisappear()")
    }
}
