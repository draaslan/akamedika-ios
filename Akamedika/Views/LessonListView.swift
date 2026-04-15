import SwiftUI

struct LessonListView: View {
    let course: Course
    @State private var viewModel = LessonListViewModel()

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            Group {
                if viewModel.isLoading && viewModel.lessons.isEmpty {
                    ScrollView {
                        VStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Theme.surfaceElevated)
                                .frame(height: 160)
                                .padding(.horizontal, 16)
                                .padding(.top, 8)
                                .shimmering()
                            ForEach(0..<6, id: \.self) { _ in
                                SkeletonLessonRow()
                                    .padding(.horizontal, 16)
                            }
                        }
                    }
                    .disabled(true)
                } else if let error = viewModel.errorMessage, viewModel.lessons.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(.orange)
                        Text(error)
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 30)
                        Button("Tekrar Dene") {
                            Task { await viewModel.fetchLessons(courseId: course.id) }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else if viewModel.lessons.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 50))
                            .foregroundStyle(Theme.textSecondary.opacity(0.6))
                        Text("Bu kursta henüz ders bulunmamaktadır.")
                            .foregroundStyle(Theme.textSecondary)
                    }
                } else {
                    lessonList
                }
            }
        }
        .navigationTitle(course.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .navigationDestination(for: Lesson.self) { lesson in
            LessonDetailView(lesson: lesson, isCompleted: viewModel.completedIDs.contains(lesson.id)) {
                await viewModel.fetchLessons(courseId: course.id)
            }
        }
        .navigationDestination(for: TopicDestination.self) { dest in
            TopicDetailView(
                topic: dest.topic,
                isCompleted: viewModel.completedIDs.contains(dest.topic.id)
            ) {
                await viewModel.fetchLessons(courseId: course.id)
            }
        }
        .task {
            await viewModel.fetchLessons(courseId: course.id)
        }
    }

    private var lessonList: some View {
        ScrollView {
            VStack(spacing: 16) {
                courseHeader
                    .padding(.horizontal, 16)
                    .padding(.top, 4)

                LazyVStack(spacing: 10) {
                    ForEach(Array(viewModel.lessons.enumerated()), id: \.element.id) { index, lesson in
                        LessonAccordion(
                            index: index + 1,
                            lesson: lesson,
                            topics: viewModel.topicsByLesson[lesson.id] ?? [],
                            completedIDs: viewModel.completedIDs
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
        }
        .refreshable {
            await viewModel.fetchLessons(courseId: course.id)
        }
    }

    private var courseHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let urlString = course.featuredMediaURL, !urlString.isEmpty {
                HStack {
                    Spacer()
                    SquareThumbnail {
                        FillingAsyncImage(url: URL(string: urlString)) {
                            ZStack {
                                Theme.accentGradient.opacity(0.35)
                                Image(systemName: "book.closed.fill")
                                    .font(.system(size: 46))
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                        }
                    }
                    .frame(maxWidth: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    Spacer()
                }
            }

            Text("\(viewModel.lessons.count) Ders")
                .font(.subheadline.bold())
                .foregroundStyle(Theme.textSecondary)

            if viewModel.progress.total > 0 {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Kurs İlerlemesi")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                        Spacer()
                        Text("%\(viewModel.progress.percent) tamamlandı")
                            .font(.caption.bold())
                            .foregroundStyle(Theme.accent)
                    }
                    ProgressBar(fraction: viewModel.progress.fraction)
                }
                .padding(14)
                .card()
            }
        }
    }
}

struct LessonAccordion: View {
    let index: Int
    let lesson: Lesson
    let topics: [Topic]
    let completedIDs: Set<Int>

    @State private var isExpanded = false

    var isCompleted: Bool { completedIDs.contains(lesson.id) }
    var hasTopics: Bool { !topics.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            headerButton
            if isExpanded && hasTopics {
                VStack(spacing: 0) {
                    Divider().background(Theme.border)
                    ForEach(Array(topics.enumerated()), id: \.element.id) { tIdx, topic in
                        NavigationLink(value: TopicDestination(topic: topic)) {
                            TopicRow(
                                index: tIdx + 1,
                                topic: topic,
                                isCompleted: completedIDs.contains(topic.id)
                            )
                        }
                        .buttonStyle(.plain)
                        if tIdx < topics.count - 1 {
                            Divider().background(Theme.border).padding(.leading, 54)
                        }
                    }
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isCompleted ? Theme.success.opacity(0.08) : Theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    isCompleted ? Theme.success.opacity(0.35) : Theme.border,
                    lineWidth: 1
                )
        )
        .animation(.snappy(duration: 0.22), value: isExpanded)
    }

    @ViewBuilder
    private var headerButton: some View {
        if hasTopics {
            Button {
                isExpanded.toggle()
            } label: {
                headerContent
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink(value: lesson) {
                headerContent
            }
            .buttonStyle(.plain)
        }
    }

    private var headerContent: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(isCompleted ? Theme.success : Theme.surfaceElevated)
                    .frame(width: 40, height: 40)
                    .shadow(color: isCompleted ? Theme.success.opacity(0.4) : .clear, radius: 8)

                if isCompleted {
                    Image(systemName: "checkmark")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    Text("\(index)")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(lesson.displayTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Image(systemName: isCompleted ? "checkmark.seal.fill" : (hasTopics ? "list.bullet" : "play.circle.fill"))
                        .font(.caption2)
                    if hasTopics {
                        Text("\(topics.count) alt ders")
                            .font(.caption.weight(isCompleted ? .bold : .regular))
                    } else {
                        Text(isCompleted ? "Tamamlandı" : "Ders")
                            .font(.caption.weight(isCompleted ? .bold : .regular))
                    }
                }
                .foregroundStyle(isCompleted ? Theme.success : Theme.textSecondary)
            }

            Spacer(minLength: 0)

            Image(systemName: hasTopics ? "chevron.down" : "chevron.right")
                .font(.footnote.bold())
                .foregroundStyle(Theme.textSecondary.opacity(0.6))
                .rotationEffect(.degrees(hasTopics && isExpanded ? 180 : 0))
        }
        .padding(14)
        .contentShape(Rectangle())
    }
}

