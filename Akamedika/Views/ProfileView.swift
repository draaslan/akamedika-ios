import SwiftUI

struct ProfileView: View {
    var onLogout: () -> Void

    @State private var wpUser: WPUser?
    @State private var isLoading = true
    @State private var errorMessage: String?

    private let service = AuthService()

    var displayName: String {
        wpUser?.name ?? AuthService.cachedDisplayName ?? "Kullanıcı"
    }

    var email: String {
        AuthService.cachedEmail ?? "—"
    }

    var nicename: String {
        AuthService.cachedNicename ?? wpUser?.slug ?? "—"
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            if isLoading && wpUser == nil {
                ScrollView {
                    SkeletonProfile()
                        .padding(.top, 12)
                }
                .disabled(true)
            } else {
                ScrollView {
                    VStack(spacing: 20) {
                        header
                            .padding(.top, 12)

                        infoCard
                            .padding(.horizontal, 16)

                        if let description = wpUser?.description, !description.isEmpty {
                            aboutCard(description: description)
                                .padding(.horizontal, 16)
                        }

                        logoutButton
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                            .padding(.bottom, 24)
                    }
                }
                .refreshable {
                    await fetchMe()
                }
            }
        }
        .navigationTitle("Profil")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task {
            await fetchMe()
        }
    }

    private var header: some View {
        VStack(spacing: 14) {
            avatar
                .frame(width: 110, height: 110)
                .clipShape(Circle())
                .overlay(
                    Circle().strokeBorder(Theme.accentGradient, lineWidth: 3)
                )
                .shadow(color: Theme.accent.opacity(0.3), radius: 16, y: 6)

            VStack(spacing: 4) {
                Text(displayName)
                    .font(.title2.bold())
                    .foregroundStyle(Theme.textPrimary)
                if let roles = wpUser?.roles, let role = roles.first {
                    Text(role.capitalized)
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Theme.accentGradient)
                        .clipShape(Capsule())
                }
            }
        }
    }

    @ViewBuilder
    private var avatar: some View {
        if let urlString = wpUser?.bestAvatarURL, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                default:
                    avatarPlaceholder
                }
            }
        } else {
            avatarPlaceholder
        }
    }

    private var avatarPlaceholder: some View {
        ZStack {
            Theme.accentGradient
            Text(String(displayName.prefix(1)).uppercased())
                .font(.system(size: 44, weight: .bold))
                .foregroundStyle(.white)
        }
    }

    private var infoCard: some View {
        VStack(spacing: 0) {
            infoRow(icon: "envelope.fill", label: "E-posta", value: email)
            divider
            infoRow(icon: "person.fill", label: "Kullanıcı adı", value: nicename)
            if let url = wpUser?.url, !url.isEmpty {
                divider
                infoRow(icon: "link", label: "Web Sitesi", value: url)
            }
        }
        .card()
    }

    private func infoRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.surfaceElevated)
                Image(systemName: icon)
                    .foregroundStyle(Theme.accent)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
        }
        .padding(14)
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.border)
            .frame(height: 1)
            .padding(.leading, 68)
    }

    private func aboutCard(description: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Hakkında")
                .font(.caption.bold())
                .foregroundStyle(Theme.textSecondary)
                .textCase(.uppercase)
            Text(description)
                .font(.subheadline)
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var logoutButton: some View {
        Button(role: .destructive) {
            onLogout()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                Text("Çıkış Yap")
                    .font(.headline)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                LinearGradient(
                    colors: [Color(red: 0.90, green: 0.25, blue: 0.35), Color(red: 0.75, green: 0.15, blue: 0.28)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private func fetchMe() async {
        isLoading = true
        do {
            wpUser = try await service.fetchMe()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
