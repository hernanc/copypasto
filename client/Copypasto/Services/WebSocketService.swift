import Foundation

protocol WebSocketServiceDelegate: AnyObject {
    func webSocketDidReceiveClipboardEntry(id: String, ciphertext: String, iv: String, contentLength: Int, createdAt: String)
    func webSocketDidDisconnect()
    func webSocketAuthExpired()
}

final class WebSocketService: NSObject {
    weak var delegate: WebSocketServiceDelegate?

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var accessToken: String?
    private var isConnected = false
    private var reconnectAttempt = 0
    private var maxReconnectDelay: TimeInterval = 30
    private var pingTimer: Timer?
    private var reconnectTask: Task<Void, Never>?
    private var pendingPushIds = Set<String>()

    func connect(accessToken: String) {
        self.accessToken = accessToken
        reconnectAttempt = 0
        establishConnection()
    }

    func disconnect() {
        reconnectTask?.cancel()
        reconnectTask = nil
        pingTimer?.invalidate()
        pingTimer = nil
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        isConnected = false
    }

    func updateToken(_ token: String) {
        self.accessToken = token
        // Reconnect with new token if currently connected
        if isConnected {
            disconnect()
            connect(accessToken: token)
        }
    }

    func pushClipboard(id: String, ciphertext: String, iv: String, contentLength: Int) {
        pendingPushIds.insert(id)

        let message: [String: Any] = [
            "type": "clipboard:push",
            "id": id,
            "payload": [
                "ciphertext": ciphertext,
                "iv": iv,
                "contentLength": contentLength,
            ],
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: message),
              let string = String(data: data, encoding: .utf8) else { return }

        webSocketTask?.send(.string(string)) { [weak self] error in
            if error != nil {
                self?.pendingPushIds.remove(id)
            }
        }
    }

    // MARK: - Private

    private func establishConnection() {
        guard let token = accessToken,
              let url = URL(string: "\(Constants.wsURL)?token=\(token)") else { return }

        urlSession = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        webSocketTask = urlSession?.webSocketTask(with: url)
        webSocketTask?.resume()
        isConnected = true

        receiveMessage()
        startPingTimer()
    }

    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            guard let self else { return }

            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleMessage(text)
                    }
                @unknown default:
                    break
                }
                self.receiveMessage() // Continue listening
            case .failure:
                self.handleDisconnect()
            }
        }
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return }

        switch type {
        case "clipboard:new":
            guard let id = json["id"] as? String,
                  let payload = json["payload"] as? [String: Any],
                  let ciphertext = payload["ciphertext"] as? String,
                  let iv = payload["iv"] as? String,
                  let contentLength = payload["contentLength"] as? Int,
                  let createdAt = json["createdAt"] as? String else { return }

            delegate?.webSocketDidReceiveClipboardEntry(
                id: id,
                ciphertext: ciphertext,
                iv: iv,
                contentLength: contentLength,
                createdAt: createdAt
            )

        case "clipboard:push:ack":
            if let id = json["id"] as? String {
                pendingPushIds.remove(id)
            }

        case "error":
            if let code = json["code"] as? String, code == "AUTH_EXPIRED" {
                delegate?.webSocketAuthExpired()
            }

        case "pong":
            break // Expected response to ping

        default:
            break
        }
    }

    private func handleDisconnect() {
        isConnected = false
        pingTimer?.invalidate()
        pingTimer = nil
        delegate?.webSocketDidDisconnect()
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        reconnectTask?.cancel()
        let delay = min(pow(2.0, Double(reconnectAttempt)), maxReconnectDelay)
        reconnectAttempt += 1

        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.establishConnection()
        }
    }

    private func startPingTimer() {
        pingTimer?.invalidate()
        pingTimer = Timer.scheduledTimer(withTimeInterval: Constants.wsPingInterval, repeats: true) { [weak self] _ in
            self?.sendPing()
        }
    }

    private func sendPing() {
        let message = #"{"type":"ping"}"#
        webSocketTask?.send(.string(message)) { _ in }
    }
}

extension WebSocketService: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        isConnected = true
        reconnectAttempt = 0
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        handleDisconnect()
    }
}
