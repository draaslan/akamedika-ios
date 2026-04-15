import SwiftUI
import WebKit

struct LessonDetailView: View {
    let lesson: Lesson
    let isCompleted: Bool
    var onCompletionChanged: () async -> Void = {}

    @State private var viewModel = LessonDetailViewModel()
    @State private var isMarking = false
    @State private var locallyCompleted = false
    @State private var contentHeight: CGFloat = 400

    var displayCompleted: Bool { isCompleted || locallyCompleted }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            Group {
                if viewModel.isLoading {
                    PulseLoader(message: "Ders yükleniyor…")
                } else if let error = viewModel.errorMessage {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(.orange)
                        Text(error)
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 30)
                        Button("Tekrar Dene") {
                            Task { await viewModel.fetchLesson(id: lesson.id) }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else if let detail = viewModel.lesson {
                    content(detail: detail)
                }
            }
        }
        .navigationTitle(lesson.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task {
            await viewModel.fetchLesson(id: lesson.id)
        }
    }

    private func content(detail: Lesson) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let urlString = detail.featuredMediaURL ?? lesson.featuredMediaURL,
                       let url = URL(string: urlString) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().aspectRatio(contentMode: .fill)
                            case .empty:
                                ThumbnailShimmer()
                            default:
                                Theme.surface
                            }
                        }
                        .frame(height: 200)
                        .frame(maxWidth: .infinity)
                        .clipped()
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(detail.displayTitle)
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

                    HTMLContentView(html: detail.htmlContent, dynamicHeight: $contentHeight)
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
                    Text("Dersi Tamamla")
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

    private func markComplete() async {
        guard let userId = AuthService.currentUserId else { return }
        isMarking = true
        do {
            try await LearnDashService().markLessonComplete(userId: userId, lessonId: lesson.id)
            locallyCompleted = true
            await onCompletionChanged()
        } catch {
            // Silently fail
        }
        isMarking = false
    }
}

struct HTMLContentView: UIViewRepresentable {
    let html: String
    @Binding var dynamicHeight: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator(height: $dynamicHeight) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsPictureInPictureMediaPlayback = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if context.coordinator.lastHTML == html { return }
        context.coordinator.lastHTML = html

