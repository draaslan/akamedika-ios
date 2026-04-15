import Foundation

struct Topic: Codable, Identifiable, Hashable {
    let id: Int
    let title: RenderedContent
    let menuOrder: Int?
    let lesson: Int?
    let course: Int?

    enum CodingKeys: String, CodingKey {
        case id, title, lesson, course
        case menuOrder = "menu_order"
    }

    var displayTitle: String {
        title.rendered.htmlStripped
    }
}
