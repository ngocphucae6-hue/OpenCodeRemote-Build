import XCTest
@testable import OpenCodeRemote

final class ServerConfigTests: XCTestCase {

    /// Keychain cần entitlement; trong CI (simulator, không ký) SecItem* sẽ fail.
    /// Khi đó bỏ qua các test phụ thuộc Keychain (logic vẫn đúng trên thiết bị thật).
    private func requireKeychain() throws {
        let probe = "____sc_keychain_probe____"
        KeychainHelper.delete(probe)
        let ok = KeychainHelper.set("1", for: probe)
        let readBack = KeychainHelper.get(probe)
        KeychainHelper.delete(probe)
        try XCTSkipUnless(ok && readBack == "1", "Keychain không khả dụng trong môi trường test (thiếu entitlement)")
    }

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: ServerConfig.storageKey)
        KeychainHelper.delete(ServerConfig.keychainPasswordKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: ServerConfig.storageKey)
        KeychainHelper.delete(ServerConfig.keychainPasswordKey)
        super.tearDown()
    }

    func testBaseURL() {
        let cfg = ServerConfig(host: "10.0.0.5", port: 5000, username: "u", password: "")
        XCTAssertEqual(cfg.baseURL, "http://10.0.0.5:5000")
    }

    func testAuthHeaderNilWhenNoPassword() {
        let cfg = ServerConfig(host: "h", port: 1, username: "u", password: "")
        XCTAssertNil(cfg.authHeader)
    }

    func testAuthHeaderBasicEncoding() {
        let cfg = ServerConfig(host: "h", port: 1, username: "user", password: "pass")
        // "user:pass" base64 = dXNlcjpwYXNz
        XCTAssertEqual(cfg.authHeader, "Basic dXNlcjpwYXNz")
    }

    func testPasswordNotPersistedInJSON() throws {
        let cfg = ServerConfig(host: "h", port: 4096, username: "u", password: "secret")
        let data = try JSONEncoder().encode(cfg)
        let json = String(data: data, encoding: .utf8) ?? ""
        XCTAssertFalse(json.contains("secret"), "Mật khẩu KHÔNG được nằm trong JSON/UserDefaults")
        XCTAssertFalse(json.contains("password"))
    }

    func testSaveLoadRoundTripWithKeychainPassword() throws {
        try requireKeychain()
        let cfg = ServerConfig(host: "1.2.3.4", port: 7000, username: "alice", password: "topsecret")
        cfg.save()

        let loaded = ServerConfig.load()
        XCTAssertEqual(loaded.host, "1.2.3.4")
        XCTAssertEqual(loaded.port, 7000)
        XCTAssertEqual(loaded.username, "alice")
        XCTAssertEqual(loaded.password, "topsecret", "Mật khẩu phải lấy lại được từ Keychain")
    }

    func testEmptyPasswordClearsKeychain() throws {
        try requireKeychain()
        ServerConfig(host: "h", port: 1, username: "u", password: "willdelete").save()
        XCTAssertEqual(KeychainHelper.get(ServerConfig.keychainPasswordKey), "willdelete")

        ServerConfig(host: "h", port: 1, username: "u", password: "").save()
        XCTAssertNil(KeychainHelper.get(ServerConfig.keychainPasswordKey), "Lưu mật khẩu rỗng phải xoá khỏi Keychain")
    }

    func testBackwardCompatLegacyJSONWithoutHost() throws {
        // Bản cũ chỉ có port/username, không có host -> phải fallback defaultHost.
        let legacy = #"{"port":9000,"username":"legacy"}"#
        let cfg = try JSONDecoder().decode(ServerConfig.self, from: Data(legacy.utf8))
        XCTAssertEqual(cfg.host, ServerConfig.defaultHost)
        XCTAssertEqual(cfg.port, 9000)
        XCTAssertEqual(cfg.username, "legacy")
        XCTAssertEqual(cfg.password, "", "Decode không bao giờ chứa mật khẩu")
    }

    func testDefaultConfig() {
        let def = ServerConfig.default
        XCTAssertEqual(def.host, ServerConfig.defaultHost)
        XCTAssertEqual(def.port, 4096)
    }
}
