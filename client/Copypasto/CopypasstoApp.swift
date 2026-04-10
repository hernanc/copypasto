import SwiftUI

@main
struct CopypasstoApp: App {
    @StateObject private var authService = AuthService()

    var body: some Scene {
        MenuBarExtra("Copypasto", systemImage: "clipboard") {
            MenuBarView()
                .environmentObject(authService)
        }
        .menuBarExtraStyle(.window)
    }
}
