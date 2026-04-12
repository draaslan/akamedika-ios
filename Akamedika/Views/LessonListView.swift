import SwiftUI

struct LessonListView: View {
    let course: Course
    @State private var viewModel = LessonListViewModel()

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.lessons.isEmpty {
                ProgressView("Dersler yükleniyor...")
            } else if let error = viewModel.errorMessage, viewModel.lessons.isEmpty {
                ContentUnavailableView {
                    Label("Hata", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Tekrar Dene") {
                        Task { await viewModel.fetchLessons(courseId: course.id) }
                    }
                }
            } else if viewModel.lessons.isEmpty {
                ContentUnavailableView(
                    "Ders Bulunamadı",
                    systemImage: "doc.text",
                    description: Text("Bu kursta henüz ders bulunmamaktadır.")
                )
            } else {
                List(viewModel.lessons) { lesson in
                    NavigationLink(value: lesson) {
                        LessonRow(lesson: lesson)
                    }
                }
                .refreshable {
                    await viewModel.fetchLessons(courseId: course.id)
                }
            }
        }
        .navigationTitle(course.displayTitle)
        .navigationDestination(for: Lesson.self) { lesson in
            LessonDetailView(lesson: lesson)
        }
        .task {
            await viewModel.fetchLessons(courseId: course.id)
        }
    }
}

struct LessonRow: View {
    let lesson: Lesson

    var body: some View {
        HStack {
            Image(systemName: "play.circle.fill")
                .font(.title2)
                .foregroundStyle(.tint)
            Text(lesson.displayTitle)
                .font(.body)
        }
        .padding(.vertical, 4)
    }
}
