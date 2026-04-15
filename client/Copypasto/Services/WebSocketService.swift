import AppKit
import Foundation
import Network

enum ConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case reconnecting(attempt: Int)
    case waitingForNetwork

    var isConnected: Bool { self == .connected }

    var statusLabel: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting…"
        case .connected: return "Connected"
        case .reconnecting: return "Reconnecting…"
        case .waitingForNetwork: return "No network"
        }
    }
}

protocol WebSocketServiceDelegate: AnyObject {
    func webSocketDidReceiveClipboardEntry(id: String, ciphertext: String, iv: String, contentLength: Int, createdAt: String)
    func webSocketDidChangeState(_ state: ConnectionState)
}

final class WebSocketService: NSObject {
    weak var delegate: WebSocketServiceDelegate?

    /// Called before reconnecting to obtain a fresh access token.
    /// Return the new token, or nil if refresh failed.
    var onRequestFreshToken: (() async -> String?)?

    private(set) var state: ConnectionState = .disconnected

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var accessToken: String?
    private var reconnectAttempt = 0
    private var pingTimer: Timer?
    private var reconnectTask: Task<Void, Never>?
    private var pongTimeoutTask: Task<Void, Never>?
    private var pendingPushIds = Set<String>()
    private var networkMonitor: NWPathMonitor?
    private var isNetworkAvailable = true

    /// Tracks whether the user intends to be connected (set by connect/disconnect).
    /// Drives auto-reconnect decisions after sleep, network changes, etc.
    private var shouldBeConnected = false

    override init() {
        super.init()
        startNetworkMonitor()
        observeSystemEvents()
    }

    deinit {
        networkMonitor?.cancel()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    // MARK: - Public API

    func connect(accessToken: String) {
        self.accessToken = accessToken
        shouldBeConnected = true
        reconnectAttempt = 0
        establishConnection()
    }

    func disconnect() {
        shouldBeConnected = false
        teardownConnection()
        updateState(.disconnected)
    }

    func updateToken(_ token: String) {
        self.accessToken = token
        if shouldBeConnected && state.isConnected {
            teardownConnection()
            reconnectAttempt = 0
            establishConnection()
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

    // MARK: - Network Monitoring

    private func startNetworkMonitor() {
        networkMonitor = NWPathMonitor()
        networkMonitor?.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.handleNetworkPathChange(isAvailable: path.status == .satisfied)
            }
        }
        networkMonitor?.start(queue: .global(qos: .utility))
    }

    private func handleNetworkPathChange(isAvailable: Bool) {
        let wasAvailable = isNetworkAvailable
        isNetworkAvailable = isAvailable

        guard shouldBeConnected else { return }

        if isAvailable && !wasAvailable {
            reconnectAttempt = 0
            scheduleReconnect(delay: 0.5)
        } else if !isAvailable {
            teardownConnection()
            updateState(.waitingForNetwork)
        }
    }

    // MARK: - System Events

    private func observeSystemEvents() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(systemWillSleep), name: NSWorkspace.willSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(systemDidWake), name: NSWorkspace.didWakeNotification, object: nil)
        center.addObserver(self, selector: #selector(screensDidWake), name: NSWorkspace.screensDidWakeNotification, object: nil)
    }

    @objc private func systemWillSleep() {
        guard shouldBeConnected else { return }
        teardownConnection()
    }

    @objc private func systemDidWake() {
        guard shouldBeConnected else { return }
        reconnectAttempt = 0
        scheduleReconnect(delay: 2.0)
    }

    @objc private func screensDidWake() {
        guard shouldBeConnected, !state.isConnected else { return }
        reconnectAttempt = 0
        scheduleReconnect(delay: 1.0)
    }

    // MARK: - Connection Lifecycle

    private func updateState(_ newState: ConnectionState) {
        guard state != newState else { return }
        state = newState
        delegate?.webSocketDidChangeState(newState)
    }

