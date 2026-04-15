import Foundation

@Observable
final class CourseListViewModel {
    var courses: [Course] = []
    var progress: [Int: CourseProgress] = [:]
    var progressLoaded = false
    var isLoading = false
    var errorMessage: String?

    private let service = LearnDashService()

    func fetchCourses() async {
        isLoading = true
        errorMessage = nil
        progressLoaded = false

        do {
            var fetched = try await service.fetchCourses()
            courses = fetched
            fetched = await service.resolveMediaURLs(
                for: fetched,
                id: { $0.featuredMediaURL == nil ? $0.featuredMediaID : nil },
                apply: { $0.featuredMediaURL = $1 }
            )
            courses = fetched
            isLoading = false

            if let userId = AuthService.currentUserId {
                await withTaskGroup(of: (Int, CourseProgress?).self) { group in
                    for course in fetched {
                        group.addTask {
                            let p = await self.service.fetchCourseProgress(userId: userId, courseId: course.id)
                            return (course.id, p)
                        }
                    }
                    for await (id, p) in group {
                        if let p { progress[id] = p }
                    }
                }
            }
            progressLoaded = true
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
}
