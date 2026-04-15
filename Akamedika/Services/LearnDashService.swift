import Foundation

struct DynamicKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

/// LearnDash's course-steps endpoint response varies by version:
/// - Flat array of IDs: [123, 456]
/// - Array of objects: [{"id":123,"type":"l"}, ...]
/// - Dict with nested hierarchy: {"123": [], "456": {...}}
/// - Wrapper: {"l": [...]} or {"sfwd-lessons": [...]}
/// This tolerates all of them.
struct CourseStepIDs: Decodable {
    let orderedIDs: [Int]

    struct Item: Decodable {
        let id: Int?
        let ID: Int?
        let step: Int?
        var resolvedID: Int? { id ?? ID ?? step }
    }

    init(from decoder: Decoder) throws {
        // Flat array of ints
        if let arr = try? decoder.singleValueContainer().decode([Int].self) {
            orderedIDs = arr
            return
        }
        // Array of ID strings
        if let arr = try? decoder.singleValueContainer().decode([String].self) {
            orderedIDs = arr.compactMap { Int($0) }
            return
        }
        // Array of objects {id|ID|step}
        if let items = try? decoder.singleValueContainer().decode([Item].self) {
            orderedIDs = items.compactMap { $0.resolvedID }
            return
        }
        // Dict shape — collect IDs recursively
        var collected: [Int] = []
        if let container = try? decoder.container(keyedBy: DynamicKey.self) {
            Self.collect(container, into: &collected)
        }
        orderedIDs = collected
    }

    private static func collect(_ c: KeyedDecodingContainer<DynamicKey>, into collected: inout [Int]) {
        for key in c.allKeys {
            // Numeric key means the key IS the ID (hierarchy shape)
            if let id = Int(key.stringValue) {
                collected.append(id)
                if let nested = try? c.nestedContainer(keyedBy: DynamicKey.self, forKey: key) {
                    Self.collect(nested, into: &collected)
                }
                continue
            }
            // Array of ints under key (e.g. "l": [...])
            if let arr = try? c.decode([Int].self, forKey: key) {
                collected.append(contentsOf: arr)
                continue
            }
            // Array of objects under key
            if let items = try? c.decode([Item].self, forKey: key) {
                collected.append(contentsOf: items.compactMap { $0.resolvedID })
                continue
            }
            // Nested dict
            if let nested = try? c.nestedContainer(keyedBy: DynamicKey.self, forKey: key) {
                Self.collect(nested, into: &collected)
            }
        }
    }
}

/// Response shape for /ldlms/v2/users/{id}/course-progress/{course}/steps
struct ProgressStep: Decodable {
    let step: Int?
    let postType: String?
    let stepStatus: String?
    let dateCompletedGMT: String?

    enum CodingKeys: String, CodingKey {
        case step
        case postType = "post_type"
        case stepStatus = "step_status"
        case dateCompletedGMT = "date_completed_gmt"
    }

    var isCompleted: Bool {
        stepStatus?.lowercased() == "completed"
    }

    var isLesson: Bool {
        postType == "sfwd-lessons"
    }
}

/// Tolerates the several shapes LearnDash returns for course-progress endpoints.
/// Extracts completed lesson IDs and totals from any of the known layouts.
struct CourseProgressResponse: Decodable {
    let completedLessonIDs: Set<Int>
    let completed: Int?
    let total: Int?

    init(from decoder: Decoder) throws {
        var ids = Set<Int>()
        var done: Int?
        var total: Int?

        // Walk top level
        let root = try decoder.container(keyedBy: DynamicKey.self)
        Self.scan(root, completed: &done, total: &total, ids: &ids)

        // Some shapes nest under "course_progress"
        if let nestedKey = DynamicKey(stringValue: "course_progress"),
           let nested = try? root.nestedContainer(keyedBy: DynamicKey.self, forKey: nestedKey) {
            Self.scan(nested, completed: &done, total: &total, ids: &ids)
        }

        self.completedLessonIDs = ids
        self.completed = done
        self.total = total
    }

