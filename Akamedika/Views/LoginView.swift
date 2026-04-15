import SwiftUI

struct LoginView: View {
    @Bindable var viewModel: AuthViewModel
    @FocusState private var focusedField: Field?

    enum Field { case username, password }

    var body: some View {
        ZStack {
            backgroundGradient.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 28) {
                    Spacer(minLength: 40)

                    Image("akamedika-logo-beyaz")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 72)
                        .padding(.bottom, 8)

                    VStack(spacing: 6) {
                        Text("Hoş geldiniz")
                            .font(.title2.bold())
                            .foregroundStyle(Theme.textPrimary)
                        Text("Öğrenmeye devam etmek için giriş yapın")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                    }

                    VStack(spacing: 14) {
                        inputField(
                            icon: "person.fill",
                            placeholder: "Kullanıcı adı veya e-posta",
                            text: $viewModel.username,
                            isSecure: false,
                            field: .username
                        )
                        .textContentType(.username)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                        inputField(
                            icon: "lock.fill",
                            placeholder: "Şifre",
                            text: $viewModel.password,
                            isSecure: true,
                            field: .password
                        )
                        .textContentType(.password)
                    }

                    if let error = viewModel.errorMessage {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.callout)
                            .multilineTextAlignment(.center)
                    }

                    Button {
                        focusedField = nil
                        Task { await viewModel.login() }
                    } label: {
                        ZStack {
                            if viewModel.isLoading {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text("Giriş Yap")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Theme.accentGradient)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .disabled(viewModel.isLoading)

                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 24)
            }
        }
    }

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [Theme.background, Color(red: 0.06, green: 0.08, blue: 0.14), Theme.background],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    @ViewBuilder
    private func inputField(icon: String, placeholder: String, text: Binding<String>, isSecure: Bool, field: Field) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 20)
            Group {
                if isSecure {
                    SecureField(placeholder, text: text)
                } else {
                    TextField(placeholder, text: text)
                }
            }
            .foregroundStyle(Theme.textPrimary)
            .focused($focusedField, equals: field)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    focusedField == field ? Theme.accent.opacity(0.6) : Theme.border,
                    lineWidth: 1
                )
        )
    }
}
