import Foundation

struct Lesson: Codable, Identifiable, Hashable {
    let id: Int
    let title: RenderedContent
    let content: RenderedContent?
    let excerpt: RenderedContent?
    var featuredMediaURL: String?
    let featuredMediaID: Int?
    let status: String
    let menuOrder: Int?
    let course: Int?

    enum CodingKeys: String, CodingKey {
        case id, title, content, excerpt, status, course
        case featuredMediaURL = "featured_media_url"
        case featuredMedia = "featured_media"
        case menuOrder = "menu_order"
        case embedded = "_embedded"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        title = try c.decode(RenderedContent.self, forKey: .title)
        content = try c.decodeIfPresent(RenderedContent.self, forKey: .content)
        excerpt = try c.decodeIfPresent(RenderedContent.self, forKey: .excerpt)
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? "publish"
        menuOrder = try c.decodeIfPresent(Int.self, forKey: .menuOrder)
        course = try c.decodeIfPresent(Int.self, forKey: .course)
        featuredMediaID = try c.decodeIfPresent(Int.self, forKey: .featuredMedia)
        featuredMediaURL = Course.resolveFeaturedMediaURL(from: c)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(content, forKey: .content)
        try c.encodeIfPresent(excerpt, forKey: .excerpt)
        try c.encodeIfPresent(featuredMediaURL, forKey: .featuredMediaURL)
        try c.encodeIfPresent(featuredMediaID, forKey: .featuredMedia)
        try c.encode(status, forKey: .status)
        try c.encodeIfPresent(menuOrder, forKey: .menuOrder)
        try c.encodeIfPresent(course, forKey: .course)
    }

    var displayTitle: String {
        title.rendered.htmlStripped
    }

    var displayExcerpt: String {
        (excerpt?.rendered ?? "").htmlStripped
    }

    var htmlContent: String {
        content?.rendered ?? ""
    }
}
