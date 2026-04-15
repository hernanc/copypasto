import Foundation

enum NetworkError: Error {
    case invalidURL
    case unauthorized
    case conflict(String)
    case serverError(String)
    case decodingError
    case noData
}

actor NetworkService {
    private var accessToken: String?
    private var refreshToken: String?
    private var onTokensRefreshed: ((String, String) async -> Void)?
    private var onAuthFailure: (() async -> Void)?

    func configure(
        accessToken: String,
        refreshToken: String,
        onTokensRefreshed: @escaping (String, String) async -> Void,
        onAuthFailure: @escaping () async -> Void
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.onTokensRefreshed = onTokensRefreshed
        self.onAuthFailure = onAuthFailure
    }

    func updateTokens(access: String, refresh: String) {
        self.accessToken = access
        self.refreshToken = refresh
    }

    func clearTokens() {
        self.accessToken = nil
        self.refreshToken = nil
    }

    // MARK: - Auth endpoints (no auth header needed)

    func signup(email: String, password: String) async throws -> AuthResponse {
        let body = ["email": email, "password": password]
        return try await post(path: "/auth/signup", body: body, authenticated: false)
    }

    func login(email: String, password: String) async throws -> AuthResponse {
        let body = ["email": email, "password": password]
        return try await post(path: "/auth/login", body: body, authenticated: false)
    }

    func refreshAccessToken() async -> String? {
        do {
            if try await attemptTokenRefresh() {
                return self.accessToken
            }
        } catch {}
        return nil
    }

    // MARK: - Clipboard endpoints

    func getClipboardHistory() async throws -> ClipboardListResponse {
        return try await get(path: "/clipboard", authenticated: true)
    }

    // MARK: - Private helpers

    private func get<T: Decodable>(path: String, authenticated: Bool) async throws -> T {
        var request = try makeRequest(path: path, method: "GET")
        if authenticated {
            guard let token = accessToken else { throw NetworkError.unauthorized }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 401, authenticated {
            if try await attemptTokenRefresh() {
                return try await get(path: path, authenticated: true)
            }
            throw NetworkError.unauthorized
        }

        return try handleResponse(data: data, response: response)
    }

    private func post<T: Decodable>(path: String, body: Encodable, authenticated: Bool) async throws -> T {
        var request = try makeRequest(path: path, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        if authenticated {
            guard let token = accessToken else { throw NetworkError.unauthorized }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 401, authenticated {
            if try await attemptTokenRefresh() {
                return try await post(path: path, body: body, authenticated: true)
            }
            throw NetworkError.unauthorized
        }

        return try handleResponse(data: data, response: response)
    }

    private func makeRequest(path: String, method: String) throws -> URLRequest {
        guard let url = URL(string: Constants.apiBaseURL + path) else {
            throw NetworkError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        return request
    }

    private func handleResponse<T: Decodable>(data: Data, response: URLResponse) throws -> T {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.serverError("Invalid response")
        }

        switch httpResponse.statusCode {
        case 200...201:
            return try JSONDecoder().decode(T.self, from: data)
        case 401:
            throw NetworkError.unauthorized
        case 409:
            let error = try? JSONDecoder().decode(ErrorResponse.self, from: data)
            throw NetworkError.conflict(error?.error ?? "Conflict")
        default:
            let error = try? JSONDecoder().decode(ErrorResponse.self, from: data)
            throw NetworkError.serverError(error?.error ?? "Server error (\(httpResponse.statusCode))")
        }
    }

    private func attemptTokenRefresh() async throws -> Bool {
        guard let refreshToken = self.refreshToken else { return false }

        let body = ["refreshToken": refreshToken]
        var request = try makeRequest(path: "/auth/refresh", method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            await onAuthFailure?()
            return false
        }

        let tokens = try JSONDecoder().decode(TokenResponse.self, from: data)
        self.accessToken = tokens.accessToken
        self.refreshToken = tokens.refreshToken
        await onTokensRefreshed?(tokens.accessToken, tokens.refreshToken)
        return true
    }
}

// Make dictionary Encodable-friendly
extension Dictionary: @retroactive Encodable where Key == String, Value == String {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self)
    }
}