    private static func scan(
        _ c: KeyedDecodingContainer<DynamicKey>,
        completed: inout Int?,
        total: inout Int?,
        ids: inout Set<Int>
    ) {
        for key in c.allKeys {
            switch key.stringValue {
            case "completed_steps":
                if let arr = try? c.decode([Int].self, forKey: key) { ids.formUnion(arr) }
            case "steps_completed", "completed":
                if completed == nil { completed = try? c.decode(Int.self, forKey: key) }
            case "steps_total", "total":
                if total == nil { total = try? c.decode(Int.self, forKey: key) }
            case "steps", "lessons":
                // Dict form: { "lesson:123": 1, "topic:456": 0 } or { "123": 1 }
                if let dict = try? c.decode([String: Int].self, forKey: key) {
                    for (k, v) in dict where v > 0 {
                        let part = k.split(separator: ":").last.map(String.init) ?? k
                        if let id = Int(part) { ids.insert(id) }
                    }
                }
                // Array of objects with id + completed/status
                if let arr = try? c.decode([StepItem].self, forKey: key) {
                    for item in arr where item.isCompleted {
                        if let id = item.id { ids.insert(id) }
                    }
                }
            default:
                break
            }
        }
    }

    struct StepItem: Decodable {
        let id: Int?
        let completed: Bool?
        let status: String?

        var isCompleted: Bool {
            completed == true || status?.lowercased() == "completed"
        }
    }
}

struct MediaItem: Decodable {
    let id: Int
    let sourceURL: String?
    enum CodingKeys: String, CodingKey {
        case id
        case sourceURL = "source_url"
    }
}

actor MediaCache {
    static let shared = MediaCache()
    private var cache: [Int: String] = [:]

    func get(_ id: Int) -> String? { cache[id] }
    func set(_ id: Int, url: String) { cache[id] = url }
}

struct LearnDashService {
    private let client = APIClient.shared

    func fetchMediaURL(id: Int) async -> String? {
        if let cached = await MediaCache.shared.get(id) { return cached }
        if let media: MediaItem = try? await client.request("/wp/v2/media/\(id)"),
           let rewritten = client.rewriteMediaURL(media.sourceURL) {
            await MediaCache.shared.set(id, url: rewritten)
            return rewritten
        }
        return nil
    }

    func resolveMediaURLs<T>(for items: [T], id: (T) -> Int?, apply: (inout T, String) -> Void) async -> [T] {
        var result = items
        await withTaskGroup(of: (Int, String?).self) { group in
            for (idx, item) in items.enumerated() {
                guard let mediaID = id(item), mediaID > 0 else { continue }
                group.addTask {
                    let url = await self.fetchMediaURL(id: mediaID)
                    return (idx, url)
                }
            }
            for await (idx, url) in group {
                if let url { apply(&result[idx], url) }
            }
        }
        return result
    }

    func fetchCourses() async throws -> [Course] {
        try await client.request("/wp/v2/sfwd-courses?per_page=100&_embed=wp:featuredmedia")
    }

    func fetchCourse(id: Int) async throws -> Course {
        try await client.request("/wp/v2/sfwd-courses/\(id)?_embed=wp:featuredmedia")
    }

    /// Parsed course outline: lesson order + topics per lesson, insertion order preserved.
    struct CourseOutline {
        var lessonIDs: [Int] = []
        var topicsByLesson: [Int: [Int]] = [:]
        var completedIDs: Set<Int> = []
    }

