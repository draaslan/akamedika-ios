import Foundation

/// A single navigable content item in course order — either a standalone lesson
/// (no topics) or a topic. Lessons that contain topics are accordion containers
/// and are not themselves navigable, so they are not represented here.
enum CourseItem: Hashable {
    case lesson(Lesson)
    case topic(Topic)

    var id: Int {
        switch self {
        case .lesson(let l): l.id
        case .topic(let t): t.id
        }
    }
}

/// Navigation value used to push a content item (and to move prev/next) by its
/// index within the view model's `orderedItems`.
struct ContentNav: Hashable { let index: Int }

@Observable
final class LessonListViewModel {
    var lessons: [Lesson] = []
    var topicsByLesson: [Int: [Topic]] = [:]
    var completedIDs: Set<Int> = []
    var courseProgress: CourseProgress?
    var orderedItems: [CourseItem] = []
    var isLoading = false
    var errorMessage: String?

    private let service = LearnDashService()

    var progress: CourseProgress {
        if let courseProgress { return courseProgress }
        let total = lessons.count + topicsByLesson.values.reduce(0) { $0 + $1.count }
        return CourseProgress(completed: completedIDs.count, total: total)
    }

    /// Index of an item (by lesson/topic id) within `orderedItems`.
    func navIndex(forID id: Int) -> Int? {
        orderedItems.firstIndex { $0.id == id }
    }

    /// Optimistically reflect a just-completed item so the list updates instantly
    /// without a full course refetch (the server is already updated).
    func markCompletedLocally(id: Int) {
        guard !completedIDs.contains(id) else { return }
        completedIDs.insert(id)
        if let p = courseProgress {
            courseProgress = CourseProgress(completed: min(p.completed + 1, p.total), total: p.total)
        }
    }

    /// Flattens lessons + topics into course order: a lesson with topics expands
    /// to its topics; a lesson without topics stands alone.
    private func rebuildOrderedItems() {
        orderedItems = lessons.flatMap { lesson -> [CourseItem] in
            let topics = topicsByLesson[lesson.id] ?? []
            return topics.isEmpty ? [.lesson(lesson)] : topics.map { .topic($0) }
        }
    }

    func fetchLessons(courseId: Int) async {
        isLoading = true
        errorMessage = nil

        do {
            let content = try await service.fetchCourseContent(courseId: courseId)
            lessons = content.lessons
            topicsByLesson = content.topics
            completedIDs = content.completed
            courseProgress = content.progress

            lessons = await service.resolveMediaURLs(
                for: lessons,
                id: { $0.featuredMediaURL == nil ? $0.featuredMediaID : nil },
                apply: { $0.featuredMediaURL = $1 }
            )
            rebuildOrderedItems()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}
