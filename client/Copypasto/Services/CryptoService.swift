import Foundation
import CryptoKit
import CommonCrypto

enum CryptoError: Error {
    case keyDerivationFailed
    case encryptionFailed
    case decryptionFailed
    case invalidData
}

enum CryptoService {

    /// Derive a 256-bit symmetric key from password + salt using PBKDF2-SHA256
    static func deriveKey(password: String, salt: Data) throws -> SymmetricKey {
        guard let passwordData = password.data(using: .utf8) else {
            throw CryptoError.keyDerivationFailed
        }

        var derivedKey = Data(count: 32) // 256 bits
        let result = derivedKey.withUnsafeMutableBytes { derivedKeyBytes in
            salt.withUnsafeBytes { saltBytes in
                passwordData.withUnsafeBytes { passwordBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.baseAddress?.assumingMemoryBound(to: Int8.self),
                        passwordData.count,
                        saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        Constants.pbkdf2Iterations,
                        derivedKeyBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        32
                    )
                }
            }
        }

        guard result == kCCSuccess else {
            throw CryptoError.keyDerivationFailed
        }

        return SymmetricKey(data: derivedKey)
    }

    /// Encrypt plaintext using AES-256-GCM with a fresh random nonce
    static func encrypt(plaintext: Data, key: SymmetricKey) throws -> (ciphertext: Data, iv: Data) {
        let nonce = AES.GCM.Nonce()
        guard let sealedBox = try? AES.GCM.seal(plaintext, using: key, nonce: nonce) else {
            throw CryptoError.encryptionFailed
        }

        // combined = nonce + ciphertext + tag, but we send nonce separately
        // sealedBox.ciphertext includes only the encrypted data (no tag)
        // We need ciphertext + tag together for decryption
        guard let combined = sealedBox.combined else {
            throw CryptoError.encryptionFailed
        }

        // combined layout: 12 bytes nonce | ciphertext | 16 bytes tag
        let ciphertextWithTag = combined.dropFirst(12) // skip nonce
        let iv = Data(nonce)

        return (ciphertext: Data(ciphertextWithTag), iv: iv)
    }

    /// Decrypt ciphertext using AES-256-GCM
    static func decrypt(ciphertext: Data, iv: Data, key: SymmetricKey) throws -> Data {
        guard let nonce = try? AES.GCM.Nonce(data: iv) else {
            throw CryptoError.invalidData
        }

        // Reconstruct the sealed box from nonce + ciphertext (which includes tag)
        let combined = iv + ciphertext
        guard let sealedBox = try? AES.GCM.SealedBox(combined: combined) else {
            throw CryptoError.invalidData
        }

        guard let plaintext = try? AES.GCM.open(sealedBox, using: key) else {
            throw CryptoError.decryptionFailed
        }

        return plaintext
    }
}
