//
//  TitlebarSparkleUserDriver.swift
//  BubbleSearch
//
//  Created by Vishrut Jha on 7/22/26.
//

import Sparkle

@MainActor
final class TitlebarSparkleUserDriver: NSObject, SPUUserDriver, SPUUpdaterDelegate {
    weak var delegate: (any TitlebarSparkleUserDriverDelegate)?

    private var expectedContentLength: UInt64 = 0
    private var receivedContentLength: UInt64 = 0
    private var downloadCancellation: (() -> Void)?

    func show(
        _ request: SPUUpdatePermissionRequest,
        reply: @escaping (SUUpdatePermissionResponse) -> Void
    ) {
        delegate?.userDriverDidRequestPermission(reply: reply)
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        delegate?.userDriverDidStartCheck(cancellation: cancellation)
    }

    func showUpdateFound(
        with appcastItem: SUAppcastItem,
        state: SPUUserUpdateState
    ) async -> SPUUserUpdateChoice {
        let offer = Self.offer(from: appcastItem, stage: Self.stage(from: state.stage))
        return await withCheckedContinuation { continuation in
            guard let delegate else {
                continuation.resume(returning: .dismiss)
                return
            }
            delegate.userDriverDidFindUpdate(offer) { choice in
                continuation.resume(returning: choice)
            }
        }
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}

    func showUpdateNotFoundWithError(_ error: Error) async {
        delegate?.userDriverDidFinish(message: "You’re up to date!", isError: false)
    }

    func showUpdaterError(_ error: Error) async {
        delegate?.userDriverDidFinish(message: error.localizedDescription, isError: true)
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        expectedContentLength = 0
        receivedContentLength = 0
        downloadCancellation = cancellation
        delegate?.userDriverDidChangeProgress(
            .downloading(progress: nil, detail: nil),
            cancellation: cancellation
        )
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        self.expectedContentLength = expectedContentLength
        publishDownloadProgress()
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        receivedContentLength += length
        publishDownloadProgress()
    }

    func showDownloadDidStartExtractingUpdate() {
        downloadCancellation = nil
        delegate?.userDriverDidChangeProgress(.extracting(progress: 0), cancellation: nil)
    }

    func showExtractionReceivedProgress(_ progress: Double) {
        delegate?.userDriverDidChangeProgress(.extracting(progress: progress), cancellation: nil)
    }

    func showReadyToInstallAndRelaunch() async -> SPUUserUpdateChoice {
        await withCheckedContinuation { continuation in
            guard let delegate else {
                continuation.resume(returning: .dismiss)
                return
            }
            delegate.userDriverNeedsChoice(for: .readyToInstall(nil)) { choice in
                continuation.resume(returning: choice)
            }
        }
    }

    func showInstallingUpdate(
        withApplicationTerminated applicationTerminated: Bool,
        retryTerminatingApplication: @escaping () -> Void
    ) {
        delegate?.userDriverDidStartInstalling(
            applicationTerminated: applicationTerminated,
            retry: retryTerminatingApplication
        )
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool) async {
        if !relaunched {
            delegate?.userDriverDidFinish(
                message: "BubbleSearch was updated successfully.",
                isError: false
            )
        }
    }

    func dismissUpdateInstallation() {
        delegate?.userDriverDidDismissUpdate()
    }

    func showUpdateInFocus() {
        delegate?.userDriverDidRequestFocus()
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        delegate?.userDriverDidFindBackgroundUpdate(Self.offer(from: item, stage: .notDownloaded))
    }

    func updater(
        _ updater: SPUUpdater,
        willInstallUpdateOnQuit item: SUAppcastItem,
        immediateInstallationBlock immediateInstallHandler: @escaping () -> Void
    ) -> Bool {
        guard let delegate else { return false }
        delegate.userDriverIsReadyToInstallOnQuit(
            Self.offer(from: item, stage: .downloaded),
            install: immediateInstallHandler
        )
        return true
    }

    static func offer(
        from appcastItem: SUAppcastItem,
        stage: SparkleUpdateOffer.Stage
    ) -> SparkleUpdateOffer {
        SparkleUpdateOffer(
            version: appcastItem.displayVersionString,
            contentLength: appcastItem.contentLength > 0 ? appcastItem.contentLength : nil,
            releaseDate: appcastItem.date,
            notes: plainText(from: appcastItem.itemDescription),
            releaseNotesURL: appcastItem.releaseNotesURL,
            informationOnly: appcastItem.isInformationOnlyUpdate,
            informationURL: appcastItem.infoURL,
            isCritical: appcastItem.isCriticalUpdate,
            stage: stage
        )
    }

    static func plainText(from html: String?) -> String? {
        guard var text = html, !text.isEmpty else { return nil }
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        text = text.replacing("&nbsp;", with: " ")
        text = text.replacing("&amp;", with: "&")
        text = text.replacing("&lt;", with: "<")
        text = text.replacing("&gt;", with: ">")
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private func publishDownloadProgress() {
        let progress: Double? =
            expectedContentLength > 0
            ? min(Double(receivedContentLength) / Double(expectedContentLength), 1)
            : nil
        let received = ByteCountFormatter.string(
            fromByteCount: Int64(receivedContentLength),
            countStyle: .file
        )
        let detail: String
        if expectedContentLength > 0 {
            let expected = ByteCountFormatter.string(
                fromByteCount: Int64(expectedContentLength),
                countStyle: .file
            )
            detail = "\(received) of \(expected)"
        } else {
            detail = "\(received) downloaded"
        }
        delegate?.userDriverDidChangeProgress(
            .downloading(progress: progress, detail: detail),
            cancellation: downloadCancellation
        )
    }

    private static func stage(from stage: SPUUserUpdateStage) -> SparkleUpdateOffer.Stage {
        switch stage {
        case .notDownloaded:
            .notDownloaded
        case .downloaded:
            .downloaded
        case .installing:
            .installing
        @unknown default:
            .notDownloaded
        }
    }
}
