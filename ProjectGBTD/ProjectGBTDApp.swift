//
//  ProjectGBTDApp.swift
//  ProjectGBTD
//
//  Created by Steven on 4/25/26.
//

import SwiftUI

@main
struct ProjectGBTDApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .defaultSize(NSScreen.main?.visibleFrame.size ?? CGSize(width: 1400, height: 900))
    }
}
