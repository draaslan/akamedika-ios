import Foundation

enum APIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case unauthorized
    case serverError(Int)
    case decodingError(Error)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL: "Geçersiz URL"
        case .invalidResponse: "Geçersiz yanıt"
        case .unauthorized: "Oturum süresi doldu. Lütfen tekrar giriş yapın."
        case .serverError(let code): "Sunucu hatası: \(code)"
        case .decodingError(let error): "Veri işleme hatası: \(error.localizedDescription)"
        case .networkError(let error): "Bağlantı hatası: \(error.localizedDescription)"
        }
    }
}

@Observable
final class APIClient {
    static let shared = APIClient()

    let baseURL = "https://7a4c-176-89-232-107.ngrok-free.app/wp-json"
    var token: String? {
        didSet {
            if let token {
                UserDefaults.standard.set(token, forKey: "jwt_token")
            } else {
                UserDefaults.standard.removeObject(forKey: "jwt_token")
            }
        }
    }

    private init() {
        token = UserDefaults.standard.string(forKey: "jwt_token")
    }

    func request<T: Decodable>(_ endpoint: String, method: String = "GET", body: [String: Any]? = nil) async throws -> T {
        guard let url = URL(string: baseURL + endpoint) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method

        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw APIError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
            do {
                return try JSONDecoder().decode(T.self, from: data)
            } catch {
                throw APIError.decodingError(error)
            }
        case 401, 403:
            throw APIError.unauthorized
        default:
            throw APIError.serverError(httpResponse.statusCode)
        }
    }
}
