import Foundation
import LocalAuthentication
import Security

enum KeychainReader {
    /// Held by every `read`. `SecKeychainSetUserInteractionAllowed` is one switch for the whole
    /// process, so without this a silent read's "no dialog" window on one thread could overlap a
    /// prompting read on another and swallow the dialog the user just asked for. `genericPassword`
    /// (Kannu's own items, read on the main thread too) does not take it, so the main thread never
    /// waits behind a dialog another thread is showing.
    private static let crossAppReadLock = NSLock()

    /// Kannu's own items. Never toggles the interaction switch.
    static func genericPassword(service: String, account: String? = nil) -> String? {
        copyPassword(passwordQuery(service: service, account: account)).value
    }

    /// Reads another app's generic password and reports the raw status, so callers can tell "item
    /// missing" apart from "item exists but macOS wants the user to approve access".
    ///
    /// `allowInteraction: false` must not show a dialog. Codex's "Codex Auth" and cursor-agent's
    /// "cursor-access-token" are file-based login-keychain items, and that keychain ignores
    /// `kSecUseAuthenticationUI` and `kSecUseAuthenticationContext`: Apple's `SecItem.cpp` hands the
    /// query to the legacy path, which never reads either key and fetches the secret with
    /// `SecKeychainItemCopyContent`, raising the access dialog whenever user interaction is allowed
    /// (the SDK's `SecItem.h` says so too: "Legacy keychain items will still activate UI if needed").
    /// Only `SecKeychainSetUserInteractionAllowed(false)` stops that, so the silent read turns it off
    /// for the one call and puts the previous value back. A protected item then fails with
    /// `errSecInteractionNotAllowed`, which `needsUserApproval` recognises. The LAContext covers an
    /// item in the data-protection keychain the same way. Deprecated API: Apple's DTS still points
    /// to it when the item is not your own.
    static func read(
        service: String,
        account: String? = nil,
        allowInteraction: Bool = true
    ) -> (value: String?, status: OSStatus) {
        var query = passwordQuery(service: service, account: account)
        crossAppReadLock.lock()
        defer { crossAppReadLock.unlock() }
        guard !allowInteraction else { return copyPassword(query) }

        let context = LAContext()
        context.interactionNotAllowed = true
        query[kSecUseAuthenticationContext as String] = context
        var wasAllowed: DarwinBoolean = true
        let knewPrevious = SecKeychainGetUserInteractionAllowed(&wasAllowed) == errSecSuccess
        SecKeychainSetUserInteractionAllowed(false)
        defer { SecKeychainSetUserInteractionAllowed(knewPrevious ? wasAllowed.boolValue : true) }
        return copyPassword(query)
    }

    private static func passwordQuery(service: String, account: String?) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        if let account { query[kSecAttrAccount as String] = account } // only filter by account when given
        return query
    }

    private static func copyPassword(_ query: [String: Any]) -> (value: String?, status: OSStatus) {
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return (nil, status) }
        return (String(data: data, encoding: .utf8), status)
    }

    /// True when the item is present but macOS blocked the read pending user approval.
    /// `errSecAuthFailed` is deliberately excluded: it means the item itself is broken
    /// (wrong ACL, corrupted entry), and offering an "approve access" button for it gives
    /// the user a control that cannot help.
    static func needsUserApproval(_ status: OSStatus) -> Bool {
        status == errSecInteractionNotAllowed || status == errSecUserCanceled
    }

    @discardableResult
    static func setGenericPassword(_ value: String, service: String, account: String) -> Bool {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess {
            return true
        }
        if status == errSecItemNotFound {
            var insert = query
            insert.merge(attributes) { _, new in new }
            return SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
        }
        return false
    }

    @discardableResult
    static func deleteGenericPassword(service: String, account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
