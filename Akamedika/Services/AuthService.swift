import Foundation

struct AuthService {
    private let client = APIClient.shared

    func login(username: String, password: String) async throws -> User {
        let body: [String: Any] = [
            "username": username,
            "password": password
        ]

        let user: User = try await client.request(
            "/jwt-auth/v1/token",
            method: "POST",
            body: body
        )

        client.token = user.token
        Self.cache(user: user)
        await fetchAndCacheUserId()
        return user
    }

    @discardableResult
    func fetchAndCacheUserId() async -> Int? {
        if let wpUser: WPUser = try? await client.request("/wp/v2/users/me") {
            UserDefaults.standard.set(wpUser.id, forKey: "wp_user_id")
            return wpUser.id
        }
        return nil
    }

    func fetchMe() async throws -> WPUser {
        try await client.request("/wp/v2/users/me?context=edit")
    }

    static var currentUserId: Int? {
        let id = UserDefaults.standard.integer(forKey: "wp_user_id")
        return id > 0 ? id : nil
    }

    static func cache(user: User) {
        let defaults = UserDefaults.standard
        defaults.set(user.userEmail, forKey: "wp_user_email")
        defaults.set(user.userNicename, forKey: "wp_user_nicename")
        defaults.set(user.userDisplayName, forKey: "wp_user_display_name")
    }

    static var cachedDisplayName: String? {
        UserDefaults.standard.string(forKey: "wp_user_display_name")
    }

    static var cachedEmail: String? {
        UserDefaults.standard.string(forKey: "wp_user_email")
    }

    static var cachedNicename: String? {
        UserDefaults.standard.string(forKey: "wp_user_nicename")
    }

    func logout() {
        client.token = nil
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "wp_user_id")
        defaults.removeObject(forKey: "wp_user_email")
        defaults.removeObject(forKey: "wp_user_nicename")
        defaults.removeObject(forKey: "wp_user_display_name")
    }
}
