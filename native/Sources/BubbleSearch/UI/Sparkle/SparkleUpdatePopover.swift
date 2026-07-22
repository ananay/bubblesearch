//
//  SparkleUpdatePopover.swift
//  BubbleSearch
//
//  Created by Vishrut Jha on 7/22/26.
//

import SwiftUI

struct SparkleUpdatePopover: View {
    @ObservedObject var controller: SparkleUpdateController

    var body: some View {
        Group {
            switch controller.status {
            case .idle:
                EmptyView()
            case .permissionRequest:
                VStack(alignment: .leading, spacing: 14) {
                    Text("Enable automatic updates?")
                        .font(.headline)
                    Text("BubbleSearch can securely check the signed release feed in the background.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("Not Now", action: controller.declineAutomaticUpdates)
                        Spacer()
                        Button("Allow", action: controller.allowAutomaticUpdates)
                            .buttonStyle(.borderedProminent)
                    }
                }
                .padding(16)
            case .checking:
                VStack(alignment: .leading, spacing: 14) {
                    Label("Checking for updates…", systemImage: "arrow.triangle.2.circlepath")
                        .font(.headline)
                    HStack {
                        Spacer()
                        Button("Cancel", action: controller.cancel)
                    }
                }
                .padding(16)
            case .updateAvailable(let offer):
                SparkleUpdateAvailableView(offer: offer, controller: controller)
            case .backgroundDownloading(let offer):
                VStack(alignment: .leading, spacing: 12) {
                    Text("Downloading BubbleSearch \(offer.version)")
                        .font(.headline)
                    ProgressView()
                    Text(
                        "The signed update is downloading in the background. "
                            + "BubbleSearch will let you know when it is ready to install."
                    )
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Spacer()
                        Button("Hide", action: controller.dismissStatus)
                    }
                }
                .padding(16)
            case .downloading(let progress, let detail):
                VStack(alignment: .leading, spacing: 12) {
                    Text("Downloading Update")
                        .font(.headline)
                    if let progress {
                        ProgressView(value: progress)
                    } else {
                        ProgressView()
                    }
                    if let detail {
                        Text(detail)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Spacer()
                        Button("Cancel", action: controller.cancel)
                    }
                }
                .padding(16)
            case .extracting(let progress):
                VStack(alignment: .leading, spacing: 12) {
                    Text("Preparing Update")
                        .font(.headline)
                    ProgressView(value: progress)
                    Text(progress, format: .percent.precision(.fractionLength(0)))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
            case .readyToInstall(let offer):
                VStack(alignment: .leading, spacing: 14) {
                    Text("Update Ready")
                        .font(.headline)
                    Text(
                        offer.map { "BubbleSearch \($0.version) is ready to install." }
                            ?? "The update is ready to install."
                    )
                        .foregroundStyle(.secondary)
                    HStack {
                        Button("Later", action: controller.dismissUpdate)
                        Spacer()
                        Button("Install and Relaunch", action: controller.install)
                            .buttonStyle(.borderedProminent)
                    }
                }
                .padding(16)
            case .installing:
                VStack(alignment: .leading, spacing: 14) {
                    Text("Installing Update")
                        .font(.headline)
                    ProgressView()
                    HStack {
                        Spacer()
                        if controller.canRetryRelaunch {
                            Button("Retry Relaunch", action: controller.retryRelaunch)
                        }
                    }
                }
                .padding(16)
            case .result(let message, let isError):
                VStack(alignment: .leading, spacing: 14) {
                    Label(
                        isError ? "Update Failed" : "You’re Up to Date",
                        systemImage: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
                    )
                    .font(.headline)
                    .foregroundStyle(isError ? .orange : .primary)
                    Text(message)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("OK", action: controller.dismissStatus)
                        if isError {
                            Spacer()
                            Button("Retry", action: controller.retryUpdateCheck)
                                .buttonStyle(.borderedProminent)
                        }
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 330)
    }
}
