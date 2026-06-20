import SwiftUI
import WebKit
import AVFoundation

struct LessonDetailView: View {
    let lesson: Lesson
    var index: Int = 0
    var total: Int = 0
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
        .navigationTitle("Ders")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task {
            await viewModel.fetchLesson(id: lesson.id)
        }
    }

    private func content(detail: Lesson) -> some View {
        let parsed = PrestoContent.parse(detail.htmlContent)
        return VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(detail.displayTitle)
                                .font(.title2.bold())
                                .foregroundStyle(Theme.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)

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
                        .frame(maxWidth: .infinity, alignment: .leading)

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
                            .frame(width: 120, height: 68)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                    ForEach(parsed.videos) { video in
                        PrestoVideoView(
                            video: video,
                            title: detail.displayTitle,
                            artworkURL: (detail.featuredMediaURL ?? lesson.featuredMediaURL)
                                .flatMap { URL(string: $0) }
                        )
                    }

                    HTMLContentView(html: parsed.cleanedHTML, dynamicHeight: $contentHeight)
                        .frame(height: contentHeight)
                }
                .padding(.bottom, 100)
            }

            footer
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            if !displayCompleted {
                completeButton
            }
            LessonNavRow(index: index, total: total)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 16)
        .background(
            Theme.background
                .shadow(color: .black.opacity(0.4), radius: 12, y: -6)
                .ignoresSafeArea(edges: .bottom)
        )
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
    }

    private func markComplete() async {
        guard let userId = AuthService.currentUserId else { return }
        isMarking = true
        do {
            let completed = try await LearnDashService().markComplete(userId: userId, postId: lesson.id)
            if completed {
                locallyCompleted = true
                await onCompletionChanged()
            }
        } catch {
            // Keep the button so the user can retry.
        }
        isMarking = false
    }
}

/// Previous / Next bar shared by the lesson and topic detail screens. Pushes the
/// adjacent content item onto the navigation stack via `ContentNav`.
struct LessonNavRow: View {
    let index: Int
    let total: Int

    var body: some View {
        HStack(spacing: 12) {
            navLink(title: "Önceki", systemImage: "chevron.left",
                    targetIndex: index - 1, enabled: index > 0, trailingIcon: false)
            navLink(title: "Sonraki", systemImage: "chevron.right",
                    targetIndex: index + 1, enabled: index < total - 1, trailingIcon: true)
        }
    }

    @ViewBuilder
    private func navLink(title: String, systemImage: String, targetIndex: Int, enabled: Bool, trailingIcon: Bool) -> some View {
        if enabled {
            NavigationLink(value: ContentNav(index: targetIndex)) {
                label(title: title, systemImage: systemImage, trailingIcon: trailingIcon, dim: false)
            }
            .buttonStyle(.plain)
        } else {
            label(title: title, systemImage: systemImage, trailingIcon: trailingIcon, dim: true)
        }
    }

    private func label(title: String, systemImage: String, trailingIcon: Bool, dim: Bool) -> some View {
        HStack(spacing: 6) {
            if !trailingIcon { Image(systemName: systemImage).font(.footnote.bold()) }
            Text(title).font(.subheadline.weight(.semibold))
            if trailingIcon { Image(systemName: systemImage).font(.footnote.bold()) }
        }
        .foregroundStyle(dim ? Theme.textSecondary.opacity(0.35) : Theme.textPrimary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 13)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1)
        )
    }
}

struct HTMLContentView: UIViewRepresentable {
    let html: String
    @Binding var dynamicHeight: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator(height: $dynamicHeight) }

    func makeUIView(context: Context) -> WKWebView {
        // Activate a playback audio session so the lesson video keeps playing when
        // the device is locked or backgrounded (paired with the `audio` background
        // mode). Just setting the category isn't enough — the session must be made
        // active for WebKit to keep the media running off-screen.
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback)
        try? session.setActive(true)

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
        <!-- Bunny.net token auth validates the referrer; send our origin on the
             cross-origin HLS/segment requests so the signed stream authorizes. -->
        <meta name="referrer" content="origin">
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
            .video-wrapper video { background: #000; }
        </style>
        </head>
        <body>\(processed)
        <script>\(Self.prestoScript)</script>
        </body>
        </html>
        """
        webView.loadHTMLString(styledHTML, baseURL: URL(string: "https://akamedika.com"))
    }

    /// Presto Player renders its videos as a `<presto-player>` web component that
    /// only hydrates when Presto's own JS bundle is loaded — which it isn't inside
    /// our bare WKWebView, so the video never appears. The real source lives in the
    /// element's attributes: Bunny.net streams as a signed HLS (`.m3u8`) URL in
    /// `src`, YouTube/Vimeo as a provider id. iOS plays HLS natively in a `<video>`
    /// tag (exactly what Safari does on the site), so we swap each presto-player for
    /// a native player / provider iframe. The signed Bunny token is minted fresh by
    /// WordPress on every content fetch, so it's valid when this runs.
    static let prestoScript = """
    (function(){
      function wrap(el){
        var w = document.createElement('div');
        w.className = 'video-wrapper';
        w.appendChild(el);
        return w;
      }
      function youtubeId(p){
        var v = p.getAttribute('provider-video-id');
        if (v) return v;
        try {
          var ba = JSON.parse(p.getAttribute('block-attributes') || '{}');
          var m = String(ba.src || '').match(/(?:youtu\\.be\\/|[?&]v=|embed\\/)([A-Za-z0-9_-]{6,})/);
          if (m) return m[1];
        } catch (e) {}
        return '';
      }
      function iframe(url){
        var f = document.createElement('iframe');
        f.setAttribute('src', url);
        f.setAttribute('allowfullscreen', '');
        f.setAttribute('allow', 'autoplay; encrypted-media; picture-in-picture');
        return f;
      }
      function convert(p){
        var cls = ((p.closest('figure') ? p.closest('figure').className : '') + ' ' + (p.className || ''));
        var node;
        if (/presto-provider-youtube/.test(cls)) {
          var yid = youtubeId(p);
          if (!yid) return;
          node = iframe('https://www.youtube.com/embed/' + yid);
        } else if (/presto-provider-vimeo/.test(cls)) {
          var vid = p.getAttribute('provider-video-id') || '';
          if (!vid) return;
          node = iframe('https://player.vimeo.com/video/' + vid);
        } else {
          var src = p.getAttribute('src') || '';
          if (!src) return;
          var video = document.createElement('video');
          video.setAttribute('controls', '');
          video.setAttribute('playsinline', '');
          video.setAttribute('webkit-playsinline', '');
          video.setAttribute('preload', 'metadata');
          var poster = p.getAttribute('poster');
          if (poster) video.setAttribute('poster', poster);
          var source = document.createElement('source');
          source.setAttribute('src', src);
          if (src.indexOf('.m3u8') !== -1) source.setAttribute('type', 'application/vnd.apple.mpegurl');
          else if (src.indexOf('.mp4') !== -1) source.setAttribute('type', 'video/mp4');
          video.appendChild(source);
          node = video;
        }
        var target = p.closest('figure.presto-block-video') || p.closest('figure') || p;
        if (target.parentNode) target.parentNode.replaceChild(wrap(node), target);
      }
      function run(){
        var list = document.querySelectorAll('presto-player');
        for (var i = 0; i < list.length; i++) { try { convert(list[i]); } catch (e) {} }
      }
      if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', run);
      else run();
    })();
    """

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
