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
    
    var displayName: String {
        name ?? id
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
}
