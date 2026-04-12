import Foundation

@Observable
final class LessonDetailViewModel {
    var lesson: Lesson?
    var isLoading = false
    var errorMessage: String?

    private let service = LearnDashService()

    func fetchLesson(id: Int) async {
        isLoading = true
        errorMessage = nil

        do {
            lesson = try await service.fetchLesson(id: id)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}
