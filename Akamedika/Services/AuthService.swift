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
        return user
    }

    func logout() {
        client.token = nil
    }
}
