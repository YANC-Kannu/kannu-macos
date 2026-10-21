import Foundation
import LocalAuthentication
import os
import Security

enum KeychainReader {
    private static let log = os.Logger(subsystem: "com.kannu.app", category: "Keychain")

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
        let query = passwordQuery(service: service, account: account)
        crossAppReadLock.lock()
        defer { crossAppReadLock.unlock() }
        guard !allowInteraction else { return copyPassword(query) }
        return copyPasswordSilently(query)
    }

    /// `setGenericPassword`'s read of the value it is about to replace: Kannu's own item, without a
    /// dialog, and without ever waiting for `crossAppReadLock`. A save runs on the main thread on
    /// every keystroke, and the lock can be held by a read that is showing another app's Keychain
    /// dialog and waiting for the user. When the lock is busy this returns nil, which the save
    /// already handles: a prior value it cannot read is not restored.
    private static func ownValueWithoutWaiting(service: String, account: String) -> String? {
        guard crossAppReadLock.try() else { return nil }
        defer { crossAppReadLock.unlock() }
        return copyPasswordSilently(passwordQuery(service: service, account: account)).value
    }

    /// One read that cannot show a dialog. The caller holds `crossAppReadLock`: the interaction
    /// switch is process-wide.
    private static func copyPasswordSilently(_ query: [String: Any]) -> (value: String?, status: OSStatus) {
        var query = query
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

    /// Saves by deleting the item and adding it fresh, never by updating it in place
    /// (2026-10-04). An in-place update keeps the item's existing access list, so an item
    /// pre-planted under Kannu's service and account with a permissive list would have received
    /// the secret; a fresh add gets a list that trusts only Kannu. Writes only Kannu-owned
    /// services — another app's item is read-only. `KeychainWritePlan` decides both, and
    /// `KeychainWritePlanTests` keeps in-place updates out of the app.
    ///
    /// Delete-then-add is not atomic, so the prior value is read first (silently: a save runs on
    /// every keystroke and must never raise a keychain prompt) and re-added if the fresh add fails.
    /// A failed save therefore keeps the secret the user had, as the old in-place update did; only
    /// a prior value Kannu cannot read without a prompt is not restored. Logs the OSStatus, never
    /// the value.
    @discardableResult
    static func setGenericPassword(_ value: String, service: String, account: String) -> Bool {
        guard KeychainWritePlan.forSaving(service: service) == .recreate else { return false }
        let prior = ownValueWithoutWaiting(service: service, account: account)
        guard deleteGenericPassword(service: service, account: account) else { return false }
        let status = addGenericPassword(value, service: service, account: account)
        if status == errSecSuccess { return true }
        log.error("Keychain save of \(account, privacy: .public) failed: OSStatus \(status, privacy: .public)")
        if let restore = KeychainWritePlan.valueToRestore(afterAdd: status, prior: prior) {
            let restored = addGenericPassword(restore, service: service, account: account)
            log.error("Keychain restore of \(account, privacy: .public) after the failed save: OSStatus \(restored, privacy: .public)")
        }
        return false
    }

    /// A fresh item: `SecItemAdd` gives it an access list that trusts only Kannu. Called only by
    /// `setGenericPassword`, after the delete — never on its own.
    private static func addGenericPassword(_ value: String, service: String, account: String) -> OSStatus {
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(value.utf8),
            // Sonar S6288 asks for user authentication on every read. Kannu reads these tokens in
            // the background (usage refreshes, task syncs), where no prompt can be answered, so
            // the item stays readable while the Mac is unlocked, on this device only, with an
            // access list that trusts only Kannu: the same protection every Kannu item had before.
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        // Sonar reports S6288 on this call; the reason is on the accessibility attribute above.
        return SecItemAdd(item as CFDictionary, nil) // NOSONAR
    }

    /// True when nothing is left at this service and account. Refuses (false) for a service
    /// Kannu does not own: deleting another app's credentials is a write too.
    @discardableResult
    static func deleteGenericPassword(service: String, account: String) -> Bool {
        guard KeychainWritePlan.isKannuOwned(service: service) else { return false }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        return KeychainWritePlan.deleteLeftNothing(SecItemDelete(query as CFDictionary))
    }
}
