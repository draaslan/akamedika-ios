import Foundation

struct Course: Codable, Identifiable, Hashable {
    let id: Int
    let title: RenderedContent
    let featuredMediaURL: String?
    let status: String

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case featuredMediaURL = "featured_media_url"
        case status
    }

    var displayTitle: String {
        title.rendered.htmlStripped
    }
}

struct RenderedContent: Codable, Hashable {
    let rendered: String
}

extension String {
    var htmlStripped: String {
        self.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#039;", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
