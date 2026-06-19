import Foundation

// MARK: - Time

struct OCTime: Codable, Equatable, Hashable {
    let created: Double?
    let updated: Double?
    let completed: Double?
    let start: Double?
    let end: Double?
}

// MARK: - Session

struct OCSession: Codable, Identifiable, Equatable, Hashable {
    let id: String
    let title: String?
    let slug: String?
    let directory: String?
    /// Session cha (nếu có). Session con do agent/subagent sinh ra khi chạy task.
    /// Bản desktop/TUI ẩn các session con này, chỉ hiện session gốc.
    let parentID: String?
    let model: OCSessionModel?
    let agent: String?
    let time: OCTime?

    enum CodingKeys: String, CodingKey {
        case id, title, slug, directory, parentID, model, agent, time
    }

    /// Init tường minh với parentID mặc định nil (giữ tương thích với call site/test cũ).
    init(id: String, title: String?, slug: String?, directory: String?,
         parentID: String? = nil, model: OCSessionModel?, agent: String?, time: OCTime?) {
        self.id = id
        self.title = title
        self.slug = slug
        self.directory = directory
        self.parentID = parentID
        self.model = model
        self.agent = agent
        self.time = time
    }

    /// True nếu đây là session con (được agent tạo ra), nên ẩn khỏi danh sách chính.
    var isChildSession: Bool {
        guard let p = parentID else { return false }
        return !p.isEmpty
    }

    var displayTitle: String {
        if let t = title, !t.isEmpty { return t }
        return "Phiên #\(id.prefix(8))"
    }

    // Mốc thời gian mới nhất (epoch ms) để sắp xếp / hiển thị
    var lastActivity: Double {
        time?.updated ?? time?.created ?? 0
    }

    var timeLabel: String? {
        let ms = time?.updated ?? time?.created
        guard let ms = ms, ms > 0 else { return nil }
        let date = Date(timeIntervalSince1970: ms / 1000)
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "vi_VN")
        fmt.dateFormat = "dd/MM HH:mm"
        return fmt.string(from: date)
    }

    var modelLabel: String? {
        guard let m = model else { return nil }
        return m.id ?? m.modelID
    }
}

struct OCSessionModel: Codable, Equatable, Hashable {
    let id: String?
    let modelID: String?
    let providerID: String?
    let variant: String?
}

// MARK: - Project

struct OCProject: Codable, Identifiable {
    let id: String
    let worktree: String?
    let time: OCTime?
}

// MARK: - Message

struct OCMessage: Codable, Identifiable {
    let id: String?
    let role: String
    let sessionID: String?
    let time: OCTime?
    let providerID: String?
    let modelID: String?
    let agent: String?
    let error: OCMessageError?

    enum CodingKeys: String, CodingKey {
        case id, role, sessionID, time, providerID, modelID, agent, error
    }

    var identifier: String {
        id ?? UUID().uuidString
    }
}

struct OCMessageError: Codable {
    let name: String?
    let data: OCMessageErrorData?
}

struct OCMessageErrorData: Codable {
    let message: String?
    let statusCode: Int?
}

// MARK: - Part

struct OCToolState: Codable {
    let status: String?
    let title: String?
    let output: String?
    let input: OCJSONValue?
    let time: OCTime?
    let metadata: OCToolMetadata?

    enum CodingKeys: String, CodingKey {
        case status, title, output, input, time, metadata
    }
}

struct OCToolMetadata: Codable {
    let filepath: String?
}

struct OCPart: Codable, Identifiable {
    var id: String?
    var type: String
    var text: String?
    var tool: String?
    var callID: String?
    var state: OCToolState?
    var mime: String?
    var filename: String?
    var url: String?

    enum CodingKeys: String, CodingKey {
        case id, type, text, tool, callID, state, mime, filename, url
    }

    var stableID: String { id ?? "\(type)_\(callID ?? "")" }

