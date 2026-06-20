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