    /// Builds the course outline by combining two authoritative sources:
    ///   1. `/ldlms/v2/sfwd-courses/{id}/steps?type=l` — the canonical SET of
    ///      lesson IDs for this course (used for classification).
    ///   2. `/ldlms/v2/users/{uid}/course-progress/{id}/steps` — flat ordered
    ///      array of every step with completion; gives us order, topics, and
    ///      completion in one shot.
    ///
    /// We distinguish lessons from topics by checking whether the step's ID is
    /// in the known-lesson set, rather than relying on post_type strings which
    /// vary across LearnDash versions.
    func fetchCourseOutline(courseId: Int, userId: Int?) async -> CourseOutline {
        // Step 1: canonical lesson ID set (no auth context needed beyond enrollment)
        async let lessonIDsTask = fetchPlainLessonIDs(courseId: courseId)

        // Step 2: progress steps for the authed user (paginated, max 100 per page)
        async let progressStepsTask: [ProgressStep] = {
            guard let userId else { return [] }
            return await fetchAllProgressSteps(userId: userId, courseId: courseId)
        }()

        let knownLessonIDs = await lessonIDsTask
        let progressSteps = await progressStepsTask

        if !progressSteps.isEmpty {
            return buildOutline(fromProgressSteps: progressSteps, knownLessons: Set(knownLessonIDs))
        }

        // Fallback 1: hierarchy dict (NSDictionary preserves JSON order)
        let hierarchyEndpoints = [
            "/ldlms/v2/sfwd-courses/\(courseId)/steps",
            "/ldlms/v2/sfwd-courses/\(courseId)/steps?type=h"
        ]
        for endpoint in hierarchyEndpoints {
            guard let data = try? await client.requestRaw(endpoint) else { continue }
            guard let json = try? JSONSerialization.jsonObject(with: data, options: []) else { continue }
            var outline = Self.parseOutline(json)
            // If hierarchy parsing failed to pick up lessons but we have type=l, seed with it
            if outline.lessonIDs.isEmpty, !knownLessonIDs.isEmpty {
                outline.lessonIDs = knownLessonIDs
            }
            if !outline.lessonIDs.isEmpty { return outline }
        }

        // Fallback 2: flat lesson list only (no topics, no completion)
        if !knownLessonIDs.isEmpty {
            return CourseOutline(lessonIDs: knownLessonIDs)
        }
        return CourseOutline()
    }

    private func fetchPlainLessonIDs(courseId: Int) async -> [Int] {
        let endpoint = "/ldlms/v2/sfwd-courses/\(courseId)/steps?type=l&per_page=100"
        if let ids: [Int] = try? await client.request(endpoint) {
            var seen = Set<Int>()
            return ids.filter { seen.insert($0).inserted }
        }
        // Some LD versions return [{id: N}] instead of [N]
        if let wrapped: CourseStepIDs = try? await client.request(endpoint) {
            var seen = Set<Int>()
            return wrapped.orderedIDs.filter { seen.insert($0).inserted }
        }
        return []
    }

    private func fetchAllProgressSteps(userId: Int, courseId: Int) async -> [ProgressStep] {
        var all: [ProgressStep] = []
        var page = 1
        let perPage = 100
        while page <= 20 {
            let endpoint = "/ldlms/v2/users/\(userId)/course-progress/\(courseId)/steps?per_page=\(perPage)&page=\(page)"
            guard let batch: [ProgressStep] = try? await client.request(endpoint), !batch.isEmpty else {
                break
            }
            all.append(contentsOf: batch)
            if batch.count < perPage { break }
            page += 1
        }
        return all
    }

    /// Walks the ordered progress-steps array. An item is a lesson iff its ID
    /// is in the known-lesson set; otherwise it's a topic that belongs to the
    /// most-recently-seen lesson. Completion comes from step_status.
    private func buildOutline(
        fromProgressSteps steps: [ProgressStep],
        knownLessons: Set<Int>
    ) -> CourseOutline {
        var outline = CourseOutline()
        var currentLesson: Int?

        for step in steps {
            guard let id = step.step else { continue }

            let isLesson: Bool = {
                if !knownLessons.isEmpty { return knownLessons.contains(id) }
                // No lesson set — fall back to post_type hint
                return step.postType?.contains("lesson") == true
            }()

            if step.isCompleted { outline.completedIDs.insert(id) }

            if isLesson {
                currentLesson = id
                if !outline.lessonIDs.contains(id) { outline.lessonIDs.append(id) }
                if outline.topicsByLesson[id] == nil { outline.topicsByLesson[id] = [] }
            } else {
                // Treat as topic (or quiz, which we currently fold under topics)
                guard let lesson = currentLesson else { continue }
                // Skip quizzes — only real topics belong in the accordion.
                let pt = step.postType?.lowercased() ?? ""
                if pt.contains("quiz") { continue }
                var arr = outline.topicsByLesson[lesson] ?? []
                if !arr.contains(id) { arr.append(id) }
                outline.topicsByLesson[lesson] = arr
            }
        }

        // Safety: ensure every known lesson appears, even if progress-steps missed it.
        for id in knownLessons where !outline.lessonIDs.contains(id) {
            outline.lessonIDs.append(id)
            outline.topicsByLesson[id] = outline.topicsByLesson[id] ?? []
        }
        return outline
    }

