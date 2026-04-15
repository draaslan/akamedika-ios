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
struct FillingAsyncImage<Placeholder: View>: View {
    let url: URL?
    @ViewBuilder var placeholder: () -> Placeholder

    var body: some View {
        GeometryReader { geo in
            Group {
                if let url {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: geo.size.width, height: geo.size.height)
                        default:
                            placeholder()
                        }
                    }
                } else {
                    placeholder()
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
    }
}

