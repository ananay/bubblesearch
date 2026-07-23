//
//  SparkleUpdateAvailableView.swift
//  BubbleSearch
//
//  Created by Vishrut Jha on 7/22/26.
//

import SwiftUI

struct SparkleUpdateAvailableView: View {
    let offer: SparkleUpdateOffer
    @ObservedObject var controller: SparkleUpdateController

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                Text(offer.informationOnly ? "Update Information" : "Update Available")
                    .font(.headline)

                Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 5) {
                    GridRow {
                        Text("Version:")
                            .foregroundStyle(.secondary)
                            .gridColumnAlignment(.trailing)
                        Text(offer.version)
                            .textSelection(.enabled)
                    }
                    if let contentLength = offer.contentLength {
                        GridRow {
                            Text("Size:")
                                .foregroundStyle(.secondary)
                            Text(
                                ByteCountFormatter.string(
                                    fromByteCount: Int64(contentLength),
                                    countStyle: .file
                                )
                            )
                        }
                    }
                    if let releaseDate = offer.releaseDate {
                        GridRow {
                            Text("Released:")
                                .foregroundStyle(.secondary)
                            Text(releaseDate, format: .dateTime.month(.abbreviated).day().year())
                        }
                    }
                }
                .font(.callout)

                HStack(spacing: 8) {
                    if !offer.informationOnly && !offer.isCritical {
                        Button("Skip", action: controller.skipUpdate)
                    }
                    Button("Later", action: controller.dismissUpdate)
                    Spacer()
                    if offer.informationOnly {
                        Button("Learn More", action: controller.openUpdateDetails)
                            .buttonStyle(.borderedProminent)
                            .disabled(offer.detailsURL == nil)
                    } else {
                        Button("Install and Relaunch", action: controller.install)
                            .buttonStyle(.borderedProminent)
                    }
                }
                .controlSize(.small)
            }
            .padding(16)

            if let notes = offer.notes {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Label("What’s New", systemImage: "doc.text")
                        .font(.callout)
                        .bold()
                    Text(notes)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
            } else if offer.detailsURL != nil && !offer.informationOnly {
                Divider()
                Button("View Release Notes", systemImage: "doc.text", action: controller.openUpdateDetails)
                    .buttonStyle(.plain)
                    .padding(14)
            }
        }
    }
}
