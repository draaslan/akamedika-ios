import SwiftUI
import AVKit
import AVFoundation
import MediaPlayer
import UIKit

/// Parses Bunny.net (HLS) videos out of Presto Player lesson HTML so they can be
/// played by a native `AVPlayer` instead of inside the WKWebView. Native playback
/// is the only reliable way to keep audio going when the device is locked, and it
/// brings lock-screen controls, playback speed + Picture-in-Picture for free.
enum PrestoContent {
    struct Video: Identifiable, Equatable {
        // Stable identity (the URL, not a fresh UUID) so re-parsing the same HTML on
        // a SwiftUI body re-eval doesn't give the ForEach a new id and tear down /
        // recreate the player — which would spawn a second AVPlayer + audio track.
        var id: String { url.absoluteString }
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

/// Persists per-video playback position so a lesson resumes where the user left
/// off. Keyed by the video's host + path (not the full URL) because Bunny mints a
/// fresh signed token on every content fetch, so the query string is unstable.
enum VideoProgressStore {
    private static let prefix = "video_progress_"

    private static func key(for url: URL) -> String {
        // Drop token-like path segments so the key survives token rotation whether
        // Bunny signs via the query string (path already stable) or via the path.
        let stable = url.pathComponents.filter { seg in
            seg != "/" &&
            !seg.contains("=") &&
            !seg.lowercased().contains("token") &&
            !seg.lowercased().contains("expires")
        }
        return prefix + (url.host ?? "") + "/" + stable.joined(separator: "/")
    }

    static func save(_ seconds: Double, for url: URL) {
        UserDefaults.standard.set(seconds, forKey: key(for: url))
    }

    static func load(for url: URL) -> Double {
        UserDefaults.standard.double(forKey: key(for: url))
    }

    static func clear(for url: URL) {
        UserDefaults.standard.removeObject(forKey: key(for: url))
    }
}

/// A native player for a Bunny HLS stream. Sends the `Referer` that Bunny's token
/// auth requires, keeps audio playing while the device is locked / backgrounded,
/// resumes from the last position, and feeds the lock-screen Now Playing card a
/// title + artwork (the Akamedika logo as fallback).
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

        context.coordinator.start(player: player, controller: controller, url: url,
                                  title: title, artworkURL: artworkURL)

        loadArtwork(into: item)
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {}

    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: Coordinator) {
        // Persist the final position, then stop audio when the screen is dismissed
        // (locking the device does NOT dismantle the view, so locked playback keeps
        // running).
        coordinator.saveProgress()
        coordinator.teardown()
        controller.player?.pause()
        controller.player = nil
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// Keeps audio alive on lock by detaching the player from the
    /// `AVPlayerViewController` when backgrounded (the standalone `AVPlayer` keeps
    /// playing; the VC would otherwise pause it) and reattaching on foreground.
    ///
    /// The lock-screen card is owned by an explicit `MPNowPlayingSession` built
    /// around our player. We publish title / artwork / duration / elapsed onto the
    /// *session's* own info center (the one the lock screen actually reads — writing
    /// to `MPNowPlayingInfoCenter.default()` is silently ignored while the session is
    /// active). Remote commands are wired to that session's command center. The card
    /// stays live even after we detach the player from the view controller for
    /// background audio. Also resumes from the last position.
    final class Coordinator: NSObject {
        private(set) var player: AVPlayer?
        private weak var controller: AVPlayerViewController?
        private var url: URL?
        private var title = ""
        private var artwork: MPMediaItemArtwork?
        private var nowPlayingSession: MPNowPlayingSession?
        private var timeObserver: Any?
        private var statusObservation: NSKeyValueObservation?
        private var rateObservation: NSKeyValueObservation?
        private var didSeek = false

        func start(player: AVPlayer, controller: AVPlayerViewController, url: URL,
                   title: String, artworkURL: URL?) {
            self.player = player
            self.controller = controller
            self.url = url
            self.title = title

            statusObservation = player.currentItem?.observe(\.status) { [weak self] item, _ in
                guard let self, item.status == .readyToPlay else { return }
                if !self.didSeek {
                    self.didSeek = true
                    self.seekToSavedPosition(duration: item.duration.seconds)
                }
                self.updateNowPlayingInfo()
            }

            rateObservation = player.observe(\.rate) { [weak self] _, _ in
                self?.updateNowPlayingInfo()
            }

            let interval = CMTime(seconds: 5, preferredTimescale: 1)
            timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] _ in
                self?.saveProgress()
                self?.updateNowPlayingInfo()
            }

            setupNowPlayingSession(player: player)
            loadNowPlayingArtwork(artworkURL)

            let center = NotificationCenter.default
            center.addObserver(self, selector: #selector(didEnterBackground),
                               name: UIApplication.didEnterBackgroundNotification, object: nil)
            center.addObserver(self, selector: #selector(willEnterForeground),
                               name: UIApplication.willEnterForegroundNotification, object: nil)
        }

        // MARK: - Resume

