import SwiftUI

@main
struct AkamedikaApp: App {
    @State private var authViewModel = AuthViewModel()

    var body: some Scene {
        WindowGroup {
            Group {
                if authViewModel.isLoggedIn {
                    CourseListView {
                        authViewModel.logout()
                    }
                } else {
                    LoginView(viewModel: authViewModel)
                }
            }
            .preferredColorScheme(.dark)
            .tint(Theme.accent)
        }
    }
}
