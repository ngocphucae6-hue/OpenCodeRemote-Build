import Foundation
import Security

/// Lưu/đọc chuỗi bí mật (mật khẩu) trong Keychain.
///
/// Lưu ý quan trọng cho bản SIDELOAD (AltStore/Sideloadly/eSign):
/// Keychain cần entitlement `application-identifier`. Nhiều bản ký lại không có
/// entitlement đầy đủ -> SecItem* trả errSecMissingEntitlement (-34018) và mật khẩu
/// KHÔNG lưu được -> app gửi request thiếu Authorization -> server trả 401 -> "không kết nối được".
///
/// Vì vậy ta fallback sang UserDefaults khi Keychain không khả dụng. Đây là app điều khiển
/// từ xa qua Tailscale của chính người dùng nên đánh đổi này chấp nhận được để luôn kết nối được.
enum KeychainHelper {
    private static let service = "com.opencode.remote"
    private static func fallbackKey(_ key: String) -> String { "kc_fallback_\(key)" }

    @discardableResult
    static func set(_ value: String, for key: String) -> Bool {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        // Xoá bản cũ rồi thêm mới (tránh trùng).
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(attributes as CFDictionary, nil)

        if status == errSecSuccess {
            // Keychain OK -> dọn fallback cũ nếu có.
            UserDefaults.standard.removeObject(forKey: fallbackKey(key))
            return true
        }
        // Keychain fail (vd thiếu entitlement trên bản sideload) -> lưu UserDefaults.
        UserDefaults.standard.set(value, forKey: fallbackKey(key))
        return true
    }

    static func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess,
           let data = result as? Data,
           let value = String(data: data, encoding: .utf8) {
            return value
        }
        // Không có trong Keychain -> thử fallback UserDefaults.
        return UserDefaults.standard.string(forKey: fallbackKey(key))
    }

    @discardableResult
    static func delete(_ key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
        UserDefaults.standard.removeObject(forKey: fallbackKey(key))
        // Xoá là best-effort: dù Keychain thiếu entitlement (sideload/simulator) thì
        // fallback UserDefaults vẫn được dọn -> coi như đã xoá thành công.
        return true
    }
}
