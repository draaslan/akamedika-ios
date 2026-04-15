import SwiftUI

struct CourseListView: View {
    @State private var viewModel = CourseListViewModel()
    var onLogout: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                Group {
                    if viewModel.isLoading && viewModel.courses.isEmpty {
                        loadingView
                    } else if let error = viewModel.errorMessage, viewModel.courses.isEmpty {
                        errorView(error)
                    } else if viewModel.courses.isEmpty {
                        emptyView
                    } else {
                        courseGrid
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Image("akamedika-logo-beyaz")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 28)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(value: ProfileDestination()) {
                        Image(systemName: "person.crop.circle")
                            .font(.title3)
                            .foregroundStyle(Theme.textPrimary)
                    }
                }
            }
            .navigationDestination(for: Course.self) { course in
                LessonListView(course: course)
            }
            .navigationDestination(for: ProfileDestination.self) { _ in
                ProfileView(onLogout: onLogout)
            }
            .task {
                await viewModel.fetchCourses()
            }
        }
        .tint(Theme.accent)
    }

    private var loadingView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    SkeletonBlock(height: 30, widthFraction: 0.5)
                    SkeletonBlock(height: 13, widthFraction: 0.3)
                }
                .padding(.horizontal, 20)
                .shimmering()

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12),
                                   GridItem(.flexible(), spacing: 12)],
                          spacing: 12) {
                    ForEach(0..<6, id: \.self) { _ in
                        SkeletonCourseCard()
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .disabled(true)
    }

    private func errorView(_ error: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.orange)
            Text("Bir hata oluştu")
                .font(.title3.bold())
                .foregroundStyle(Theme.textPrimary)
            Text(error)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button {
                Task { await viewModel.fetchCourses() }
            } label: {
                Text("Tekrar Dene")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Theme.accentGradient)
                    .clipShape(Capsule())
            }
        }
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "books.vertical.fill")
                .font(.system(size: 54))
                .foregroundStyle(Theme.textSecondary.opacity(0.6))
            Text("Kurs bulunamadı")
                .font(.title3.bold())
                .foregroundStyle(Theme.textPrimary)
            Text("Kayıtlı olduğunuz bir kurs bulunmamaktadır.")
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 32)
    }

    private var courseGrid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Kurslarım")
                        .font(.largeTitle.bold())
                        .foregroundStyle(Theme.textPrimary)
                    Text("\(viewModel.courses.count) kurs mevcut")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12),
                                   GridItem(.flexible(), spacing: 12)],
                          spacing: 12) {
                    ForEach(viewModel.courses) { course in
                        NavigationLink(value: course) {
                            CourseCard(
                                course: course,
                                progress: viewModel.progress[course.id],
                                progressLoaded: viewModel.progressLoaded
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
        }
        .refreshable {
            await viewModel.fetchCourses()
        }
    }
}

struct ProfileDestination: Hashable {}

struct CourseCard: View {
    let course: Course
    let progress: CourseProgress?
    var progressLoaded: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SquareThumbnail {
                FillingAsyncImage(url: URL(string: course.featuredMediaURL ?? "")) {
                    placeholder
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(course.displayTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                progressSection
            }
            .padding(12)
        }
        .card()
    }

    @ViewBuilder
    private var progressSection: some View {
        if !progressLoaded {
            VStack(alignment: .leading, spacing: 5) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Theme.surfaceElevated)
                    .frame(width: 60, height: 10)
                RoundedRectangle(cornerRadius: 3)
                    .fill(Theme.surfaceElevated)
                    .frame(height: 6)
            }
            .shimmering()
        } else if let progress, progress.total > 0 {
            VStack(alignment: .leading, spacing: 5) {
                Text("%\(progress.percent) • \(progress.completed)/\(progress.total)")
                    .font(.caption2.bold())
                    .foregroundStyle(Theme.accent)
                ProgressBar(fraction: progress.fraction)
            }
        } else {
            Text("Başlanmadı")
                .font(.caption2.bold())
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var placeholder: some View {
        ZStack {
            Theme.accentGradient.opacity(0.35)
            Image(systemName: "book.closed.fill")
                .font(.system(size: 40))
                .foregroundStyle(.white.opacity(0.6))
        }
    }
}

struct ProgressBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.surfaceElevated)
                Capsule()
                    .fill(Theme.accentGradient)
                    .frame(width: max(0, min(1, fraction)) * geo.size.width)
            }
        }
        .frame(height: 6)
    }
}
