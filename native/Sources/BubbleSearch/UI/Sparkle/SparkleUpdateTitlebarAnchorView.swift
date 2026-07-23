//
//  SparkleUpdateTitlebarAnchorView.swift
//  BubbleSearch
//
//  Created by Vishrut Jha on 7/22/26.
//

import AppKit

final class SparkleUpdateTitlebarAnchorView: NSView {
    var controller: SparkleUpdateController {
        didSet {
            updateAccessoryContent()
        }
    }

    private weak var installedWindow: NSWindow?
    private var accessory: NSTitlebarAccessoryViewController?

    init(controller: SparkleUpdateController) {
        self.controller = controller
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        guard let window else {
            removeAccessory()
            return
        }

        installAccessory(in: window)
    }

    func removeAccessory() {
        guard
            let installedWindow,
            let accessory,
            let index = installedWindow.titlebarAccessoryViewControllers.firstIndex(where: { $0 === accessory })
        else {
            accessory = nil
            installedWindow = nil
            return
        }

        installedWindow.removeTitlebarAccessoryViewController(at: index)
        self.accessory = nil
        self.installedWindow = nil
    }

    private func installAccessory(in window: NSWindow) {
        if installedWindow === window, accessory != nil {
            updateAccessoryContent()
            return
        }

        removeAccessory()

        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none

        let accessory = NSTitlebarAccessoryViewController()
        accessory.layoutAttribute = .right
        accessory.view = makeHostingView()
        window.addTitlebarAccessoryViewController(accessory)

        installedWindow = window
        self.accessory = accessory
    }

    private func updateAccessoryContent() {
        guard let hostingView = accessory?.view as? SparkleUpdateHostingView else { return }
        hostingView.rootView = accessoryView
    }

    private func makeHostingView() -> SparkleUpdateHostingView {
        let hostingView = SparkleUpdateHostingView(rootView: accessoryView)
        hostingView.sizingOptions = [.intrinsicContentSize]
        hostingView.setFrameSize(hostingView.fittingSize)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        return hostingView
    }

    private var accessoryView: SparkleUpdateTitlebarContent {
        SparkleUpdateTitlebarContent(controller: controller)
    }
}
