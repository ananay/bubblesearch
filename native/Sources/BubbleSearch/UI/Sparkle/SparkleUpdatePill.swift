//
//  SparkleUpdatePill.swift
//  BubbleSearch
//
//  Created by Vishrut Jha on 7/22/26.
//

import SwiftUI

struct SparkleUpdatePill: View {
    @ObservedObject var controller: SparkleUpdateController
    @State private var isPopoverPresented = false

    var body: some View {
        Button(action: togglePopover) {
            HStack(spacing: 6) {
                SparkleUpdateBadge(status: controller.status)
                Text(controller.status.titlebarText)
                    .lineLimit(1)
            }
            .font(.caption)
            .bold()
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .foregroundStyle(foregroundColor)
            .background(backgroundColor, in: .capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .help(controller.status.titlebarText)
        .accessibilityLabel(controller.status.titlebarText)
        .accessibilityInputLabels(["Software Update", "Update"])
        .accessibilityHidden(controller.status.isIdle)
        .opacity(controller.status.isIdle ? 0 : 1)
        .allowsHitTesting(!controller.status.isIdle)
        .popover(isPresented: $isPopoverPresented, arrowEdge: .bottom) {
            SparkleUpdatePopover(controller: controller)
        }
        .onChange(of: controller.presentationRequest) {
            isPopoverPresented = true
        }
        .onChange(of: controller.status) { _, status in
            if status.isIdle {
                isPopoverPresented = false
            }
        }
    }

    private var foregroundColor: Color {
        switch controller.status {
        case .updateAvailable, .readyToInstall:
            .white
        case .result(_, true):
            .orange
        default:
            .primary
        }
    }

    private var backgroundColor: Color {
        switch controller.status {
        case .updateAvailable, .readyToInstall:
            .accentColor
        case .result(_, true):
            .orange.opacity(0.18)
        case .result(_, false):
            .green.opacity(0.18)
        default:
            Color(nsColor: .controlBackgroundColor)
        }
    }

    private func togglePopover() {
        isPopoverPresented.toggle()
    }
}
