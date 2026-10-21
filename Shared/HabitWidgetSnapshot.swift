import Foundation

struct HabitWidgetHabit: Codable, Identifiable, Equatable {
    let id: UUID
    let title: String
    let iconName: String
    var isCompleted: Bool
}

struct HabitWidgetSnapshot: Codable, Equatable {
    static let groupID = "group.com.tenora.app"
    static let key = "tenora.habit.widget.snapshot.v1"
    static let pendingKey = "tenora.habit.widget.pending.v1"
    static let activeProfileKey = WidgetSnapshot.activeProfileKey

    let updatedAt: Date
    var habits: [HabitWidgetHabit]
    var completedCount: Int
    let totalCount: Int

    private enum CodingKeys: String, CodingKey {
        case updatedAt, habits, quests, completedCount, totalCount
    }

    init(updatedAt: Date, habits: [HabitWidgetHabit], completedCount: Int, totalCount: Int) {
        self.updatedAt = updatedAt
        self.habits = habits
        self.completedCount = completedCount
        self.totalCount = totalCount
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        updatedAt = try values.decode(Date.self, forKey: .updatedAt)
        habits = try values.decodeIfPresent([HabitWidgetHabit].self, forKey: .habits)
            ?? values.decodeIfPresent([HabitWidgetHabit].self, forKey: .quests)
            ?? []
        completedCount = try values.decodeIfPresent(Int.self, forKey: .completedCount)
            ?? habits.filter(\.isCompleted).count
        totalCount = try values.decodeIfPresent(Int.self, forKey: .totalCount) ?? habits.count
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(updatedAt, forKey: .updatedAt)
        try values.encode(habits, forKey: .habits)
        try values.encode(completedCount, forKey: .completedCount)
        try values.encode(totalCount, forKey: .totalCount)
    }

    static func read() -> Self? {
        let defaults = UserDefaults(suiteName: groupID)
        let profileID = defaults?.string(forKey: activeProfileKey) ?? "offline"
        let data = defaults?.data(forKey: storageKey(profileID: profileID))
            ?? (profileID == "offline" ? defaults?.data(forKey: key) : nil)
        guard let data else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }

    func write(profileID: String = "offline") {
        guard let data = try? JSONEncoder().encode(self) else { return }
        let defaults = UserDefaults(suiteName: Self.groupID)
        defaults?.set(profileID, forKey: Self.activeProfileKey)
        defaults?.set(data, forKey: Self.storageKey(profileID: profileID))
    }

    static func queueCompletion(id: UUID) {
        let defaults = UserDefaults(suiteName: groupID)
        let profileID = defaults?.string(forKey: activeProfileKey) ?? "offline"
        let key = pendingStorageKey(profileID: profileID)
        var values = defaults?.stringArray(forKey: key) ?? []
        if !values.contains(id.uuidString) { values.append(id.uuidString) }
        defaults?.set(values, forKey: key)
    }

    static func takePendingCompletionIDs() -> [UUID] {
        let defaults = UserDefaults(suiteName: groupID)
        let profileID = defaults?.string(forKey: activeProfileKey) ?? "offline"
        let key = pendingStorageKey(profileID: profileID)
        let values = defaults?.stringArray(forKey: key) ?? []
        defaults?.removeObject(forKey: key)
        return values.compactMap(UUID.init(uuidString:))
    }

    static func storageKey(profileID: String) -> String { key + "." + profileID }
    static func pendingStorageKey(profileID: String) -> String { pendingKey + "." + profileID }
}
