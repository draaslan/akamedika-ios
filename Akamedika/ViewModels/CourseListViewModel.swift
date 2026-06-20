import Foundation

@Observable
final class CourseListViewModel {
    var courses: [Course] = []
    var progress: [Int: CourseProgress] = [:]
    var progressLoaded = false
    var isLoading = false
    var errorMessage: String?

    private let service = LearnDashService()

    /// Reflects a course's updated progress (e.g. after completing a lesson deep
    /// in the stack) so the course card updates on return — no refetch needed.
    func updateCourseProgress(courseId: Int, progress newProgress: CourseProgress) {
        progress[courseId] = newProgress
    }

    /// Loads courses + progress. Skips the network entirely if data is already
    /// loaded so re-entering the screen doesn't refetch; pass `force: true`
    /// (pull-to-refresh / retry) to reload.
    func fetchCourses(force: Bool = false) async {
        if !force && !courses.isEmpty && progressLoaded { return }

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

            // Single batched request for every course's progress.
            if let userId = AuthService.currentUserId {
                progress = await service.fetchAllCourseProgress(userId: userId)
            }
            progressLoaded = true
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
}
