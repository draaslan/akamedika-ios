import Foundation

struct Course: Codable, Identifiable, Hashable {
    let id: Int
    let title: RenderedContent
    let excerpt: RenderedContent?
    let content: RenderedContent?
    var featuredMediaURL: String?
    let featuredMediaID: Int?
    let status: String

    enum CodingKeys: String, CodingKey {
        case id, title, excerpt, content, status
        case featuredMediaURL = "featured_media_url"
        case featuredMedia = "featured_media"
        case embedded = "_embedded"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        title = try c.decode(RenderedContent.self, forKey: .title)
        excerpt = try c.decodeIfPresent(RenderedContent.self, forKey: .excerpt)
        content = try c.decodeIfPresent(RenderedContent.self, forKey: .content)
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? "publish"
        featuredMediaID = try c.decodeIfPresent(Int.self, forKey: .featuredMedia)
        featuredMediaURL = Self.resolveFeaturedMediaURL(from: c)
    }

    init(id: Int, title: RenderedContent, excerpt: RenderedContent? = nil, content: RenderedContent? = nil, featuredMediaURL: String? = nil, featuredMediaID: Int? = nil, status: String = "publish") {
        self.id = id
        self.title = title
        self.excerpt = excerpt
        self.content = content
        self.featuredMediaURL = featuredMediaURL
        self.featuredMediaID = featuredMediaID
        self.status = status
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(excerpt, forKey: .excerpt)
        try c.encodeIfPresent(content, forKey: .content)
        try c.encodeIfPresent(featuredMediaURL, forKey: .featuredMediaURL)
        try c.encodeIfPresent(featuredMediaID, forKey: .featuredMedia)
        try c.encode(status, forKey: .status)
    }

    static func resolveFeaturedMediaURL<K: CodingKey>(from container: KeyedDecodingContainer<K>) -> String? {
        var raw: String?
        if let key = K(stringValue: "featured_media_url"),
           let url = (try? container.decodeIfPresent(String.self, forKey: key)) ?? nil,
           !url.isEmpty {
            raw = url
        }
        if raw == nil, let key = K(stringValue: "_embedded"),
           let embedded = try? container.decodeIfPresent(Embedded.self, forKey: key),
           let url = embedded.featuredMediaSourceURL {
            raw = url
        }
        return APIClient.shared.rewriteMediaURL(raw)
    }

    var displayTitle: String {
        title.rendered.htmlStripped
    }

    var displayExcerpt: String {
        (excerpt?.rendered ?? "").htmlStripped
    }
}

struct RenderedContent: Codable, Hashable {
    let rendered: String
}

struct CourseProgress: Codable, Hashable {
    let completed: Int
    let total: Int

    var fraction: Double {
        total > 0 ? Double(completed) / Double(total) : 0
    }

    var percent: Int {
        Int((fraction * 100).rounded())
    }
}

struct Embedded: Decodable {
    let featuredMedia: [EmbeddedMedia]?

    enum CodingKeys: String, CodingKey {
        case featuredMedia = "wp:featuredmedia"
    }

    var featuredMediaSourceURL: String? {
        featuredMedia?.compactMap { $0.sourceURL }.first
    }
}

struct EmbeddedMedia: Decodable {
    let sourceURL: String?
    let mediaDetails: MediaDetails?

    enum CodingKeys: String, CodingKey {
        case sourceURL = "source_url"
        case mediaDetails = "media_details"
    }
}

struct MediaDetails: Decodable {
    let sizes: [String: MediaSize]?
}

struct MediaSize: Decodable {
    let sourceURL: String?
    enum CodingKeys: String, CodingKey { case sourceURL = "source_url" }
}

extension String {
    var htmlStripped: String {
        var s = self.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        s = Self.decodeNumericEntities(s)
        let namedEntities: [(String, String)] = [
            ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""),
            ("&apos;", "'"), ("&nbsp;", " "), ("&ndash;", "–"), ("&mdash;", "—"),
            ("&hellip;", "…"), ("&laquo;", "«"), ("&raquo;", "»"),
            ("&ldquo;", "\u{201C}"), ("&rdquo;", "\u{201D}"),
            ("&lsquo;", "\u{2018}"), ("&rsquo;", "\u{2019}"),
            ("&bull;", "•"), ("&middot;", "·"), ("&copy;", "©"), ("&reg;", "®"),
            ("&trade;", "™"), ("&deg;", "°")
        ]
        for (k, v) in namedEntities {
            s = s.replacingOccurrences(of: k, with: v)
        }
        s = s.replacingOccurrences(of: "[…]", with: "…")
        s = s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decodeNumericEntities(_ input: String) -> String {
        guard input.contains("&#") else { return input }
        let pattern = "&#(x?)([0-9a-fA-F]+);"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return input }
        let ns = input as NSString
        let matches = regex.matches(in: input, range: NSRange(location: 0, length: ns.length))
        var result = input
        for match in matches.reversed() {
            let isHex = ns.substring(with: match.range(at: 1)) == "x"
            let numberString = ns.substring(with: match.range(at: 2))
            guard let code = UInt32(numberString, radix: isHex ? 16 : 10),
                  let scalar = Unicode.Scalar(code) else { continue }
            let replacement = String(Character(scalar))
            let fullRange = Range(match.range, in: result)!
            result.replaceSubrange(fullRange, with: replacement)
        }
        return result
    }
}
