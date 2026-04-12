import Foundation

@Observable
final class CourseListViewModel {
    var courses: [Course] = []
    var isLoading = false
    var errorMessage: String?

    private let service = LearnDashService()

    func fetchCourses() async {
        isLoading = true
        errorMessage = nil

        do {
            courses = try await service.fetchCourses()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}
