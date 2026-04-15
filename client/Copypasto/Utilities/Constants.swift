import Foundation

enum Constants {
    static let apiBaseURL = "https://api.copypasto.com/api"
    static let wsURL = "wss://api.copypasto.com/ws"
    static let keychainService = "com.copypasto"
    static let keychainAccessTokenKey = "accessToken"
    static let keychainRefreshTokenKey = "refreshToken"
    static let keychainEncryptionSaltKey = "encryptionSalt"
    static let clipboardPollInterval: TimeInterval = 0.5
    static let wsPingInterval: TimeInterval = 30
    static let wsInitialReconnectDelay: TimeInterval = 1
    static let wsMaxReconnectDelay: TimeInterval = 30
    static let wsPongTimeout: TimeInterval = 10
    static let maxPlaintextSize = 1_048_576 // 1MB
    static let pbkdf2Iterations: UInt32 = 600_000
}
