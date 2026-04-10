import Foundation

/// Stores credentials in a file within the app's Application Support directory.
/// This avoids macOS Keychain password prompts that occur with ad-hoc signed
/// development builds. The storage file is readable only by the current user.
enum KeychainService {

    private static var storageURL: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let dir = appSupport.appendingPathComponent("Copypasto", isDirectory: true)

        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(
                at: dir,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }

        return dir.appendingPathComponent("credentials.json")
    }

    private static func readStore() -> [String: String] {
        guard let data = try? Data(contentsOf: storageURL),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return dict
    }

    private static func writeStore(_ store: [String: String]) {
        guard let data = try? JSONEncoder().encode(store) else { return }
        try? data.write(to: storageURL, options: [.atomic, .completeFileProtection])

        // Ensure the file is only readable by the current user
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: storageURL.path
        )
    }

    @discardableResult
    static func save(key: String, data: Data) -> Bool {
        guard let string = String(data: data, encoding: .utf8) else { return false }
        return save(key: key, string: string)
    }

    @discardableResult
    static func save(key: String, string: String) -> Bool {
        var store = readStore()
        store[key] = string
        writeStore(store)
        return true
    }

    static func load(key: String) -> Data? {
        guard let string = loadString(key: key) else { return nil }
        return string.data(using: .utf8)
    }

    static func loadString(key: String) -> String? {
        let store = readStore()
        return store[key]
    }

    @discardableResult
    static func delete(key: String) -> Bool {
        var store = readStore()
        store.removeValue(forKey: key)
        writeStore(store)
        return true
    }

    static func deleteAll() {
        delete(key: Constants.keychainAccessTokenKey)
        delete(key: Constants.keychainRefreshTokenKey)
        delete(key: Constants.keychainEncryptionSaltKey)
    }
}
