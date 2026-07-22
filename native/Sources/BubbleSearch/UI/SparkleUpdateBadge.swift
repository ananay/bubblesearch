//
//  SparkleUpdateBadge.swift
//  BubbleSearch
//
//  Created by Vishrut Jha on 7/22/26.
//

import SwiftUI

struct SparkleUpdateBadge: View {
    let status: SparkleUpdateStatus

    var body: some View {
        switch status {
        case .idle:
            Color.clear
                .frame(width: 14, height: 14)
        case .checking, .backgroundDownloading, .installing:
            ProgressView()
                .controlSize(.mini)
                .frame(width: 14, height: 14)
        case .downloading(let progress, _):
            if let progress {
                ProgressView(value: progress)
                    .progressViewStyle(.circular)
                    .controlSize(.mini)
                    .frame(width: 14, height: 14)
            } else {
                ProgressView()
                    .controlSize(.mini)
                    .frame(width: 14, height: 14)
            }
        case .extracting(let progress):
            ProgressView(value: progress)
                .progressViewStyle(.circular)
                .controlSize(.mini)
                .frame(width: 14, height: 14)
        case .permissionRequest, .updateAvailable, .readyToInstall, .result:
            Image(systemName: status.iconName)
                .frame(width: 14, height: 14)
        }
    }
}