    /// So sánh nội dung hiển thị để biết part có thực sự đổi không (tránh render lại thừa,
    /// nhưng vẫn bắt đổi state.status/output/title để tool không bị "đơ" trạng thái cũ).
    func isContentEqual(to other: OCPart) -> Bool {
        return id == other.id
            && type == other.type
            && text == other.text
            && tool == other.tool
            && callID == other.callID
            && mime == other.mime
            && filename == other.filename
            && url == other.url
            && state?.status == other.state?.status
            && state?.title == other.state?.title
            && state?.output == other.state?.output
    }
}

struct OCMessageWithParts: Codable, Identifiable {
    var info: OCMessage
    var parts: [OCPart]

    /// Fallback ổn định cho 1 instance: nếu server trả id = nil thì vẫn giữ NGUYÊN
    /// một id trong suốt vòng đời instance (tránh sinh UUID mới mỗi lần truy cập .id,
    /// khiến SwiftUI tưởng là item khác và dựng lại view liên tục).
    private let localStableID = UUID().uuidString

    var id: String { info.id ?? localStableID }

    enum CodingKeys: String, CodingKey {
        case info, parts
    }

    /// So sánh nội dung hiển thị (không tính localStableID) để biết có cần render lại không.
    func isContentEqual(to other: OCMessageWithParts) -> Bool {
        guard info.id == other.info.id,
              info.role == other.info.role,
              parts.count == other.parts.count else { return false }
        for (a, b) in zip(parts, other.parts) {
            if !a.isContentEqual(to: b) { return false }
        }
        return true
    }
}

// MARK: - Question (agent hỏi người dùng để chọn đáp án)

struct OCQuestionOption: Codable, Identifiable, Hashable {
    let label: String
    let description: String?

    var id: String { label }
}

struct OCQuestionInfo: Codable, Identifiable, Hashable {
    let question: String
    let header: String?
    let options: [OCQuestionOption]
    let multiple: Bool?
    let custom: Bool?

    var id: String { question }
}

struct OCQuestionRequest: Codable, Identifiable {
    let id: String
    let sessionID: String?
    let questions: [OCQuestionInfo]
}

// MARK: - Skill & Command (để agent tự biết và gọi)

struct OCSkill: Codable, Identifiable, Hashable {
    let name: String
    let description: String?

    var id: String { name }
}

struct OCCommand: Codable, Identifiable, Hashable {
    let name: String
    let description: String?

    var id: String { name }
}

// MARK: - Permission (agent xin phép chạy tool)

struct OCPermissionRequest: Codable, Identifiable {
    let id: String
    let sessionID: String?
    let permission: String?
    let patterns: [String]?

    enum CodingKeys: String, CodingKey {
        case id, sessionID, permission, patterns
    }

    var displayText: String {
        permission ?? "Yêu cầu quyền"
    }
}

// MARK: - Status

struct OCSessionStatus: Codable {
    let status: String?
}

struct OCHealthResponse: Codable {
    let healthy: Bool
    let version: String?
}

// MARK: - Todo

struct OCTodo: Codable, Identifiable {
    let id: String?
    let content: String?
    let status: String?
    let priority: String?

    var identifier: String {
        id ?? UUID().uuidString
    }
}

// MARK: - Flexible JSON value (cho tool input tuỳ ý)

enum OCJSONValue: Codable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: OCJSONValue])
    case array([OCJSONValue])
    case null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let v = try? c.decode(Bool.self) {
            self = .bool(v)
        } else if let v = try? c.decode(Double.self) {
            self = .number(v)
        } else if let v = try? c.decode(String.self) {
            self = .string(v)
        } else if let v = try? c.decode([String: OCJSONValue].self) {
            self = .object(v)
        } else if let v = try? c.decode([OCJSONValue].self) {
            self = .array(v)
        } else {
            self = .null
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }

    // Trình bày gọn cho UI
    var displayString: String {
        switch self {
        case .string(let v): return v
        case .number(let v):
            if v == v.rounded() { return String(Int(v)) }
            return String(v)
        case .bool(let v): return v ? "true" : "false"
        case .null: return ""
        case .array(let arr):
            return arr.map { $0.displayString }.joined(separator: ", ")
        case .object(let obj):
            return obj.map { "\($0.key): \($0.value.displayString)" }
                .sorted()
                .joined(separator: ", ")
        }
    }
}
