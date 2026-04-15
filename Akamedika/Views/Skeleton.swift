import SwiftUI

struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.0), location: 0.0),
                            .init(color: .white.opacity(0.10), location: 0.45),
                            .init(color: .white.opacity(0.22), location: 0.5),
                            .init(color: .white.opacity(0.10), location: 0.55),
                            .init(color: .white.opacity(0.0), location: 1.0)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 2)
                    .offset(x: geo.size.width * phase)
                    .blendMode(.plusLighter)
                }
                .allowsHitTesting(false)
                .mask(content)
            )
            .onAppear {
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    phase = 1.2
                }
            }
    }
}

extension View {
    func shimmering() -> some View { modifier(ShimmerModifier()) }
}

struct SkeletonBlock: View {
    var height: CGFloat = 16
    var corner: CGFloat = 6
    var widthFraction: CGFloat = 1.0

    var body: some View {
        GeometryReader { geo in
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(Theme.surfaceElevated)
                .frame(width: geo.size.width * widthFraction, height: height)
        }
        .frame(height: height)
    }
}

struct SkeletonCourseCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(Theme.surfaceElevated)
                .aspectRatio(1, contentMode: .fill)

            VStack(alignment: .leading, spacing: 8) {
                SkeletonBlock(height: 14, widthFraction: 0.85)
                SkeletonBlock(height: 14, widthFraction: 0.6)
                SkeletonBlock(height: 10, widthFraction: 0.4)
                SkeletonBlock(height: 6, corner: 3)
            }
            .padding(12)
        }
        .card()
        .shimmering()
    }
}

struct SkeletonLessonRow: View {
    var body: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(Theme.surfaceElevated)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 8) {
                SkeletonBlock(height: 14, widthFraction: 0.85)
                SkeletonBlock(height: 10, widthFraction: 0.4)
            }
            Spacer()
        }
        .padding(14)
        .card()
        .shimmering()
    }
}

struct SkeletonProfile: View {
    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 14) {
                Circle()
                    .fill(Theme.surfaceElevated)
                    .frame(width: 110, height: 110)
                SkeletonBlock(height: 22, widthFraction: 0.5)
                SkeletonBlock(height: 14, widthFraction: 0.25)
            }
            .padding(.top, 20)

            VStack(spacing: 14) {
                ForEach(0..<3, id: \.self) { _ in
                    HStack(spacing: 14) {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Theme.surfaceElevated)
                            .frame(width: 40, height: 40)
                        VStack(alignment: .leading, spacing: 6) {
                            SkeletonBlock(height: 10, widthFraction: 0.25)
                            SkeletonBlock(height: 14, widthFraction: 0.7)
                        }
                        Spacer()
                    }
                    .padding(14)
                    .card()
                }
            }
            .padding(.horizontal, 16)
        }
        .shimmering()
    }
}

/// A smooth indeterminate pulse loader for small inline spots.
struct PulseLoader: View {
    var message: String? = nil
    @State private var animate = false

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .stroke(Theme.accent.opacity(0.5), lineWidth: 2)
                        .frame(width: 60, height: 60)
                        .scaleEffect(animate ? 1.6 : 0.6)
                        .opacity(animate ? 0 : 0.8)
                        .animation(
                            .easeOut(duration: 1.8)
                                .repeatForever(autoreverses: false)
                                .delay(Double(i) * 0.5),
                            value: animate
                        )
                }
                Circle()
                    .fill(Theme.accentGradient)
                    .frame(width: 28, height: 28)
                    .shadow(color: Theme.accent.opacity(0.6), radius: 12)
            }
            .frame(width: 100, height: 100)

            if let message {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .onAppear { animate = true }
    }
}
