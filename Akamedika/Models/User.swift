import Foundation

struct User: Codable {
    let token: String
    let userEmail: String
    let userNicename: String
    let userDisplayName: String

    enum CodingKeys: String, CodingKey {
        case token
        case userEmail = "user_email"
        case userNicename = "user_nicename"
        case userDisplayName = "user_display_name"
    }
}

struct WPUser: Codable {
    let id: Int
    let name: String?
    let slug: String?
    let description: String?
    let url: String?
    let link: String?
    let avatarUrls: [String: String]?
    let roles: [String]?

    enum CodingKeys: String, CodingKey {
        case id, name, slug, description, url, link, roles
        case avatarUrls = "avatar_urls"
    }

    var bestAvatarURL: String? {
        guard let avatarUrls else { return nil }
        let raw = avatarUrls["96"] ?? avatarUrls["48"] ?? avatarUrls["24"] ?? avatarUrls.first?.value
        return APIClient.shared.rewriteMediaURL(raw)
    }
}
