import SwiftUI
import AVFoundation

@main
struct AkamedikaApp: App {
    @State private var authViewModel = AuthViewModel()

    init() {
        // `.playback` keeps lesson video audio going when the device is locked or
        // the ringer is silenced (paired with the `audio` background mode). The
        // category is just declared here; iOS starts the session when a video plays.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if authViewModel.isLoggedIn {
                    MainTabView {
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

/// Root tab bar shown once the user is signed in. "Kurslarım" lists every
/// course (enrolled in-app, others open in Safari to purchase); "Profilim"
/// is the account screen previously reached from the toolbar.
struct MainTabView: View {
    var onLogout: () -> Void

    init(onLogout: @escaping () -> Void) {
        self.onLogout = onLogout
        Self.configureTabBarAppearance()
    }

    var body: some View {
        TabView {
            CourseListView()
                .tabItem {
                    Label("Kurslarım", systemImage: "books.vertical.fill")
                }

            NavigationStack {
                ProfileView(onLogout: onLogout)
            }
            .tabItem {
                Label("Profilim", systemImage: "person.crop.circle")
            }
        }
        .tint(Theme.accent)
    }

    /// Opaque dark tab bar matching the app background so it doesn't render as
    /// a translucent light bar over the dark UI.
    private static func configureTabBarAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(Theme.background)
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
}
