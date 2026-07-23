//
//  SparkleUpdateTitlebarAccessory.swift
//  BubbleSearch
//
//  Created by Vishrut Jha on 7/22/26.
//

import SwiftUI

struct SparkleUpdateTitlebarAccessory: NSViewRepresentable {
    @ObservedObject var controller: SparkleUpdateController

    func makeNSView(context: Context) -> SparkleUpdateTitlebarAnchorView {
        SparkleUpdateTitlebarAnchorView(controller: controller)
    }

    func updateNSView(_ nsView: SparkleUpdateTitlebarAnchorView, context: Context) {
        if nsView.controller !== controller {
            nsView.controller = controller
        }
    }

    static func dismantleNSView(_ nsView: SparkleUpdateTitlebarAnchorView, coordinator: ()) {
        nsView.removeAccessory()
    }
}