    /// Walks the mixed-shape hierarchy from LearnDash, extracting lesson IDs in order
    /// and the topic IDs that nest under each lesson.
    private static func parseOutline(_ json: Any) -> CourseOutline {
        var outline = CourseOutline()
        walk(json, currentLesson: nil, expectedType: .lesson, outline: &outline)
        return outline
    }

    /// `expectedType` carries the wrapper context downward so that bare numeric
    /// keys (which are how LearnDash represents IDs in nested hierarchies, e.g.
    /// `"sfwd-topic": { "22374": {...} }`) get classified correctly. Without
    /// this, every numeric key would be treated as a lesson and topics would
    /// silently land in `lessonIDs`.
    private static func walk(_ node: Any, currentLesson: Int?, expectedType: NodeType, outline: inout CourseOutline) {
        if let nsDict = node as? NSDictionary {
            // NSDictionary preserves JSON insertion order via allKeys.
            for rawKey in nsDict.allKeys {
                let key = "\(rawKey)"
                let value = nsDict[rawKey] ?? NSNull()
                handleEntry(key: key, value: value, currentLesson: currentLesson, expectedType: expectedType, outline: &outline)
            }
            return
        }
        if let dict = node as? [String: Any] {
            for (key, value) in dict {
                handleEntry(key: key, value: value, currentLesson: currentLesson, expectedType: expectedType, outline: &outline)
            }
            return
        }
        if let arr = node as? [Any] {
            for el in arr {
                if let dict = el as? [String: Any] {
                    let typeStr = ((dict["type"] as? String) ?? (dict["post_type"] as? String) ?? "").lowercased()
                    let id = (dict["id"] as? Int) ?? (dict["ID"] as? Int) ?? (dict["step"] as? Int)
                    let nodeType: NodeType = typeStr.contains("topic") ? .topic
                        : (typeStr.contains("lesson") ? .lesson : expectedType)
                    if nodeType == .lesson, let id {
                        addID(id, type: .lesson, currentLesson: currentLesson, outline: &outline)
                        walk(dict, currentLesson: id, expectedType: .lesson, outline: &outline)
                    } else if nodeType == .topic, let id {
                        addID(id, type: .topic, currentLesson: currentLesson, outline: &outline)
                    } else {
                        walk(dict, currentLesson: currentLesson, expectedType: expectedType, outline: &outline)
                    }
                } else if let id = el as? Int {
                    addID(id, type: expectedType, currentLesson: currentLesson, outline: &outline)
                }
            }
        }
    }

    private static func handleEntry(key: String, value: Any, currentLesson: Int?, expectedType: NodeType, outline: inout CourseOutline) {
        let lower = key.lowercased()
        // Wrapper keys: change the expected type for descendant numeric keys.
        if lower == "sfwd-lessons" || lower == "lessons" || lower == "l" {
            walk(value, currentLesson: currentLesson, expectedType: .lesson, outline: &outline)
            return
        }
        if lower == "sfwd-topic" || lower == "sfwd-topics" || lower == "topics" || lower == "topic" || lower == "t" {
            walk(value, currentLesson: currentLesson, expectedType: .topic, outline: &outline)
            return
        }
        if lower == "sfwd-quiz" || lower == "quiz" || lower == "quizzes" || lower == "q" {
            return  // skip quizzes
        }
        if lower == "h" || lower == "steps" {
            walk(value, currentLesson: currentLesson, expectedType: expectedType, outline: &outline)
            return
        }
        // Prefixed forms ("lesson:NN" / "topic:NN")
        if lower.hasPrefix("lesson:") {
            if let id = Int(key.split(separator: ":").last ?? "") {
                addID(id, type: .lesson, currentLesson: currentLesson, outline: &outline)
                walk(value, currentLesson: id, expectedType: .lesson, outline: &outline)
            }
            return
        }
        if lower.hasPrefix("topic:") {
            if let id = Int(key.split(separator: ":").last ?? "") {
                addID(id, type: .topic, currentLesson: currentLesson, outline: &outline)
            }
            return
        }
        // Numeric key — classify by the wrapper context.
        if let id = Int(key) {
            addID(id, type: expectedType, currentLesson: currentLesson, outline: &outline)
            let nextLesson = expectedType == .lesson ? id : currentLesson
            walk(value, currentLesson: nextLesson, expectedType: expectedType, outline: &outline)
            return
        }
        walk(value, currentLesson: currentLesson, expectedType: expectedType, outline: &outline)
    }

