import Foundation

struct OCProvider: Codable, Identifiable {
    let id: String
    let name: String
    let models: [OCModel]
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case models
    }
}

struct OCModel: Codable, Identifiable {
    let id: String
    let name: String?
    let description: String?
    /// Model có hỗ trợ đính kèm ảnh/file không (field "attachment" từ opencode).
    let attachment: Bool?

    var displayName: String {
        name ?? id
    }

    /// True nếu model nhận được ảnh đầu vào.
    var supportsImages: Bool {
        attachment ?? false
    }
}

struct OCProviderListResponse: Codable {
    let all: [OCProviderRaw]?
    let providers: [OCProviderRaw]?
    let `default`: [String: String]?
    let connected: [String]?
}

struct OCProviderRaw: Codable {
    let id: String
    let name: String?
    let models: [String: OCModelRaw]?
}

struct OCModelRaw: Codable {
    let id: String
    let name: String?
    let description: String?
    let attachment: Bool?
}
