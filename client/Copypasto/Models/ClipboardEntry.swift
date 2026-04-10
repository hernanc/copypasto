import Foundation

struct ClipboardEntry: Identifiable, Codable {
    let id: String
    let ciphertext: String
    let iv: String
    let contentLength: Int
    let createdAt: String

    var preview: String?
}