struct TopicRow: View {
    let index: Int
    let topic: Topic
    let isCompleted: Bool

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(isCompleted ? Theme.success.opacity(0.25) : Theme.surfaceElevated)
                    .frame(width: 28, height: 28)
                if isCompleted {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.success)
                } else {
                    Text("\(index)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            Text(topic.displayTitle)
                .font(.footnote.weight(.medium))
                .foregroundStyle(isCompleted ? Theme.success : Theme.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption2.bold())
                .foregroundStyle(Theme.textSecondary.opacity(0.5))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .padding(.leading, 6)
        .contentShape(Rectangle())
    }
}

struct TopicDestination: Hashable {
    let topic: Topic
}

struct LessonRow: View {
    let index: Int
    let lesson: Lesson
    let isCompleted: Bool

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(isCompleted ? Theme.success : Theme.surfaceElevated)
                    .frame(width: 44, height: 44)
                    .shadow(color: isCompleted ? Theme.success.opacity(0.4) : .clear, radius: 8)

                if isCompleted {
                    Image(systemName: "checkmark")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    Text("\(index)")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(lesson.displayTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Image(systemName: isCompleted ? "checkmark.seal.fill" : "play.circle.fill")
                        .font(.caption)
                    Text(isCompleted ? "Tamamlandı" : "Ders")
                        .font(.caption.weight(isCompleted ? .bold : .regular))
                }
                .foregroundStyle(isCompleted ? Theme.success : Theme.textSecondary)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.footnote.bold())
                .foregroundStyle(Theme.textSecondary.opacity(0.5))
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isCompleted ? Theme.success.opacity(0.08) : Theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    isCompleted ? Theme.success.opacity(0.35) : Theme.border,
                    lineWidth: 1
                )
        )
    }
}
