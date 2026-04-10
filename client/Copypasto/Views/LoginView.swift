import SwiftUI

struct LoginView: View {
    @EnvironmentObject var authService: AuthService

    @State private var email = ""
    @State private var password = ""
    @State private var isSignup = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 6) {
                Image(systemName: "clipboard.fill")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(.tint)

                Text("Copypasto")
                    .font(.system(size: 15, weight: .semibold))

                Text(isSignup ? "Create your account" : "Sign in to sync your clipboard")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 20)
            .padding(.bottom, 18)

            // Form fields
            VStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Email")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    TextField("name@example.com", text: $email)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.emailAddress)
                        .disableAutocorrection(true)
                        .controlSize(.large)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Password")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    SecureField("Enter password", text: $password)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(isSignup ? .newPassword : .password)
                        .controlSize(.large)
                }
            }
            .padding(.horizontal, 2)

            // Error message
            if let error = authService.errorMessage {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                    Text(error)
                        .font(.system(size: 11))
                }
                .foregroundStyle(.red)
                .padding(.top, 8)
                .multilineTextAlignment(.center)
            }

            // Submit button
            Button(action: submit) {
                Group {
                    if authService.isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text(isSignup ? "Create Account" : "Sign In")
                            .font(.system(size: 13, weight: .medium))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 14)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(email.isEmpty || password.isEmpty || authService.isLoading)
            .padding(.top, 14)

            // Toggle sign in / sign up
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isSignup.toggle()
                    authService.errorMessage = nil
                }
            } label: {
                Text(isSignup ? "Already have an account? **Sign In**" : "Don't have an account? **Sign Up**")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.top, 10)
            .padding(.bottom, 4)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .frame(width: 280)
    }

    private func submit() {
        Task {
            if isSignup {
                await authService.signup(email: email, password: password)
            } else {
                await authService.login(email: email, password: password)
            }
        }
    }
}
