import Foundation

struct ServerConfig: Codable {
    /// IP/host của server (mặc định là IP Tailscale cũ, nhưng người dùng đổi được trong Cài đặt).
    var host: String
    var port: Int
    var username: String
    /// Mật khẩu KHÔNG mã hoá vào JSON/UserDefaults. Lưu riêng trong Keychain.
    var password: String

    /// Giá trị mặc định khi chưa cấu hình gì.
    static let defaultHost = "100.104.242.86"

    var baseURL: String {
        return "http://\(host):\(port)"
    }

    var authHeader: String? {
        guard !password.isEmpty else { return nil }
        let credentials = "\(username):\(password)"
        guard let data = credentials.data(using: .utf8) else { return nil }
        return "Basic \(data.base64EncodedString())"
    }

    static var `default`: ServerConfig {
        ServerConfig(
            host: defaultHost,
            port: 4096,
            username: "opencode",
            password: ""
        )
    }

    enum CodingKeys: String, CodingKey {
        case host, port, username
        // password cố tình KHÔNG nằm trong JSON.
    }

    init(host: String, port: Int, username: String, password: String) {
        self.host = host
        self.port = port
        self.username = username
        self.password = password
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Tương thích ngược: bản cũ không có "host" -> dùng default.
        self.host = (try? c.decode(String.self, forKey: .host)) ?? Self.defaultHost
        self.port = (try? c.decode(Int.self, forKey: .port)) ?? 4096
        self.username = (try? c.decode(String.self, forKey: .username)) ?? "opencode"
        self.password = ""
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(host, forKey: .host)
        try c.encode(port, forKey: .port)
        try c.encode(username, forKey: .username)
    }
}

extension ServerConfig {
    static let storageKey = "server_config"
    static let keychainPasswordKey = "server_password"

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
        // Mật khẩu lưu riêng trong Keychain.
        if password.isEmpty {
            KeychainHelper.delete(Self.keychainPasswordKey)
        } else {
            KeychainHelper.set(password, for: Self.keychainPasswordKey)
        }
    }

    static func load() -> ServerConfig {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              var config = try? JSONDecoder().decode(ServerConfig.self, from: data) else {
            // Lần đầu: không có config -> default, nhưng vẫn thử lấy mật khẩu Keychain (nếu có).
            var def = ServerConfig.default
            def.password = KeychainHelper.get(keychainPasswordKey) ?? ""
            return def
        }
        config.password = KeychainHelper.get(keychainPasswordKey) ?? ""
        return config
    }
}
