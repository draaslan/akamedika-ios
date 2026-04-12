import Foundation

struct Lesson: Codable, Identifiable, Hashable {
    let id: Int
    let title: RenderedContent
    let content: RenderedContent?
    let status: String

    var displayTitle: String {
        title.rendered.htmlStripped
    }

    var htmlContent: String {
        content?.rendered ?? ""
    }
}
