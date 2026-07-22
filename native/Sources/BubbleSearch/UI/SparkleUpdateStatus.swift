//
//  SparkleUpdateStatus.swift
//  BubbleSearch
//
//  Created by Vishrut Jha on 7/22/26.
//

import Foundation

enum SparkleUpdateStatus: Equatable {
    case idle
    case permissionRequest
    case checking
    case updateAvailable(SparkleUpdateOffer)
    case backgroundDownloading(SparkleUpdateOffer)
    case downloading(progress: Double?, detail: String?)
    case extracting(progress: Double)
    case readyToInstall(SparkleUpdateOffer?)
    case installing
    case result(message: String, isError: Bool)

    var isIdle: Bool {
        self == .idle
    }

    var titlebarText: String {
        switch self {
        case .idle:
            ""
        case .permissionRequest:
            "Enable Automatic Updates?"
        case .checking:
            "Checking for Updates…"
        case .updateAvailable(let offer):
            "Update Available: \(offer.version)"
        case .backgroundDownloading(let offer):
            "Downloading \(offer.version)…"
        case .downloading(let progress, _):
            if let progress {
                "Downloading: \(progress.formatted(.percent.precision(.fractionLength(0))))"
            } else {
                "Downloading Update…"
            }
        case .extracting(let progress):
            "Preparing: \(progress.formatted(.percent.precision(.fractionLength(0))))"
        case .readyToInstall(let offer):
            if let offer {
                "Update \(offer.version) Ready"
            } else {
                "Update Ready"
            }
        case .installing:
            "Installing Update…"
        case .result(_, let isError):
            isError ? "Update Failed" : "You’re Up to Date"
        }
    }

    var iconName: String {
        switch self {
        case .idle:
            ""
        case .permissionRequest:
            "questionmark.circle"
        case .checking:
            "arrow.triangle.2.circlepath"
        case .updateAvailable:
            "shippingbox.fill"
        case .backgroundDownloading, .downloading:
            "arrow.down.circle"
        case .extracting:
            "shippingbox"
        case .readyToInstall:
            "checkmark.circle.fill"
        case .installing:
            "power.circle"
        case .result(_, let isError):
            isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
        }
    }
}
