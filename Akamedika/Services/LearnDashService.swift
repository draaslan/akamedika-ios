import Foundation

struct LearnDashService {
    private let client = APIClient.shared

    func fetchCourses() async throws -> [Course] {
        try await client.request("/ldlms/v2/sfwd-courses?per_page=100")
    }

    func fetchLessons(courseId: Int) async throws -> [Lesson] {
        try await client.request("/ldlms/v2/sfwd-lessons?course=\(courseId)&per_page=100")
    }

    func fetchLesson(id: Int) async throws -> Lesson {
        try await client.request("/wp/v2/sfwd-lessons/\(id)")
    }
}
