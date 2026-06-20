import Foundation

@Observable
final class AuthViewModel {
    var isLoggedIn = false
    var isLoading = false
    var errorMessage: String?
    var username = ""
    var password = ""
    /// Set when the session expired mid-use; drives the re-login alert.
    var sessionExpired = false

    private let authService = AuthService()

    init() {
        isLoggedIn = APIClient.shared.token != nil
        if isLoggedIn, AuthService.currentUserId == nil {
            Task { await authService.fetchAndCacheUserId() }
        }
        // Force a re-login whenever any request reports an expired/invalid token.
        APIClient.shared.onSessionExpired = { [weak self] in
            Task { @MainActor in self?.handleSessionExpired() }
        }
    }

    @MainActor
    private func handleSessionExpired() {
        guard isLoggedIn else { return }  // ignore if already logged out
        authService.logout()
        isLoggedIn = false
        password = ""
        sessionExpired = true
    }

    func login() async {
        guard !username.isEmpty, !password.isEmpty else {
            errorMessage = "Kullanıcı adı ve şifre gereklidir."
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            _ = try await authService.login(username: username, password: password)
            isLoggedIn = true
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func logout() {
        authService.logout()
        isLoggedIn = false
        username = ""
        password = ""
    }
}
