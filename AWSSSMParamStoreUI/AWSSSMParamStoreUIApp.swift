//
//  AWSSSMParamStoreUIApp.swift
//  AWS SSM Param Store UI
//
//  Created by Bilal Fazlani on 01/12/25.
//

import SwiftUI

@main
struct AWSSSMParamStoreUIApp: App {
    // Initialize WindowManager to start observing
    private let windowManager = WindowManager.shared
    @FocusedObject private var appState: AppState?

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Tab") {
                    WindowManager.shared.openNewTab()
                }
                .keyboardShortcut("t", modifiers: [.command])
                
                Button("New Window") {
                    WindowManager.shared.openNewWindow()
                }
                .keyboardShortcut("n", modifiers: [.command])
            }
            CommandGroup(after: .help) {
                Button("What's New?") {
                    appState?.showReleaseNotes()
                }
            }
        }
    }
}
