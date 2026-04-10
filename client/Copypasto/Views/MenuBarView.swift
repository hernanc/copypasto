import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var authService: AuthService

    var body: some View {
        if authService.isLoggedIn {
            ClipboardListView()
                .environmentObject(authService)
        } else {
            LoginView()
                .environmentObject(authService)
        }
    }
}
