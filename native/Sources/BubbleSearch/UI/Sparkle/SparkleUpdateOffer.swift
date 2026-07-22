//
//  SparkleUpdateOffer.swift
//  BubbleSearch
//
//  Created by Vishrut Jha on 7/22/26.
//

import Foundation

struct SparkleUpdateOffer: Equatable {
    enum Stage: Equatable {
        case notDownloaded
        case downloaded
        case installing
    }

    let version: String
    let contentLength: UInt64?
    let releaseDate: Date?
    let notes: String?
    let releaseNotesURL: URL?
    let informationOnly: Bool
    let informationURL: URL?
    let isCritical: Bool
    let stage: Stage

    var detailsURL: URL? {
        if informationOnly {
            informationURL ?? releaseNotesURL
        } else {
            releaseNotesURL ?? informationURL
        }
    }
}
