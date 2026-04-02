import SwiftUI

@main
struct JumpSyncApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(appState)
        } label: {
            Label("JumpSync", systemImage: appState.menuBarIcon)
        }
        .menuBarExtraStyle(.window)

        Window("JumpSync", id: "main") {
            MainWindowView()
                .environment(appState)
                .frame(minWidth: 700, minHeight: 500)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 800, height: 560)

        Settings {
            ConfigurationView()
                .environment(appState)
        }
    }
}