    private static func addID(_ id: Int, type: NodeType, currentLesson: Int?, outline: inout CourseOutline) {
        switch type {
        case .lesson:
            if !outline.lessonIDs.contains(id) { outline.lessonIDs.append(id) }
            if outline.topicsByLesson[id] == nil { outline.topicsByLesson[id] = [] }
        case .topic:
            guard let lesson = currentLesson else { return }
            var arr = outline.topicsByLesson[lesson] ?? []
            if !arr.contains(id) { arr.append(id) }
            outline.topicsByLesson[lesson] = arr
        case .container:
            break
        }
    }

    private enum NodeType { case lesson, topic, container }

    /// Fetches lessons (and topics) for a course, preserving LearnDash order.
    /// Merges completion from both outline walk and summary endpoint for safety.
    func fetchCourseContent(courseId: Int) async throws -> (lessons: [Lesson], topics: [Int: [Topic]], completed: Set<Int>) {
        let userId = AuthService.currentUserId
        let outline = await fetchCourseOutline(courseId: courseId, userId: userId)
        let lessonIDs = outline.lessonIDs
        let allTopicIDs = Array(Set(outline.topicsByLesson.values.flatMap { $0 }))

        async let lessonsTask: [Lesson] = fetchLessonsByIDs(lessonIDs, courseId: courseId)
        async let topicsTask: [Int: Topic] = fetchTopicsByIDs(allTopicIDs)
        async let summaryCompletedTask: Set<Int> = {
            guard let userId else { return [] }
            return await fetchProgressResponse(userId: userId, courseId: courseId)?.completedLessonIDs ?? []
        }()

        let lessons = try await lessonsTask
        let topicsByID = await topicsTask
        let summaryCompleted = await summaryCompletedTask

        var topicsByLesson: [Int: [Topic]] = [:]
        for (lessonID, tIDs) in outline.topicsByLesson {
            let ordered = tIDs.compactMap { topicsByID[$0] }
            if !ordered.isEmpty { topicsByLesson[lessonID] = ordered }
        }
        let completed = outline.completedIDs.union(summaryCompleted)
        return (lessons, topicsByLesson, completed)
    }

