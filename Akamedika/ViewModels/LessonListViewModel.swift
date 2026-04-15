import Foundation

@Observable
final class LessonListViewModel {
    var lessons: [Lesson] = []
    var topicsByLesson: [Int: [Topic]] = [:]
    var completedIDs: Set<Int> = []
    var courseProgress: CourseProgress?
    var isLoading = false
    var errorMessage: String?

    private let service = LearnDashService()

    var progress: CourseProgress {
        if let courseProgress { return courseProgress }
        let total = lessons.count + topicsByLesson.values.reduce(0) { $0 + $1.count }
        return CourseProgress(completed: completedIDs.count, total: total)
    }

    func fetchLessons(courseId: Int) async {
        isLoading = true
        errorMessage = nil

        do {
            let content = try await service.fetchCourseContent(courseId: courseId)
            lessons = content.lessons
            topicsByLesson = content.topics
            completedIDs = content.completed

            if let userId = AuthService.currentUserId {
                if let p = await service.fetchCourseProgress(userId: userId, courseId: courseId) {
                    courseProgress = p
                }
            }

            lessons = await service.resolveMediaURLs(
                for: lessons,
                id: { $0.featuredMediaURL == nil ? $0.featuredMediaID : nil },
                apply: { $0.featuredMediaURL = $1 }
            )
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}
