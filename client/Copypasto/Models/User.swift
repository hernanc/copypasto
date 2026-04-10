import Foundation

struct AuthResponse: Codable {
    let userId: String
    let accessToken: String
    let refreshToken: String
    let encryptionSalt: String
}

struct TokenResponse: Codable {
    let accessToken: String
    let refreshToken: String
}

struct ClipboardListResponse: Codable {
    let items: [ClipboardEntry]
}

struct ErrorResponse: Codable {
    let error: String
}
