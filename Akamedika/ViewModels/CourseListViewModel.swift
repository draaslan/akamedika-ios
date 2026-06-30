import Foundation

@Observable
final class CourseListViewModel {
    var courses: [Course] = []
    var progress: [Int: CourseProgress] = [:]
    /// IDs of the courses the signed-in user is enrolled in. Courses outside
    /// this set are shown as "not enrolled" and open in Safari for purchase.
    var enrolledCourseIDs: Set<Int> = []
    var progressLoaded = false
    var isLoading = false
    var errorMessage: String?

    private let service = LearnDashService()

    func isEnrolled(_ courseId: Int) -> Bool {
        enrolledCourseIDs.contains(courseId)
    }

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

            // Single batched request for every course's progress + enrollment.
            if let userId = AuthService.currentUserId {
                let result = await service.fetchAllCourseProgress(userId: userId)
                progress = result.progress
                enrolledCourseIDs = result.enrolledCourseIDs
                // Show enrolled courses first, then the rest (available to buy),
                // preserving the server order within each group.
                courses = stableSortedByEnrollment(courses)
            }
            progressLoaded = true
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    /// Stable partition: enrolled courses keep their relative order and come
    /// first; non-enrolled keep theirs and follow.
    private func stableSortedByEnrollment(_ list: [Course]) -> [Course] {
        let enrolled = list.filter { enrolledCourseIDs.contains($0.id) }
        let others = list.filter { !enrolledCourseIDs.contains($0.id) }
        return enrolled + others
    }
}