    private func fetchLessonsByIDs(_ ids: [Int], courseId: Int) async throws -> [Lesson] {
        if !ids.isEmpty {
            let includeParam = ids.map(String.init).joined(separator: ",")
            let endpoint = "/wp/v2/sfwd-lessons?include=\(includeParam)&per_page=\(ids.count)&orderby=include&_embed=wp:featuredmedia"
            if let batch: [Lesson] = try? await client.request(endpoint), !batch.isEmpty {
                let indexOf: [Int: Int] = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, $0) })
                return batch.sorted { (indexOf[$0.id] ?? 0) < (indexOf[$1.id] ?? 0) }
            }
        }

        // Fallback: ldlms endpoint returns `course` field on each lesson — filter client-side.
        let all: [Lesson] = (try? await client.request(
            "/ldlms/v2/sfwd-lessons?per_page=100&orderby=menu_order&order=asc"
        )) ?? []
        let filtered = all.filter { $0.course == courseId }
        if !filtered.isEmpty { return filtered.sorted { ($0.menuOrder ?? 0) < ($1.menuOrder ?? 0) } }

        let wpLessons: [Lesson] = try await client.request(
            "/wp/v2/sfwd-lessons?course=\(courseId)&per_page=100&orderby=menu_order&order=asc&_embed=wp:featuredmedia"
        )
        return wpLessons
            .filter { $0.course == nil || $0.course == courseId }
            .sorted { ($0.menuOrder ?? 0) < ($1.menuOrder ?? 0) }
    }

    private func fetchTopicsByIDs(_ ids: [Int]) async -> [Int: Topic] {
        guard !ids.isEmpty else { return [:] }
        let includeParam = ids.map(String.init).joined(separator: ",")
        let endpoints = [
            "/wp/v2/sfwd-topic?include=\(includeParam)&per_page=\(ids.count)&orderby=include",
            "/ldlms/v2/sfwd-topic?include=\(includeParam)&per_page=\(ids.count)"
        ]
        for endpoint in endpoints {
            if let topics: [Topic] = try? await client.request(endpoint), !topics.isEmpty {
                return Dictionary(uniqueKeysWithValues: topics.map { ($0.id, $0) })
            }
        }
        return [:]
    }

    func fetchLessons(courseId: Int) async throws -> [Lesson] {
        try await fetchCourseContent(courseId: courseId).lessons
    }

    func fetchLesson(id: Int) async throws -> Lesson {
        try await client.request("/wp/v2/sfwd-lessons/\(id)?_embed=wp:featuredmedia")
    }

    /// Fetches the raw course-progress payload once and returns decoded struct.
    private func fetchProgressResponse(userId: Int, courseId: Int) async -> CourseProgressResponse? {
        let endpoints = [
            "/ldlms/v2/users/\(userId)/course-progress/\(courseId)",
            "/ldlms/v2/users/\(userId)/courses/\(courseId)/steps"
        ]
        for endpoint in endpoints {
            if let r: CourseProgressResponse = try? await client.request(endpoint) {
                return r
            }
        }
        return nil
    }

    func fetchCompletedLessonIDs(userId: Int, courseId: Int) async -> Set<Int> {
        await fetchProgressResponse(userId: userId, courseId: courseId)?.completedLessonIDs ?? []
    }

    func fetchCourseProgress(userId: Int, courseId: Int) async -> CourseProgress? {
        guard let r = await fetchProgressResponse(userId: userId, courseId: courseId) else { return nil }
        if let c = r.completed, let t = r.total, t > 0 {
            return CourseProgress(completed: c, total: t)
        }
        return nil
    }

    /// Batch fetch: returns both progress totals and the exact set of completed
    /// lesson IDs. Uses the per-step progress endpoint which returns one object
    /// per step with status and post_type — the reliable source for completion.
    func fetchCourseDetail(userId: Int, courseId: Int) async -> (progress: CourseProgress?, completed: Set<Int>) {
        async let progressTask = fetchProgressResponse(userId: userId, courseId: courseId)
        async let stepsTask: [ProgressStep]? = try? client.request(
            "/ldlms/v2/users/\(userId)/course-progress/\(courseId)/steps?per_page=100"
        )

        let progressResponse = await progressTask
        let steps = await stepsTask ?? []

        var completed = Set<Int>()
        for step in steps where step.isLesson && step.isCompleted {
            if let id = step.step { completed.insert(id) }
        }
        // Fallback to any IDs the summary endpoint surfaced.
        if completed.isEmpty, let summaryIDs = progressResponse?.completedLessonIDs {
            completed = summaryIDs
        }

        let progress: CourseProgress? = {
            if let r = progressResponse, let c = r.completed, let t = r.total, t > 0 {
                return CourseProgress(completed: c, total: t)
            }
            return nil
        }()
        return (progress, completed)
    }

    func markLessonComplete(userId: Int, lessonId: Int) async throws {
        let _: EmptyResponse = try await client.request(
            "/ldlms/v2/users/\(userId)/lessons/\(lessonId)",
            method: "POST",
            body: ["status": "complete"]
        )
    }
}

struct EmptyResponse: Decodable {}
