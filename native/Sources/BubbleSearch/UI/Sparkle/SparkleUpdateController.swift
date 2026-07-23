//
//  SparkleUpdateController.swift
//  BubbleSearch
//
//  Created by Vishrut Jha on 7/22/26.
//

import AppKit
import Combine
import Sparkle

@MainActor
final class SparkleUpdateController: ObservableObject {
    @Published private(set) var status: SparkleUpdateStatus = .idle
    @Published private(set) var presentationRequest = 0

    private let updater: SPUUpdater?
    private let userDriver: TitlebarSparkleUserDriver?
    private var cancellation: (() -> Void)?
    private var choiceHandler: ((SPUUserUpdateChoice) -> Void)?
    private var permissionHandler: ((SUUpdatePermissionResponse) -> Void)?
    private var immediateInstallHandler: (() -> Void)?
    private var retryTerminationHandler: (() -> Void)?
    private var currentOffer: SparkleUpdateOffer?
    private var transientResultTask: Task<Void, Never>?

    init(bundle: Bundle = .main) {
        guard bundle.bundlePath.hasSuffix(".app") else {
            updater = nil
            userDriver = nil
            return
        }

        let driver = TitlebarSparkleUserDriver()
        userDriver = driver
        updater = SPUUpdater(
            hostBundle: bundle,
            applicationBundle: bundle,
            userDriver: driver,
            delegate: driver
        )
        driver.delegate = self

        do {
            try updater?.start()
        } catch {
            showResult(message: error.localizedDescription, isError: true)
        }
    }

    var isAvailable: Bool {
        updater != nil
    }

    var canRetryRelaunch: Bool {
        retryTerminationHandler != nil
    }

    func checkForUpdates() {
        guard let updater else { return }
        // A pending Sparkle interaction must be re-surfaced, never discarded:
        // the stored reply closures resume checked continuations inside
        // TitlebarSparkleUserDriver (and the install-on-quit block is
        // Sparkle's only install hook once willInstallUpdateOnQuit returns
        // true). Dropping one leaks the continuation and wedges Sparkle's
        // session — canCheckForUpdates is true while an update is shown
        // (SPUUpdater's updateShownHandler), so the guard below cannot
        // protect against this.
        if choiceHandler != nil || permissionHandler != nil || immediateInstallHandler != nil {
            presentPendingInteraction()
            return
        }
        guard updater.canCheckForUpdates else {
            presentPendingInteraction()
            return
        }
        resetInteractionHandlers()
        setStatus(.idle)
        updater.checkForUpdates()
    }

    func requestPresentation() {
        guard !status.isIdle else { return }
        presentationRequest += 1
    }

    /// Bring whatever Sparkle is waiting on (or quietly doing) back on
    /// screen. Used when a check is requested while a session is already in
    /// flight or was hidden with "Later"/"Hide" — the pill may be idle then,
    /// so restore the pending state before presenting the popover.
    private func presentPendingInteraction() {
        if status.isIdle {
            if immediateInstallHandler != nil {
                setStatus(.readyToInstall(currentOffer))
            } else if choiceHandler != nil {
                if let offer = currentOffer, offer.stage == .notDownloaded {
                    setStatus(.updateAvailable(offer))
                } else {
                    setStatus(.readyToInstall(currentOffer))
                }
            } else if permissionHandler != nil {
                setStatus(.permissionRequest)
            } else if let offer = currentOffer {
                setStatus(.backgroundDownloading(offer))
            } else {
                return // nothing pending to show
            }
        }
        presentationRequest += 1
    }

    func cancel() {
        let action = cancellation
        resetInteractionHandlers()
        setStatus(.idle)
        action?()
    }

    func allowAutomaticUpdates() {
        replyToPermission(automaticChecks: true)
    }

    func declineAutomaticUpdates() {
        replyToPermission(automaticChecks: false)
    }

    func install() {
        if let immediateInstallHandler {
            self.immediateInstallHandler = nil
            setStatus(.installing)
            immediateInstallHandler()
            return
        }
        reply(with: .install)
    }

    func dismissUpdate() {
        if choiceHandler == nil {
            // Keep immediateInstallHandler: once willInstallUpdateOnQuit
            // returns true, Sparkle's scheduler is stalled and this block is
            // the only remaining way to install (or re-present) the update.
            // "Later" just hides the pill; checkForUpdates() restores it.
            setStatus(.idle)
        } else {
            immediateInstallHandler = nil
            reply(with: .dismiss)
        }
    }

    func skipUpdate() {
        reply(with: .skip)
    }

