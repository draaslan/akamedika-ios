import SwiftUI

enum Theme {
    static let background = Color(red: 0.04, green: 0.05, blue: 0.08)
    static let surface = Color(red: 0.09, green: 0.10, blue: 0.14)
    static let surfaceElevated = Color(red: 0.13, green: 0.14, blue: 0.19)
    static let border = Color.white.opacity(0.08)
    static let textPrimary = Color(red: 0.96, green: 0.97, blue: 0.98)
    static let textSecondary = Color(red: 0.68, green: 0.72, blue: 0.80)
    static let accent = Color(red: 0.35, green: 0.68, blue: 1.0)
    static let accentSecondary = Color(red: 0.55, green: 0.45, blue: 1.0)
    static let success = Color(red: 0.30, green: 0.82, blue: 0.55)

    static let accentGradient = LinearGradient(
        colors: [accent, accentSecondary],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let surfaceGradient = LinearGradient(
        colors: [surfaceElevated, surface],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Theme.border, lineWidth: 1)
            )
    }
}

extension View {
    func card() -> some View { modifier(CardStyle()) }
}

/// A container that always renders as a square, filling with the given content
/// regardless of the content's intrinsic aspect ratio. Content is clipped.
struct SquareThumbnail<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                content()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .clipped()
            .contentShape(Rectangle())
    }
}

/// Helper that loads a remote image and always fills its container, cropped.
/// Pass `isLoading: true` to render the shimmer even when `url` is still nil
/// (e.g. a featured-media ID is being resolved upstream).
///
/// Backed by `CachedAsyncImage` rather than SwiftUI's `AsyncImage` because the
/// latter is unreliable inside `LazyVGrid`: cells that scroll into view late
/// often never resolve their image. The cached loader uses URLSession + an
/// in-memory cache keyed by URL, so each image is fetched at most once and
/// late-appearing cells reliably trigger their own load.
struct FillingAsyncImage<Placeholder: View>: View {
    let url: URL?
    var isLoading: Bool = false
    @ViewBuilder var placeholder: () -> Placeholder

    var body: some View {
        GeometryReader { geo in
            Group {
                if let url {
                    CachedAsyncImage(url: url, placeholder: placeholder)
                } else if isLoading {
                    ThumbnailShimmer()
                } else {
                    placeholder()
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
    }
}

/// Process-wide image cache. NSCache evicts on memory pressure automatically.
final class ImageCache {
    static let shared = ImageCache()
    private let cache = NSCache<NSURL, UIImage>()
    private init() { cache.countLimit = 200 }

    func image(for url: URL) -> UIImage? { cache.object(forKey: url as NSURL) }
    func store(_ image: UIImage, for url: URL) { cache.setObject(image, forKey: url as NSURL) }
}

/// Loads a remote image via URLSession with an in-memory cache. Renders a
/// shimmer while loading and falls back to the supplied placeholder on
/// failure. Uses `.task(id: url)` so cell reuse in lazy containers re-triggers
/// the load instead of getting stuck.
struct CachedAsyncImage<Placeholder: View>: View {
    let url: URL
    @ViewBuilder var placeholder: () -> Placeholder

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        GeometryReader { geo in
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                } else if failed {
                    placeholder()
                } else {
                    ThumbnailShimmer()
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
        .task(id: url) {
            await load()
        }
    }

    private func load() async {
        if let cached = ImageCache.shared.image(for: url) {
            image = cached
            return
        }
        image = nil
        failed = false
        do {
            var request = URLRequest(url: url)
            request.setValue("1", forHTTPHeaderField: "ngrok-skip-browser-warning")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let ui = UIImage(data: data) else {
                failed = true
                return
            }
            ImageCache.shared.store(ui, for: url)
            if !Task.isCancelled { image = ui }
        } catch {
            if !Task.isCancelled { failed = true }
        }
    }
}

/// A solid, shimmering rectangle sized to fill its container. Used as the
/// loading placeholder for any remote thumbnail.
struct ThumbnailShimmer: View {
    var body: some View {
        Rectangle()
            .fill(Theme.surfaceElevated)
            .shimmering()
    }
}

