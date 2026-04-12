import Foundation

@Observable
final class AuthViewModel {
    var isLoggedIn = false
    var isLoading = false
    var errorMessage: String?
    var username = ""
    var password = ""

    private let authService = AuthService()

    init() {
        isLoggedIn = APIClient.shared.token != nil
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
