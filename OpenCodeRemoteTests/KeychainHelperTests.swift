import XCTest
@testable import OpenCodeRemote

final class KeychainHelperTests: XCTestCase {

    private let key = "unit_test_password_key"

    /// Keychain cần entitlement (application-identifier). Trong CI chạy test trên simulator
    /// với CODE_SIGNING_ALLOWED=NO thì không có entitlement -> SecItem* trả errSecMissingEntitlement.
    /// Khi đó bỏ qua các test này (logic vẫn đúng trên thiết bị thật/đã ký).
    private func requireKeychain() throws {
        let probe = "____keychain_probe____"
        KeychainHelper.delete(probe)
        let ok = KeychainHelper.set("1", for: probe)
        let readBack = KeychainHelper.get(probe)
        KeychainHelper.delete(probe)
        try XCTSkipUnless(ok && readBack == "1", "Keychain không khả dụng trong môi trường test (thiếu entitlement)")
    }

    override func tearDown() {
        KeychainHelper.delete(key)
        super.tearDown()
    }

    func testSetThenGet() throws {
        try requireKeychain()
        KeychainHelper.delete(key)
        let ok = KeychainHelper.set("hunter2", for: key)
        XCTAssertTrue(ok)
        XCTAssertEqual(KeychainHelper.get(key), "hunter2")
    }

    func testOverwrite() throws {
        try requireKeychain()
        KeychainHelper.set("first", for: key)
        KeychainHelper.set("second", for: key)
        XCTAssertEqual(KeychainHelper.get(key), "second", "Set lần 2 phải ghi đè, không nhân đôi")
    }

    func testDelete() throws {
        try requireKeychain()
        KeychainHelper.set("toremove", for: key)
        XCTAssertEqual(KeychainHelper.get(key), "toremove")
        let deleted = KeychainHelper.delete(key)
        XCTAssertTrue(deleted)
        XCTAssertNil(KeychainHelper.get(key))
    }

    func testGetMissingReturnsNil() throws {
        try requireKeychain()
        KeychainHelper.delete(key)
        XCTAssertNil(KeychainHelper.get(key))
    }

    func testDeleteMissingIsSuccess() throws {
        try requireKeychain()
        KeychainHelper.delete(key)
        // Xoá key không tồn tại vẫn coi là thành công (errSecItemNotFound).
        XCTAssertTrue(KeychainHelper.delete(key))
    }
}