    func openUpdateDetails() {
        guard case .updateAvailable(let offer) = status,
            let detailsURL = offer.detailsURL
        else { return }
        NSWorkspace.shared.open(detailsURL)
        if offer.informationOnly {
            dismissUpdate()
        }
    }

    func dismissStatus() {
        switch status {
        case .backgroundDownloading, .result:
            setStatus(.idle)
        default:
            break
        }
    }

    func retryUpdateCheck() {
        checkForUpdates()
    }

    func retryRelaunch() {
        retryTerminationHandler?()
    }

    private func replyToPermission(automaticChecks: Bool) {
        let handler = permissionHandler
        permissionHandler = nil
        setStatus(.idle)
        handler?(
            SUUpdatePermissionResponse(
                automaticUpdateChecks: automaticChecks,
                sendSystemProfile: false
            )
        )
    }

    private func reply(with choice: SPUUserUpdateChoice) {
        let handler = choiceHandler
        choiceHandler = nil
        setStatus(.idle)
        handler?(choice)
    }

    private func setStatus(_ status: SparkleUpdateStatus) {
        transientResultTask?.cancel()
        transientResultTask = nil
        self.status = status
    }

    private func showResult(message: String, isError: Bool) {
        setStatus(.result(message: message, isError: isError))
        guard !isError else { return }
        transientResultTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            guard case .result(let currentMessage, false) = self?.status,
                currentMessage == message
            else { return }
            self?.setStatus(.idle)
        }
    }

    private func resetInteractionHandlers() {
        cancellation = nil
        choiceHandler = nil
        permissionHandler = nil
        immediateInstallHandler = nil
        retryTerminationHandler = nil
    }
}

extension SparkleUpdateController: TitlebarSparkleUserDriverDelegate {
    func userDriverDidRequestPermission(reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        resetInteractionHandlers()
        permissionHandler = reply
        setStatus(.permissionRequest)
    }

    func userDriverDidStartCheck(cancellation: @escaping () -> Void) {
        resetInteractionHandlers()
        self.cancellation = cancellation
        setStatus(.checking)
    }

    func userDriverDidFindUpdate(
        _ offer: SparkleUpdateOffer,
        reply: @escaping (SPUUserUpdateChoice) -> Void
    ) {
        resetInteractionHandlers()
        currentOffer = offer
        choiceHandler = reply
        switch offer.stage {
        case .notDownloaded:
            setStatus(.updateAvailable(offer))
        case .downloaded, .installing:
            setStatus(.readyToInstall(offer))
        }
    }

    func userDriverDidFindBackgroundUpdate(_ offer: SparkleUpdateOffer) {
        currentOffer = offer
        if status.isIdle || status == .checking {
            setStatus(.backgroundDownloading(offer))
        }
    }

    func userDriverDidChangeProgress(
        _ status: SparkleUpdateStatus,
        cancellation: (() -> Void)?
    ) {
        self.cancellation = cancellation
        setStatus(status)
    }

    func userDriverNeedsChoice(
        for status: SparkleUpdateStatus,
        reply: @escaping (SPUUserUpdateChoice) -> Void
    ) {
        cancellation = nil
        // A stale install-on-quit block must not shadow this fresh choice in
        // install() — the reply continuation would leak.
        immediateInstallHandler = nil
        choiceHandler = reply
        if case .readyToInstall = status {
            setStatus(.readyToInstall(currentOffer))
        } else {
            setStatus(status)
        }
    }

    func userDriverIsReadyToInstallOnQuit(
        _ offer: SparkleUpdateOffer,
        install: @escaping () -> Void
    ) {
        resetInteractionHandlers()
        currentOffer = offer
        immediateInstallHandler = install
        setStatus(.readyToInstall(offer))
    }

    func userDriverDidStartInstalling(applicationTerminated: Bool, retry: @escaping () -> Void) {
        cancellation = nil
        retryTerminationHandler = applicationTerminated ? nil : retry
        setStatus(.installing)
    }

    func userDriverDidFinish(message: String, isError: Bool) {
        resetInteractionHandlers()
        showResult(message: message, isError: isError)
    }

    func userDriverDidRequestFocus() {
        requestPresentation()
    }

    func userDriverDidDismissUpdate() {
        let pendingChoice = choiceHandler
        let pendingPermission = permissionHandler
        resetInteractionHandlers()
        if case .result = status {
            // Sparkle tears down its session immediately after acknowledging a
            // terminal result. Keep the result visible for our brief UI timeout.
        } else {
            setStatus(.idle)
        }
        pendingChoice?(.dismiss)
        pendingPermission?(
            SUUpdatePermissionResponse(
                automaticUpdateChecks: false,
                sendSystemProfile: false
            )
        )
    }
}