        let processed = Self.processEmbeds(html)
        let styledHTML = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
        <style>
            :root { color-scheme: dark; }
            html, body { background: transparent; margin: 0; padding: 0; }
            body {
                font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Text', sans-serif;
                font-size: 16px;
                line-height: 1.65;
                padding: 16px 20px 24px 20px;
                color: #F5F7FA;
                word-wrap: break-word;
            }
            h1, h2, h3, h4 { color: #FFFFFF; margin: 1.2em 0 0.5em; line-height: 1.3; }
            h1 { font-size: 24px; } h2 { font-size: 21px; } h3 { font-size: 19px; }
            p { margin: 0 0 14px 0; color: #D9DEE6; }
            a { color: #5AAFFF; text-decoration: none; }
            strong, b { color: #FFFFFF; }
            ul, ol { padding-left: 22px; margin: 0 0 14px 0; color: #D9DEE6; }
            li { margin-bottom: 6px; }
            blockquote {
                border-left: 3px solid #5AAFFF;
                margin: 16px 0; padding: 6px 14px;
                background: rgba(90,175,255,0.08);
                border-radius: 6px; color: #C8D0DC;
            }
            code { background: rgba(255,255,255,0.08); padding: 2px 6px; border-radius: 5px; font-size: 0.9em; }
            pre { background: #1A1D26; padding: 14px; border-radius: 10px; overflow-x: auto; border: 1px solid rgba(255,255,255,0.08); }
            img { max-width: 100%; height: auto; border-radius: 10px; display: block; margin: 14px auto; }
            figure { margin: 14px 0; }
            figcaption { font-size: 13px; color: #9BA3B2; text-align: center; margin-top: 6px; }
            hr { border: none; border-top: 1px solid rgba(255,255,255,0.1); margin: 20px 0; }
            table { width: 100%; border-collapse: collapse; margin: 14px 0; }
            th, td { border: 1px solid rgba(255,255,255,0.1); padding: 8px; text-align: left; }
            th { background: rgba(255,255,255,0.05); }
            .video-wrapper {
                position: relative; width: 100%; padding-bottom: 56.25%;
                height: 0; margin: 16px 0; border-radius: 12px;
                overflow: hidden; background: #000;
            }
            .video-wrapper iframe, .video-wrapper video,
            .video-wrapper embed, .video-wrapper object {
                position: absolute !important; top: 0; left: 0;
                width: 100% !important; height: 100% !important; border: 0;
            }
            iframe, video, embed, object { max-width: 100%; }
        </style>
        </head>
        <body>\(processed)</body>
        </html>
        """
        webView.loadHTMLString(styledHTML, baseURL: URL(string: "https://akamedika.com"))
    }

    static func processEmbeds(_ raw: String) -> String {
        var s = raw

        // Rewrite internal WordPress hosts to public origin so media loads.
        let publicOrigin = APIClient.shared.publicOrigin
        for host in ["https://akamedika-new.test", "http://akamedika-new.test",
                     "https://akamedika.test", "http://akamedika.test"] {
            s = s.replacingOccurrences(of: host, with: publicOrigin)
        }

        s = s.replacingOccurrences(
            of: #"<(iframe|img|video|source|embed)([^>]*?)\s(data-src|data-lazy-src|data-ez-src)=\""#,
            with: "<$1$2 src=\"",
            options: .regularExpression
        )

        s = s.replacingOccurrences(
            of: #"(<iframe[\s\S]*?</iframe>)"#,
            with: "<div class=\"video-wrapper\">$1</div>",
            options: .regularExpression
        )

        s = s.replacingOccurrences(
            of: #"(<video[\s\S]*?</video>)"#,
            with: "<div class=\"video-wrapper\">$1</div>",
            options: .regularExpression
        )

        s = s.replacingOccurrences(
            of: #"\[embed\](https?://(?:www\.)?(?:youtube\.com/watch\?v=|youtu\.be/)([A-Za-z0-9_-]+)[^\]]*)\[/embed\]"#,
            with: "<div class=\"video-wrapper\"><iframe src=\"https://www.youtube.com/embed/$2\" allowfullscreen allow=\"autoplay; encrypted-media; picture-in-picture\"></iframe></div>",
            options: .regularExpression
        )

        s = s.replacingOccurrences(
            of: #"\[embed\]https?://(?:www\.)?vimeo\.com/(\d+)[^\]]*\[/embed\]"#,
            with: "<div class=\"video-wrapper\"><iframe src=\"https://player.vimeo.com/video/$1\" allowfullscreen allow=\"autoplay; encrypted-media; picture-in-picture\"></iframe></div>",
            options: .regularExpression
        )

        return s
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        @Binding var height: CGFloat
        weak var webView: WKWebView?
        var lastHTML: String = ""
        private var pollTimer: Timer?

        init(height: Binding<CGFloat>) {
            self._height = height
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            measure(webView)
            // Polling catches late-loaded images / iframes resizing the body.
            pollTimer?.invalidate()
            var ticks = 0
            pollTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self, weak webView] timer in
                guard let webView else { timer.invalidate(); return }
                self?.measure(webView)
                ticks += 1
                if ticks > 15 { timer.invalidate() }
            }
        }

        private func measure(_ webView: WKWebView) {
            webView.evaluateJavaScript("document.documentElement.scrollHeight") { [weak self] result, _ in
                guard let self, let h = result as? CGFloat else { return }
                if abs(h - self.height) > 1 {
                    DispatchQueue.main.async { self.height = h }
                }
            }
        }
    }
}