        private func seekToSavedPosition(duration: Double) {
            guard let url, let player else { return }
            let saved = VideoProgressStore.load(for: url)
            guard saved > 3 else { return }
            if duration.isFinite, saved >= duration - 5 {
                VideoProgressStore.clear(for: url)
                return
            }
            // Tolerant seek (not .zero) — precise seeking is slow/unreliable on HLS.
            player.seek(to: CMTime(seconds: saved, preferredTimescale: 600)) { [weak self] _ in
                self?.updateNowPlayingInfo()
            }
        }

        func saveProgress() {
            guard let url, let player, let item = player.currentItem else { return }
            let t = player.currentTime().seconds
            guard t.isFinite, t > 0 else { return }
            let duration = item.duration.seconds
            if duration.isFinite, t >= duration - 5 {
                VideoProgressStore.clear(for: url)
            } else {
                VideoProgressStore.save(t, for: url)
            }
        }

        // MARK: - Lock-screen Now Playing

        private func setupNowPlayingSession(player: AVPlayer) {
            let session = MPNowPlayingSession(players: [player])
            // We publish the info ourselves (title + artwork included), so turn off
            // the automatic publisher that would otherwise overwrite it with timing
            // only and drop our metadata.
            session.automaticallyPublishesNowPlayingInfo = false
            self.nowPlayingSession = session

            let c = session.remoteCommandCenter
            c.playCommand.addTarget { [weak self] _ in
                guard let p = self?.player else { return .commandFailed }
                p.play(); return .success
            }
            c.pauseCommand.addTarget { [weak self] _ in
                guard let p = self?.player else { return .commandFailed }
                p.pause(); return .success
            }
            c.togglePlayPauseCommand.addTarget { [weak self] _ in
                guard let p = self?.player else { return .commandFailed }
                if p.rate == 0 { p.play() } else { p.pause() }
                return .success
            }
            c.changePlaybackPositionCommand.addTarget { [weak self] event in
                guard let p = self?.player,
                      let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
                p.seek(to: CMTime(seconds: e.positionTime, preferredTimescale: 600))
                return .success
            }
            for skip in [c.skipForwardCommand, c.skipBackwardCommand] { skip.preferredIntervals = [15] }
            c.skipForwardCommand.addTarget { [weak self] _ in self?.skip(by: 15); return .success }
            c.skipBackwardCommand.addTarget { [weak self] _ in self?.skip(by: -15); return .success }

            session.becomeActiveIfPossible()
            updateNowPlayingInfo()
        }

        private func skip(by seconds: Double) {
            guard let player else { return }
            let target = max(0, player.currentTime().seconds + seconds)
            player.seek(to: CMTime(seconds: target, preferredTimescale: 600)) { [weak self] _ in
                self?.updateNowPlayingInfo()
            }
        }

        private func updateNowPlayingInfo() {
            if !Thread.isMainThread {
                DispatchQueue.main.async { [weak self] in self?.updateNowPlayingInfo() }
                return
            }
            guard let session = nowPlayingSession, let player, let item = player.currentItem else { return }
            var info: [String: Any] = [
                MPMediaItemPropertyTitle: title.isEmpty ? "Akamedika" : title,
                MPNowPlayingInfoPropertyElapsedPlaybackTime: player.currentTime().seconds,
                MPNowPlayingInfoPropertyPlaybackRate: player.rate
            ]
            let duration = item.duration.seconds
            if duration.isFinite { info[MPMediaItemPropertyPlaybackDuration] = duration }
            if let artwork { info[MPMediaItemPropertyArtwork] = artwork }
            let center = session.nowPlayingInfoCenter
            center.nowPlayingInfo = info
            center.playbackState = player.rate > 0 ? .playing : .paused
        }

        private func loadNowPlayingArtwork(_ artworkURL: URL?) {
            Task {
                let image = await PrestoVideoPlayer.downloadImage(artworkURL)
                    ?? PrestoVideoPlayer.fallbackArtwork()
                guard let image else { return }
                await MainActor.run {
                    self.artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                    self.updateNowPlayingInfo()
                }
            }
        }

        // MARK: - Background keep-alive

        @objc private func didEnterBackground() {
            saveProgress()
            // Detach so AVPlayerViewController doesn't pause the player; audio continues.
            // The MPNowPlayingSession still references the player, so the lock-screen
            // card keeps publishing and the controls stay live.
            if controller?.player != nil { controller?.player = nil }
            updateNowPlayingInfo()
        }

        @objc private func willEnterForeground() {
            if controller?.player == nil { controller?.player = player }
        }

        func teardown() {
            if let timeObserver, let player { player.removeTimeObserver(timeObserver) }
            timeObserver = nil
            statusObservation?.invalidate()
            statusObservation = nil
            rateObservation?.invalidate()
            rateObservation = nil
            NotificationCenter.default.removeObserver(self)
            nowPlayingSession?.nowPlayingInfoCenter.nowPlayingInfo = nil
            nowPlayingSession = nil
        }

        deinit { teardown() }
    }

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
