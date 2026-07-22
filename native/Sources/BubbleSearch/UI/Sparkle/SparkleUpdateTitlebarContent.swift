//
//  SparkleUpdateTitlebarContent.swift
//  BubbleSearch
//
//  Created by Vishrut Jha on 7/22/26.
//

import SwiftUI

struct SparkleUpdateTitlebarContent: View {
    @ObservedObject var controller: SparkleUpdateController

    var body: some View {
        SparkleUpdatePill(controller: controller)
            .frame(minWidth: 220, minHeight: 26, alignment: .trailing)
            .padding(.trailing, 8)
    }
}
