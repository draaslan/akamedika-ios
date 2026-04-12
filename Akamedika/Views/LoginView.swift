import SwiftUI

struct LoginView: View {
    @Bindable var viewModel: AuthViewModel

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 8) {
                Image(systemName: "graduationcap.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.tint)
                Text("Akamedika")
                    .font(.largeTitle.bold())
            }

            VStack(spacing: 16) {
                TextField("Kullanıcı adı veya e-posta", text: $viewModel.username)
                    .textContentType(.username)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .padding()
                    .background(.fill.tertiary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                SecureField("Şifre", text: $viewModel.password)
                    .textContentType(.password)
                    .padding()
                    .background(.fill.tertiary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.callout)
                    .multilineTextAlignment(.center)
            }

            Button {
                Task { await viewModel.login() }
            } label: {
                if viewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Giriş Yap")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(viewModel.isLoading)

            Spacer()
        }
        .padding(.horizontal, 24)
    }
}
