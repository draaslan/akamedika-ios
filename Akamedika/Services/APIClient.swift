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

    let baseURL = "https://afb3-176-89-232-107.ngrok-free.app/wp-json"

    /// The public origin (scheme+host) used for serving media. WordPress returns
    /// URLs using its internal site URL (e.g. https://akamedika-new.test) which
    /// isn't reachable from the device; rewrite those to the ngrok origin.
    var publicOrigin: String {
        URL(string: baseURL).flatMap { url -> String? in
            guard let scheme = url.scheme, let host = url.host else { return nil }
            return "\(scheme)://\(host)"
        } ?? "https://afb3-176-89-232-107.ngrok-free.app"
    }

    /// Known WordPress internal hosts that should be rewritten to `publicOrigin`.
    private let internalHosts = ["akamedika-new.test", "akamedika.test", "localhost", "127.0.0.1"]

    func rewriteMediaURL(_ urlString: String?) -> String? {
        guard let urlString, !urlString.isEmpty else { return nil }
        guard let url = URL(string: urlString), let host = url.host else { return urlString }
        if internalHosts.contains(where: { host.lowercased().contains($0) }) {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let origin = URL(string: publicOrigin)
            components?.scheme = origin?.scheme
            components?.host = origin?.host
            components?.port = origin?.port
            return components?.url?.absoluteString ?? urlString
        }
        return urlString
    }
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

    func requestRaw(_ endpoint: String, method: String = "GET", body: [String: Any]? = nil) async throws -> Data {
        guard let url = URL(string: baseURL + endpoint) else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
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
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        switch http.statusCode {
        case 200...299: return data
        case 401, 403: throw APIError.unauthorized
        default: throw APIError.serverError(http.statusCode)
        }
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