    private func teardownConnection() {
        reconnectTask?.cancel()
        reconnectTask = nil
        pongTimeoutTask?.cancel()
        pongTimeoutTask = nil
        pingTimer?.invalidate()
        pingTimer = nil
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
    }

    private func establishConnection() {
        guard let token = accessToken,
              let url = URL(string: "\(Constants.wsURL)?token=\(token)") else { return }

        guard isNetworkAvailable else {
            updateState(.waitingForNetwork)
            return
        }

        teardownConnection()
        updateState(reconnectAttempt == 0 ? .connecting : .reconnecting(attempt: reconnectAttempt))

        urlSession = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        webSocketTask = urlSession?.webSocketTask(with: url)
        webSocketTask?.resume()

        receiveMessage()
        startPingTimer()
    }

    private func handleDisconnect() {
        pingTimer?.invalidate()
        pingTimer = nil
        pongTimeoutTask?.cancel()
        pongTimeoutTask = nil
        webSocketTask = nil

        guard shouldBeConnected else {
            updateState(.disconnected)
            return
        }

        guard isNetworkAvailable else {
            updateState(.waitingForNetwork)
            return
        }

        scheduleReconnect()
    }

    private func scheduleReconnect(delay overrideDelay: TimeInterval? = nil) {
        reconnectTask?.cancel()

        let delay: TimeInterval
        if let provided = overrideDelay {
            delay = provided
        } else {
            let exponential = min(
                Constants.wsInitialReconnectDelay * pow(2.0, Double(reconnectAttempt)),
                Constants.wsMaxReconnectDelay
            )
            delay = exponential + Double.random(in: 0...(exponential * 0.3))
        }

        reconnectAttempt += 1
        updateState(.reconnecting(attempt: reconnectAttempt))

        reconnectTask = Task { [weak self] in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.establishConnection() }
        }
    }

    private func handleAuthExpired() {
        teardownConnection()

        guard shouldBeConnected else {
            updateState(.disconnected)
            return
        }

        updateState(.reconnecting(attempt: reconnectAttempt))

        Task { [weak self] in
            if let self, let refresher = self.onRequestFreshToken,
               let freshToken = await refresher() {
                await MainActor.run {
                    self.accessToken = freshToken
                    self.reconnectAttempt = 0
                    self.scheduleReconnect(delay: 0.5)
                }
            } else {
                await MainActor.run {
                    self?.scheduleReconnect()
                }
            }
        }
    }

    // MARK: - Messaging

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
                self.receiveMessage()
            case .failure:
                DispatchQueue.main.async { self.handleDisconnect() }
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
                DispatchQueue.main.async { [weak self] in
                    self?.handleAuthExpired()
                }
            }

        case "pong":
            DispatchQueue.main.async { [weak self] in
                self?.pongTimeoutTask?.cancel()
                self?.pongTimeoutTask = nil
            }

        default:
            break
        }
    }

    // MARK: - Ping / Pong

    private func startPingTimer() {
        pingTimer?.invalidate()
        pingTimer = Timer.scheduledTimer(withTimeInterval: Constants.wsPingInterval, repeats: true) { [weak self] _ in
            self?.sendPing()
        }
    }

    private func sendPing() {
        let message = #"{"type":"ping"}"#
        webSocketTask?.send(.string(message)) { [weak self] error in
            if error != nil {
                DispatchQueue.main.async { self?.handleDisconnect() }
                return
            }
        }

        pongTimeoutTask?.cancel()
        pongTimeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Constants.wsPongTimeout * 1_000_000_000))
            guard !Task.isCancelled else { return }
            DispatchQueue.main.async { self?.handleDisconnect() }
        }
    }
}

// MARK: - URLSessionWebSocketDelegate

extension WebSocketService: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        DispatchQueue.main.async { [weak self] in
            self?.reconnectAttempt = 0
            self?.updateState(.connected)
        }
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        DispatchQueue.main.async { [weak self] in
            self?.handleDisconnect()
        }
    }
}
