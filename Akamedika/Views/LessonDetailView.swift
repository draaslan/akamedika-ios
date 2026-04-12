import SwiftUI
import WebKit

struct LessonDetailView: View {
    let lesson: Lesson
    @State private var viewModel = LessonDetailViewModel()

    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView("Ders yükleniyor...")
            } else if let error = viewModel.errorMessage {
                ContentUnavailableView {
                    Label("Hata", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Tekrar Dene") {
                        Task { await viewModel.fetchLesson(id: lesson.id) }
                    }
                }
            } else if let detail = viewModel.lesson {
                HTMLContentView(html: detail.htmlContent)
            }
        }
        .navigationTitle(lesson.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.fetchLesson(id: lesson.id)
        }
    }
}

struct HTMLContentView: UIViewRepresentable {
    let html: String

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let styledHTML = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <style>
            body {
                font-family: -apple-system, BlinkMacSystemFont, sans-serif;
                font-size: 17px;
                line-height: 1.6;
                padding: 16px;
                margin: 0;
                color: #333;
            }
            @media (prefers-color-scheme: dark) {
                body { color: #f0f0f0; background: transparent; }
                a { color: #6db3f2; }
            }
            img { max-width: 100%; height: auto; border-radius: 8px; }
            video { max-width: 100%; }
            iframe { max-width: 100%; }
        </style>
        </head>
        <body>\(html)</body>
        </html>
        """
        webView.loadHTMLString(styledHTML, baseURL: URL(string: "https://akamedika.com"))
    }
}
