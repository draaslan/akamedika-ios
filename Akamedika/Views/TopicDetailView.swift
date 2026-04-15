import SwiftUI

struct TopicDetailView: View {
    let topic: Topic
    let isCompleted: Bool
    var onCompletionChanged: () async -> Void = {}

    @State private var htmlContent: String = ""
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isMarking = false
    @State private var locallyCompleted = false
    @State private var contentHeight: CGFloat = 400

    var displayCompleted: Bool { isCompleted || locallyCompleted }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            if isLoading {
                PulseLoader(message: "İçerik yükleniyor…")
            } else if let error = errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.orange)
                    Text(error)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                    Button("Tekrar Dene") {
                        Task { await loadContent() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                content
            }
        }
        .navigationTitle(topic.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task {
            await loadContent()
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(topic.displayTitle)
                            .font(.title2.bold())
                            .foregroundStyle(Theme.textPrimary)

                        if displayCompleted {
                            Label("Tamamlandı", systemImage: "checkmark.seal.fill")
                                .font(.caption.bold())
                                .foregroundStyle(Theme.success)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Theme.success.opacity(0.15))
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                    HTMLContentView(html: htmlContent, dynamicHeight: $contentHeight)
                        .frame(height: contentHeight)
                }
                .padding(.bottom, 100)
            }

            if !displayCompleted {
                completeButton
            }
        }
    }

    private var completeButton: some View {
        Button {
            Task { await markComplete() }
        } label: {
            HStack {
                if isMarking {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Tamamla")
                        .font(.headline)
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Theme.accentGradient)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .disabled(isMarking)
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .background(
            Theme.background
                .shadow(color: .black.opacity(0.4), radius: 12, y: -6)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func loadContent() async {
        isLoading = true
        errorMessage = nil
        struct TopicContent: Decodable {
            let content: RenderedContent?
        }
        do {
            let t: TopicContent = try await APIClient.shared.request("/wp/v2/sfwd-topic/\(topic.id)")
            htmlContent = t.content?.rendered ?? ""
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func markComplete() async {
        guard let userId = AuthService.currentUserId else { return }
        isMarking = true
        defer { isMarking = false }
        struct Empty: Decodable {}
        _ = try? await APIClient.shared.request("/ldlms/v2/users/\(userId)/topics/\(topic.id)", method: "POST", body: ["status": "complete"]) as Empty
        locallyCompleted = true
        await onCompletionChanged()
    }
}
