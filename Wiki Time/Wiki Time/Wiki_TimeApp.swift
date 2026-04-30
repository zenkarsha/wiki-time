//
//  Wiki_TimeApp.swift
//  Wiki Time
//
//  Created by zenkarsha on 2026/4/29.
//

import SwiftUI

@main
struct Wiki_TimeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
