import Foundation

class OpenCodeAPI {
    private let config: ServerConfig
    private let session: URLSession
    
    init(config: ServerConfig) {
        self.config = config
        let urlConfig = URLSessionConfiguration.default
        urlConfig.timeoutIntervalForRequest = 30
        urlConfig.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: urlConfig)
    }
    
    private func makeRequest(path: String, method: String = "GET", body: Data? = nil, directory: String? = nil) -> URLRequest? {
        var fullPath = path
        // Gắn ?directory=... để server xử lý đúng thư mục/project của session.
        if let dir = directory, !dir.isEmpty {
            let encoded = dir.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? dir
            fullPath += (fullPath.contains("?") ? "&" : "?") + "directory=\(encoded)"
        }
        guard let url = URL(string: "\(config.baseURL)\(fullPath)") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let auth = config.authHeader {
            request.setValue(auth, forHTTPHeaderField: "Authorization")
        }
        request.httpBody = body
        return request
    }
    
    // MARK: - Health
    
    func checkHealth() async throws -> OCHealthResponse {
        guard let request = makeRequest(path: "/global/health") else {
            throw APIError.invalidURL
        }
        let (data, _) = try await session.data(for: request)
        return try JSONDecoder().decode(OCHealthResponse.self, from: data)
    }
    
    // MARK: - Sessions
    
    func listSessions() async throws -> [OCSession] {
        guard let request = makeRequest(path: "/session") else {
            throw APIError.invalidURL
        }
        let (data, _) = try await session.data(for: request)
        return try JSONDecoder().decode([OCSession].self, from: data)
    }

    /// Lấy danh sách project (mỗi thư mục mở trong opencode là 1 project).
    func listProjects() async throws -> [OCProject] {
        guard let request = makeRequest(path: "/project") else {
            throw APIError.invalidURL
        }
        let (data, _) = try await session.data(for: request)
        return try JSONDecoder().decode([OCProject].self, from: data)
    }

    /// Lấy session của 1 thư mục cụ thể.
    func listSessions(directory: String) async throws -> [OCSession] {
        let encoded = directory.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? directory
        guard let request = makeRequest(path: "/session?directory=\(encoded)") else {
            throw APIError.invalidURL
        }
        let (data, _) = try await session.data(for: request)
        return try JSONDecoder().decode([OCSession].self, from: data)
    }

    /// Gộp session từ TẤT CẢ project (giống danh sách opencode trên PC).
    func listAllSessions() async throws -> [OCSession] {
        let projects = (try? await listProjects()) ?? []
        // Lấy worktree hợp lệ (bỏ "global" worktree "/").
        let dirs = projects
            .compactMap { $0.worktree }
            .filter { $0 != "/" && !$0.isEmpty }

        var combined: [String: OCSession] = [:]

        // Luôn gồm session của thư mục mặc định.
        if let base = try? await listSessions() {
            for s in base { combined[s.id] = s }
        }

        // Lấy song song session của từng project.
        await withTaskGroup(of: [OCSession].self) { group in
            for dir in dirs {
                group.addTask { [weak self] in
                    (try? await self?.listSessions(directory: dir)) ?? []
                }
            }
            for await list in group {
                for s in list { combined[s.id] = s }
            }
        }

        // Ẩn session con (do agent/subagent sinh ra khi chạy task), giống bản desktop/TUI.
        // Chỉ giữ session gốc để danh sách khớp với máy tính.
        return Array(combined.values).filter { !$0.isChildSession }
    }
    
    func createSession(title: String?) async throws -> OCSession {
        guard let body = try? JSONEncoder().encode(["title": title]) else {
            throw APIError.encodingFailed
        }
        guard let request = makeRequest(path: "/session", method: "POST", body: body) else {
            throw APIError.invalidURL
        }
        let (data, _) = try await session.data(for: request)
        return try JSONDecoder().decode(OCSession.self, from: data)
    }
    
    func deleteSession(id: String) async throws -> Bool {
        guard let request = makeRequest(path: "/session/\(id)", method: "DELETE") else {
            throw APIError.invalidURL
        }
        let (data, _) = try await session.data(for: request)
        return (try? JSONDecoder().decode(Bool.self, from: data)) ?? true
    }
    
    func abortSession(id: String, directory: String? = nil) async throws -> Bool {
        guard let request = makeRequest(path: "/session/\(id)/abort", method: "POST", directory: directory) else {
            throw APIError.invalidURL
        }
        let (data, _) = try await session.data(for: request)
        return (try? JSONDecoder().decode(Bool.self, from: data)) ?? true
    }
    
    func getSessionStatus(directory: String? = nil) async throws -> [String: OCSessionStatus] {
        guard let request = makeRequest(path: "/session/status", directory: directory) else {
            throw APIError.invalidURL
        }
        let (data, _) = try await session.data(for: request)
        return try JSONDecoder().decode([String: OCSessionStatus].self, from: data)
    }
    
    func getTodos(sessionId: String, directory: String? = nil) async throws -> [OCTodo] {
        guard let request = makeRequest(path: "/session/\(sessionId)/todo", directory: directory) else {
            throw APIError.invalidURL
        }
        let (data, _) = try await session.data(for: request)
        return try JSONDecoder().decode([OCTodo].self, from: data)
    }
    
    // MARK: - Messages
    
    func listMessages(sessionId: String, directory: String? = nil) async throws -> [OCMessageWithParts] {
        guard let request = makeRequest(path: "/session/\(sessionId)/message", directory: directory) else {
            throw APIError.invalidURL
        }
        let (data, _) = try await session.data(for: request)
        return try JSONDecoder().decode([OCMessageWithParts].self, from: data)
    }
    
    func sendMessageAsync(sessionId: String, text: String, provider: String? = nil, model: String? = nil, imageDataURLs: [String] = [], agent: String? = nil, directory: String? = nil) async throws {
        var parts: [[String: Any]] = []
        if !text.isEmpty {
            parts.append(["type": "text", "text": text])
        }
        // Ảnh -> file part (server nhận type=file, mime, url data-base64)
        for url in imageDataURLs {
            parts.append([
                "type": "file",
                "mime": "image/jpeg",
                "filename": "image.jpg",
                "url": url
            ])
        }
        var bodyDict: [String: Any] = ["parts": parts]
        if let provider = provider, let model = model {
            bodyDict["model"] = ["providerID": provider, "modelID": model]
        }
        if let agent = agent {
            bodyDict["agent"] = agent
        }
        guard let body = try? JSONSerialization.data(withJSONObject: bodyDict) else {
            throw APIError.encodingFailed
        }
        guard let request = makeRequest(path: "/session/\(sessionId)/prompt_async", method: "POST", body: body, directory: directory) else {
            throw APIError.invalidURL
        }
        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 204 else {
            throw APIError.requestFailed
        }
    }
    
    // MARK: - Questions & Permissions
    /// Lấy các câu hỏi đang chờ trả lời.
    func listQuestions(directory: String? = nil) async throws -> [OCQuestionRequest] {
        guard let request = makeRequest(path: "/question", directory: directory) else {
            throw APIError.invalidURL
        }
        let (data, _) = try await session.data(for: request)
        return (try? JSONDecoder().decode([OCQuestionRequest].self, from: data)) ?? []
    }

    /// Trả lời câu hỏi: answers theo thứ tự câu hỏi, mỗi câu là mảng nhãn đã chọn.
    func replyQuestion(requestID: String, answers: [[String]], directory: String? = nil) async throws {
        let bodyDict: [String: Any] = ["answers": answers]
        guard let body = try? JSONSerialization.data(withJSONObject: bodyDict) else {
            throw APIError.encodingFailed
        }
        guard let request = makeRequest(path: "/question/\(requestID)/reply", method: "POST", body: body, directory: directory) else {
            throw APIError.invalidURL
        }
        _ = try await session.data(for: request)
    }

    /// Từ chối câu hỏi.
    func rejectQuestion(requestID: String, directory: String? = nil) async throws {
        guard let request = makeRequest(path: "/question/\(requestID)/reject", method: "POST", body: Data("{}".utf8), directory: directory) else {
            throw APIError.invalidURL
        }
        _ = try await session.data(for: request)
    }

    /// Lấy các yêu cầu quyền đang chờ.
    func listPermissions(directory: String? = nil) async throws -> [OCPermissionRequest] {
        guard let request = makeRequest(path: "/permission", directory: directory) else {
            throw APIError.invalidURL
        }
        let (data, _) = try await session.data(for: request)
        return (try? JSONDecoder().decode([OCPermissionRequest].self, from: data)) ?? []
    }

    /// Trả lời quyền: "once" | "always" | "reject".
    func replyPermission(requestID: String, reply: String, directory: String? = nil) async throws {
        let bodyDict: [String: Any] = ["reply": reply]
        guard let body = try? JSONSerialization.data(withJSONObject: bodyDict) else {
            throw APIError.encodingFailed
        }
        guard let request = makeRequest(path: "/permission/\(requestID)/reply", method: "POST", body: body, directory: directory) else {
            throw APIError.invalidURL
        }
        _ = try await session.data(for: request)
    }

        // MARK: - Skills & Commands

    /// Danh sách skill cài trên server (để agent biết và gọi).
    func listSkills() async throws -> [OCSkill] {
        guard let request = makeRequest(path: "/skill") else { throw APIError.invalidURL }
        let (data, _) = try await session.data(for: request)
        return (try? JSONDecoder().decode([OCSkill].self, from: data)) ?? []
    }

    /// Danh sách command (slash command) trên server.
    func listCommands() async throws -> [OCCommand] {
        guard let request = makeRequest(path: "/command") else { throw APIError.invalidURL }
        let (data, _) = try await session.data(for: request)
        return (try? JSONDecoder().decode([OCCommand].self, from: data)) ?? []
    }

    // MARK: - Providers & Models
    
    func listProviders() async throws -> [OCProvider] {        guard let request = makeRequest(path: "/provider") else {
            throw APIError.invalidURL
        }
        let (data, _) = try await session.data(for: request)
        let response = try JSONDecoder().decode(OCProviderListResponse.self, from: data)
        let rawProviders = response.all ?? response.providers ?? []

        // Chỉ hiển thị provider đã kết nối (giống opencode TUI). Nếu rỗng thì hiện tất cả.
        let connected = Set(response.connected ?? [])
        let filtered = connected.isEmpty
            ? rawProviders
            : rawProviders.filter { connected.contains($0.id) }

        return filtered.map { raw in
            let models = (raw.models ?? [:]).values.map { m in
                OCModel(id: m.id, name: m.name, description: m.description)
            }.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            return OCProvider(
                id: raw.id,
                name: raw.name ?? raw.id,
                models: models
            )
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    
    // MARK: - Config
    
    func updateConfig(provider: String, model: String) async throws {
        let bodyDict: [String: Any] = [
            "model": ["providerID": provider, "modelID": model]
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: bodyDict) else {
            throw APIError.encodingFailed
        }
        guard let request = makeRequest(path: "/config", method: "PATCH", body: body) else {
            throw APIError.invalidURL
        }
        let (_, _) = try await session.data(for: request)
    }
    
    // MARK: - Events (SSE)
    
    func eventStreamURL() -> URL? {
        URL(string: "\(config.baseURL)/event")
    }

    // MARK: - File download

    struct DownloadedFile {
        let data: Data
        let filename: String
    }

    /// Tải nội dung 1 file từ server. Trả về Data + tên file để lưu vào máy.
    func downloadFile(path: String, directory: String?) async throws -> DownloadedFile {
        let encodedPath = path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? path
        var pathStr = "/file/content?path=\(encodedPath)"
        if let dir = directory, !dir.isEmpty {
            let encodedDir = dir.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? dir
            pathStr += "&directory=\(encodedDir)"
        }
        guard let request = makeRequest(path: pathStr) else {
            throw APIError.invalidURL
        }
        let (data, _) = try await session.data(for: request)

        struct FileContent: Codable {
            let type: String?
            let content: String?
        }
        let fc = try JSONDecoder().decode(FileContent.self, from: data)

        let filename = (path as NSString).lastPathComponent
        let raw = fc.content ?? ""
        if fc.type == "binary", let decoded = Data(base64Encoded: raw) {
            return DownloadedFile(data: decoded, filename: filename)
        } else {
            return DownloadedFile(data: Data(raw.utf8), filename: filename)
        }
    }
    
    // MARK: - Errors
    
    enum APIError: LocalizedError {
        case invalidURL
        case encodingFailed
        case requestFailed
        case decodingFailed
        
        var errorDescription: String? {
            switch self {
            case .invalidURL: return "URL không hợp lệ"
            case .encodingFailed: return "Lỗi mã hóa dữ liệu"
            case .requestFailed: return "Yêu cầu thất bại"
            case .decodingFailed: return "Lỗi giải mã phản hồi"
            }
        }
    }
}
