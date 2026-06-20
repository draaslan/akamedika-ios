import SwiftUI
import AVKit
import AVFoundation
import UIKit

/// Parses Bunny.net (HLS) videos out of Presto Player lesson HTML so they can be
/// played by a native `AVPlayer` instead of inside the WKWebView. Native playback
/// is the only reliable way to keep audio going when the device is locked, and it
/// brings lock-screen controls, playback speed + Picture-in-Picture for free.
enum PrestoContent {
    struct Video: Identifiable, Equatable {
        let id = UUID()
        let url: URL
        let title: String?
        let poster: URL?
        static func == (l: Video, r: Video) -> Bool { l.url == r.url }
    }

    /// Returns the Bunny videos found in `html` plus the HTML with those video
    /// blocks removed (text and any YouTube/Vimeo embeds are left untouched).
    static func parse(_ html: String) -> (videos: [Video], cleanedHTML: String) {
        let figurePattern = #"<figure[^>]*presto-block-video[^>]*>[\s\S]*?</figure>"#
        guard let figureRegex = try? NSRegularExpression(pattern: figurePattern, options: [.caseInsensitive]) else {
            return ([], html)
        }
        let ns = html as NSString
        let matches = figureRegex.matches(in: html, range: NSRange(location: 0, length: ns.length))

        var videos: [Video] = []
        var removeRanges: [NSRange] = []
        for m in matches {
            let figure = ns.substring(with: m.range)
            guard let src = attribute("src", in: figure),
                  src.contains(".m3u8") || src.contains("b-cdn"),
                  let url = URL(string: src) else { continue }
            let poster = attribute("poster", in: figure).flatMap { URL(string: $0) }
            videos.append(Video(url: url, title: attribute("media-title", in: figure), poster: poster))
            removeRanges.append(m.range)
        }

        guard !removeRanges.isEmpty else { return ([], html) }

        let mutable = NSMutableString(string: html)
        for range in removeRanges.reversed() {
            mutable.replaceCharacters(in: range, with: "")
        }
        var cleaned = mutable as String
        // Drop the leftover `<!--presto-player:video_id=N-->` markers.
        cleaned = cleaned.replacingOccurrences(
            of: #"<!--presto-player:[^>]*-->"#, with: "", options: .regularExpression)
        return (videos, cleaned)
    }

    private static func attribute(_ name: String, in tag: String) -> String? {
        let pattern = "\(name)\\s*=\\s*\"([^\"]*)\""
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let ns = tag as NSString
        guard let m = re.firstMatch(in: tag, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges > 1 else { return nil }
        return decodeEntities(ns.substring(with: m.range(at: 1)))
    }

    private static func decodeEntities(_ s: String) -> String {
        s.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&#038;", with: "&")
            .replacingOccurrences(of: "&#38;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
    }
}

/// A native player for a Bunny HLS stream. Sends the `Referer` that Bunny's token
/// auth requires, keeps audio playing while locked / backgrounded, and feeds the
/// lock-screen Now Playing card a title + artwork (the Akamedika logo as fallback).
struct PrestoVideoPlayer: UIViewControllerRepresentable {
    let url: URL
    var title: String = ""
    var artworkURL: URL?

    private static let referer = "https://akamedika.com/"

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback)
        try? session.setActive(true)

        let asset = AVURLAsset(url: url, options: [
            "AVURLAssetHTTPHeaderFieldsKey": ["Referer": Self.referer]
        ])
        let item = AVPlayerItem(asset: asset)
        // Title shows on the lock screen immediately; artwork is filled in async.
        item.externalMetadata = [Self.titleMetadata(title)]

        let player = AVPlayer(playerItem: item)
        player.allowsExternalPlayback = true

        let controller = AVPlayerViewController()
        controller.player = player
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.speeds = Self.speedOptions
        context.coordinator.player = player

        loadArtwork(into: item)
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {}

    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: Coordinator) {
        // Stop audio when the screen is dismissed (locking the device does NOT
        // dismantle the view, so locked playback keeps running).
        controller.player?.pause()
        controller.player = nil
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var player: AVPlayer? }

    // MARK: - Playback speed

    private static let speedOptions: [AVPlaybackSpeed] = [
        (0.5, "0.5x"), (0.75, "0.75x"), (1.0, "1x"),
        (1.25, "1.25x"), (1.5, "1.5x"), (1.75, "1.75x"), (2.0, "2x")
    ].map { AVPlaybackSpeed(rate: Float($0.0), localizedName: $0.1) }

    // MARK: - Now Playing metadata

    private func loadArtwork(into item: AVPlayerItem) {
        let title = self.title
        let artworkURL = self.artworkURL
        Task {
            let image = await Self.downloadImage(artworkURL) ?? Self.fallbackArtwork()
            guard let image, let artwork = Self.artworkMetadata(image) else { return }
            await MainActor.run {
                item.externalMetadata = [Self.titleMetadata(title), artwork]
            }
        }
    }

    private static func titleMetadata(_ title: String) -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.identifier = .commonIdentifierTitle
        item.value = (title.isEmpty ? "Akamedika" : title) as NSString
        item.extendedLanguageTag = "und"
        return item
    }

    private static func artworkMetadata(_ image: UIImage) -> AVMetadataItem? {
        guard let data = image.pngData() else { return nil }
        let item = AVMutableMetadataItem()
        item.identifier = .commonIdentifierArtwork
        item.value = data as NSData
        item.dataType = kCMMetadataBaseDataType_PNG as String
        item.extendedLanguageTag = "und"
        return item
    }

    private static func downloadImage(_ url: URL?) async -> UIImage? {
        guard let url else { return nil }
        var request = URLRequest(url: url)
        request.setValue(referer, forHTTPHeaderField: "Referer")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let image = UIImage(data: data) else { return nil }
        return image
    }

    /// The Akamedika logo centered on a dark square, used when there's no thumbnail.
    private static func fallbackArtwork() -> UIImage? {
        let size = CGSize(width: 600, height: 600)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor(red: 0.055, green: 0.067, blue: 0.094, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            guard let logo = UIImage(named: "akamedika-logo-beyaz") else { return }
            let targetWidth = size.width * 0.7
            let scale = targetWidth / logo.size.width
            let w = logo.size.width * scale
            let h = logo.size.height * scale
            logo.draw(in: CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h))
        }
    }
}

/// Lays the native player out at a 16:9 ratio to match the in-page video frame.
struct PrestoVideoView: View {
    let video: PrestoContent.Video
    var title: String = ""
    var artworkURL: URL?

    var body: some View {
        PrestoVideoPlayer(url: video.url, title: title.isEmpty ? (video.title ?? "") : title,
                          artworkURL: artworkURL ?? video.poster)
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 16)
    }
}
