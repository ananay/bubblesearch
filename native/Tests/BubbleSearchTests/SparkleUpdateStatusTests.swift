//
//  SparkleUpdateStatusTests.swift
//  BubbleSearchTests
//
//  Created by Vishrut Jha on 7/22/26.
//

import XCTest

@testable import bubblesearch

final class SparkleUpdateStatusTests: XCTestCase {
    func testUpdateAvailableTitleIncludesVersion() {
        let offer = makeOffer(version: "1.2.3")

        XCTAssertEqual(
            SparkleUpdateStatus.updateAvailable(offer).titlebarText,
            "Update Available: 1.2.3"
        )
    }

    func testDownloadingTitleFormatsProgress() {
        XCTAssertEqual(
            SparkleUpdateStatus.downloading(progress: 0.42, detail: nil).titlebarText,
            "Downloading: 42%"
        )
    }

    func testCriticalOfferRetainsReleaseMetadata() {
        let date = Date(timeIntervalSince1970: 1_753_200_000)
        let offer = makeOffer(
            version: "2.0",
            contentLength: 6_080_978,
            releaseDate: date,
            isCritical: true
        )

        XCTAssertEqual(offer.contentLength, 6_080_978)
        XCTAssertEqual(offer.releaseDate, date)
        XCTAssertTrue(offer.isCritical)
    }

    func testAppcastHTMLIsConvertedToPlainText() async {
        let text = await TitlebarSparkleUserDriver.plainText(
            from: "<p>Faster search &amp; safer updates.</p>"
        )

        XCTAssertEqual(text, "Faster search & safer updates.")
    }

    func testInformationOnlyOfferPrefersInformationURL() throws {
        let informationURL = try XCTUnwrap(URL(string: "https://example.com/info"))
        let releaseNotesURL = try XCTUnwrap(URL(string: "https://example.com/notes"))
        let offer = SparkleUpdateOffer(
            version: "2.0",
            contentLength: nil,
            releaseDate: nil,
            notes: nil,
            releaseNotesURL: releaseNotesURL,
            informationOnly: true,
            informationURL: informationURL,
            isCritical: false,
            stage: .notDownloaded
        )

        XCTAssertEqual(offer.detailsURL, informationURL)
    }

    @MainActor
    func testDownloadedOfferIsReadyToInstall() {
        let controller = SparkleUpdateController()
        let offer = makeOffer(version: "2.0", stage: .downloaded)

        controller.userDriverDidFindUpdate(offer) { _ in }

        XCTAssertEqual(controller.status, .readyToInstall(offer))
        controller.dismissUpdate()
    }

    @MainActor
    func testSparkleTeardownPreservesTerminalResult() {
        let controller = SparkleUpdateController()

        controller.userDriverDidFinish(message: "You’re up to date!", isError: false)
        controller.userDriverDidDismissUpdate()

        XCTAssertEqual(
            controller.status,
            .result(message: "You’re up to date!", isError: false)
        )
        controller.dismissStatus()
    }

    private func makeOffer(
        version: String,
        contentLength: UInt64? = nil,
        releaseDate: Date? = nil,
        isCritical: Bool = false,
        stage: SparkleUpdateOffer.Stage = .notDownloaded
    ) -> SparkleUpdateOffer {
        SparkleUpdateOffer(
            version: version,
            contentLength: contentLength,
            releaseDate: releaseDate,
            notes: nil,
            releaseNotesURL: nil,
            informationOnly: false,
            informationURL: nil,
            isCritical: isCritical,
            stage: stage
        )
    }
}
