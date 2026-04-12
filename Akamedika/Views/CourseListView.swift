import SwiftUI

struct CourseListView: View {
    @State private var viewModel = CourseListViewModel()
    var onLogout: () -> Void

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.courses.isEmpty {
                    ProgressView("Kurslar yükleniyor...")
                } else if let error = viewModel.errorMessage, viewModel.courses.isEmpty {
                    ContentUnavailableView {
                        Label("Hata", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Tekrar Dene") {
                            Task { await viewModel.fetchCourses() }
                        }
                    }
                } else if viewModel.courses.isEmpty {
                    ContentUnavailableView(
                        "Kurs Bulunamadı",
                        systemImage: "book.closed",
                        description: Text("Kayıtlı olduğunuz bir kurs bulunmamaktadır.")
                    )
                } else {
                    List(viewModel.courses) { course in
                        NavigationLink(value: course) {
                            CourseRow(course: course)
                        }
                    }
                    .refreshable {
                        await viewModel.fetchCourses()
                    }
                }
            }
            .navigationTitle("Kurslarım")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Çıkış", systemImage: "rectangle.portrait.and.arrow.right") {
                        onLogout()
                    }
                }
            }
            .navigationDestination(for: Course.self) { course in
                LessonListView(course: course)
            }
            .task {
                await viewModel.fetchCourses()
            }
        }
    }
}

struct CourseRow: View {
    let course: Course

    var body: some View {
        HStack(spacing: 12) {
            if let imageURL = course.featuredMediaURL, let url = URL(string: imageURL) {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.fill.tertiary)
                        .overlay {
                            Image(systemName: "book.fill")
                                .foregroundStyle(.secondary)
                        }
                }
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            Text(course.displayTitle)
                .font(.headline)
        }
        .padding(.vertical, 4)
    }
}
