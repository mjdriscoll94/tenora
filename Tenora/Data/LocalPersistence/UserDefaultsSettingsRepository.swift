import Foundation

@MainActor
final class UserDefaultsSettingsRepository: SettingsRepository {
    let profileID: LocalProfileID
    private let defaults: UserDefaults
    private let schemaVersion = 1

    init(profileID: LocalProfileID, defaults: UserDefaults = .standard) {
        self.profileID = profileID
        self.defaults = defaults
    }

    func object(for key: TenoraSettingKey) -> Any? {
        let namespaced = storageKey(key)
        if let value = defaults.object(forKey: namespaced) { return value }
        // The offline profile owns all pre-profile settings. Copy on first read so
        // existing installations keep behavior while future profiles remain isolated.
        guard profileID == .offline, let legacy = defaults.object(forKey: key.rawValue) else { return nil }
        defaults.set(legacy, forKey: namespaced)
        return legacy
    }

    func set(_ value: Any?, for key: TenoraSettingKey) {
        let namespaced = storageKey(key)
        if let value { defaults.set(value, forKey: namespaced) }
        else { defaults.removeObject(forKey: namespaced) }
        // Mirror the offline profile for one stable compatibility release because
        // existing @AppStorage and platform services still observe legacy keys.
        if profileID == .offline {
            if let value { defaults.set(value, forKey: key.rawValue) }
            else { defaults.removeObject(forKey: key.rawValue) }
        }
    }

    func remove(_ key: TenoraSettingKey) { set(nil, for: key) }

    func removeAll() {
        TenoraSettingKey.allCases.forEach(remove)
    }

    func refreshFromLegacyStore() {
        guard profileID == .offline else { return }
        for key in TenoraSettingKey.allCases {
            let namespaced = storageKey(key)
            if let legacy = defaults.object(forKey: key.rawValue) {
                defaults.set(legacy, forKey: namespaced)
            } else {
                defaults.removeObject(forKey: namespaced)
            }
        }
    }

    private func storageKey(_ key: TenoraSettingKey) -> String {
        "profile.\(profileID.storageComponent).settings.v\(schemaVersion).\(key.rawValue)"
    }
}

@MainActor
final class UserDefaultsProfileRepository: ProfileRepository {
    private static let activeKey = "profiles.active.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var activeProfileID: LocalProfileID {
        defaults.string(forKey: Self.activeKey).map(LocalProfileID.init(rawValue:)) ?? .offline
    }

    func activate(_ profileID: LocalProfileID) {
        defaults.set(profileID.rawValue, forKey: Self.activeKey)
        UserDefaults(suiteName: WidgetSnapshot.groupID)?
            .set(profileID.rawValue, forKey: WidgetSnapshot.activeProfileKey)
    }

    func returnToOfflineProfile() { activate(.offline) }
}
