import Foundation
import SwiftUI
import CryptoKit

@MainActor
final class AuthService: ObservableObject {
    @Published var isLoggedIn = false
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var clipboardEntries: [ClipboardEntry] = []
    @Published var connectionState: ConnectionState = .disconnected

    private let network = NetworkService()
    private let webSocket = WebSocketService()
    private let clipboardMonitor = ClipboardMonitor()
    private var encryptionKey: SymmetricKey?
    private var userId: String?

    init() {
        webSocket.delegate = self

        webSocket.onRequestFreshToken = { [weak self] in
            guard let self else { return nil }
            return await self.network.refreshAccessToken()
        }

        clipboardMonitor.onClipboardChange = { [weak self] text in
            Task { @MainActor in
                self?.handleLocalClipboardChange(text)
            }
        }

        // Check if we have a stored refresh token to auto-login
        if let refreshToken = KeychainService.loadString(key: Constants.keychainRefreshTokenKey) {
            Task { await attemptAutoLogin(refreshToken: refreshToken) }
        }
    }

    func login(email: String, password: String) async {
        isLoading = true
        errorMessage = nil

        do {
            let response = try await network.login(email: email, password: password)
            try setupSession(response: response, password: password)
        } catch let error as NetworkError {
            errorMessage = describeError(error)
        } catch {
            errorMessage = "Login failed: \(error.localizedDescription)"
        }

        isLoading = false
    }

    func signup(email: String, password: String) async {
        isLoading = true
        errorMessage = nil

        do {
            let response = try await network.signup(email: email, password: password)
            try setupSession(response: response, password: password)
        } catch let error as NetworkError {
            errorMessage = describeError(error)
        } catch {
            errorMessage = "Signup failed: \(error.localizedDescription)"
        }

        isLoading = false
    }

    func logout() {
        clipboardMonitor.stop()
        webSocket.disconnect()
        KeychainService.deleteAll()
        encryptionKey = nil
        userId = nil
        clipboardEntries = []
        isLoggedIn = false
    }

    func copyEntry(_ entry: ClipboardEntry) {
        guard let key = encryptionKey,
              let ciphertextData = Data(base64Encoded: entry.ciphertext),
              let ivData = Data(base64Encoded: entry.iv) else { return }

        do {
            let plaintext = try CryptoService.decrypt(ciphertext: ciphertextData, iv: ivData, key: key)
            if let text = String(data: plaintext, encoding: .utf8) {
                clipboardMonitor.writeFromRemote(text)
            }
        } catch {
            // Decryption failed — entry may be corrupted or key mismatch
        }
    }

    // MARK: - Private

    private func setupSession(response: AuthResponse, password: String) throws {
        guard let saltData = Data(base64Encoded: response.encryptionSalt) else {
            throw CryptoError.invalidData
        }

        let key = try CryptoService.deriveKey(password: password, salt: saltData)
        self.encryptionKey = key
        self.userId = response.userId

        // Store tokens in Keychain
        KeychainService.save(key: Constants.keychainAccessTokenKey, string: response.accessToken)
        KeychainService.save(key: Constants.keychainRefreshTokenKey, string: response.refreshToken)
        KeychainService.save(key: Constants.keychainEncryptionSaltKey, string: response.encryptionSalt)

        // Configure network service with tokens
        Task {
            await network.configure(
                accessToken: response.accessToken,
                refreshToken: response.refreshToken,
                onTokensRefreshed: { [weak self] access, refresh in
                    await self?.handleTokensRefreshed(access: access, refresh: refresh)
                },
                onAuthFailure: { [weak self] in
                    await MainActor.run { self?.logout() }
                }
            )
        }

        // Connect WebSocket
        webSocket.connect(accessToken: response.accessToken)

        // Start clipboard monitoring
        clipboardMonitor.start()

        isLoggedIn = true

        // Load clipboard history
        Task { await loadClipboardHistory() }
    }

