import AppKit
import CryptoKit

final class ClipboardMonitor {
    var onClipboardChange: ((String) -> Void)?

    private var timer: Timer?
    private var lastChangeCount: Int
    private var ignoreNextChange = false

    init() {
        lastChangeCount = NSPasteboard.general.changeCount
    }

    func start() {
        timer = Timer.scheduledTimer(
            withTimeInterval: Constants.clipboardPollInterval,
            repeats: true
        ) { [weak self] _ in
            self?.checkForChanges()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Write text to the system clipboard from a remote update.
    /// Sets the ignore flag so we don't echo it back to the server.
    func writeFromRemote(_ text: String) {
        ignoreNextChange = true
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        lastChangeCount = pasteboard.changeCount
    }

    // MARK: - Private

    private func checkForChanges() {
        let currentCount = NSPasteboard.general.changeCount
        guard currentCount != lastChangeCount else { return }
        lastChangeCount = currentCount

        if ignoreNextChange {
            ignoreNextChange = false
            return
        }

        guard let string = NSPasteboard.general.string(forType: .string),
              !string.isEmpty else { return }

        // Enforce size limit
        guard string.utf8.count <= Constants.maxPlaintextSize else { return }

        onClipboardChange?(string)
    }
}
