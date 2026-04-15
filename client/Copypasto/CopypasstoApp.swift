import SwiftUI

@main
struct CopypasstoApp: App {
    @StateObject private var authService = AuthService()

    private var menuBarIcon: String {
        guard authService.isLoggedIn else { return "clipboard" }
        return authService.connectionState.isConnected ? "clipboard.fill" : "clipboard"
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(authService)
        } label: {
            Label("Copypasto", systemImage: menuBarIcon)
        }
        .menuBarExtraStyle(.window)
    }
}
