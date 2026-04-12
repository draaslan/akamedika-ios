import Foundation

@Observable
final class LessonListViewModel {
    var lessons: [Lesson] = []
    var isLoading = false
    var errorMessage: String?

    private let service = LearnDashService()

    func fetchLessons(courseId: Int) async {
        isLoading = true
        errorMessage = nil

        do {
            lessons = try await service.fetchLessons(courseId: courseId)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}