    private func attemptAutoLogin(refreshToken: String) async {
        // We can refresh the token but we can't derive the encryption key without the password.
        // The user must log in with their password to derive the key.
        // So auto-login just means we know the user had an account — we still show the login form.
    }

    private func loadClipboardHistory() async {
        guard let key = encryptionKey else { return }

        do {
            let response = try await network.getClipboardHistory()
            clipboardEntries = response.items.map { entry in
                var enriched = entry
                if let ciphertextData = Data(base64Encoded: entry.ciphertext),
                   let ivData = Data(base64Encoded: entry.iv),
                   let plaintext = try? CryptoService.decrypt(ciphertext: ciphertextData, iv: ivData, key: key),
                   let text = String(data: plaintext, encoding: .utf8) {
                    enriched.preview = String(text.prefix(100))
                }
                return enriched
            }
        } catch {
            // Silently fail — history is not critical
        }
    }

    private func handleLocalClipboardChange(_ text: String) {
        guard let key = encryptionKey else { return }

        do {
            let plaintext = Data(text.utf8)
            let (ciphertext, iv) = try CryptoService.encrypt(plaintext: plaintext, key: key)
            let id = UUID().uuidString

            webSocket.pushClipboard(
                id: id,
                ciphertext: ciphertext.base64EncodedString(),
                iv: iv.base64EncodedString(),
                contentLength: plaintext.count
            )

            // Add to local history
            let entry = ClipboardEntry(
                id: id,
                ciphertext: ciphertext.base64EncodedString(),
                iv: iv.base64EncodedString(),
                contentLength: plaintext.count,
                createdAt: ISO8601DateFormatter().string(from: Date()),
                preview: String(text.prefix(100))
            )
            clipboardEntries.insert(entry, at: 0)
            if clipboardEntries.count > 5 {
                clipboardEntries = Array(clipboardEntries.prefix(5))
            }
        } catch {
            // Encryption failed — skip this clipboard entry
        }
    }

    private func handleTokensRefreshed(access: String, refresh: String) {
        KeychainService.save(key: Constants.keychainAccessTokenKey, string: access)
        KeychainService.save(key: Constants.keychainRefreshTokenKey, string: refresh)
        webSocket.updateToken(access)
    }

    private func describeError(_ error: NetworkError) -> String {
        switch error {
        case .unauthorized:
            return "Invalid email or password"
        case .conflict(let msg):
            return msg
        case .serverError(let msg):
            return msg
        case .invalidURL:
            return "Invalid server URL"
        case .decodingError:
            return "Unexpected server response"
        case .noData:
            return "No response from server"
        }
    }
}

// MARK: - WebSocketServiceDelegate

extension AuthService: WebSocketServiceDelegate {
    nonisolated func webSocketDidReceiveClipboardEntry(id: String, ciphertext: String, iv: String, contentLength: Int, createdAt: String) {
        Task { @MainActor in
            guard let key = encryptionKey else { return }

            let entry = ClipboardEntry(
                id: id,
                ciphertext: ciphertext,
                iv: iv,
                contentLength: contentLength,
                createdAt: createdAt,
                preview: nil
            )

            // Decrypt and write to clipboard
            if let ciphertextData = Data(base64Encoded: ciphertext),
               let ivData = Data(base64Encoded: iv),
               let plaintext = try? CryptoService.decrypt(ciphertext: ciphertextData, iv: ivData, key: key),
               let text = String(data: plaintext, encoding: .utf8) {

                clipboardMonitor.writeFromRemote(text)

                var enriched = entry
                enriched.preview = String(text.prefix(100))

                clipboardEntries.insert(enriched, at: 0)
                if clipboardEntries.count > 5 {
                    clipboardEntries = Array(clipboardEntries.prefix(5))
                }
            }
        }
    }

    nonisolated func webSocketDidChangeState(_ state: ConnectionState) {
        Task { @MainActor in
            self.connectionState = state
        }
    }
}
