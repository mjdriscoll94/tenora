import Foundation

struct HabitWidgetQuest: Codable, Identifiable, Equatable {
    let id: UUID
    let title: String
    let iconName: String
    let xp: Int
    var isCompleted: Bool
}

struct HabitWidgetSnapshot: Codable, Equatable {
    static let groupID = "group.com.tenora.app"
    static let key = "tenora.habit.widget.snapshot.v1"
    static let pendingKey = "tenora.habit.widget.pending.v1"

    let updatedAt: Date
    var quests: [HabitWidgetQuest]
    let momentum: Int
    let level: Int
    var completedCount: Int
    let totalCount: Int

    static func read() -> Self? {
        guard let data = UserDefaults(suiteName: groupID)?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }

    func write() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults(suiteName: Self.groupID)?.set(data, forKey: Self.key)
    }

    static func queueCompletion(id: UUID) {
        let defaults = UserDefaults(suiteName: groupID)
        var values = defaults?.stringArray(forKey: pendingKey) ?? []
        if !values.contains(id.uuidString) { values.append(id.uuidString) }
        defaults?.set(values, forKey: pendingKey)
    }

    static func takePendingCompletionIDs() -> [UUID] {
        let defaults = UserDefaults(suiteName: groupID)
        let values = defaults?.stringArray(forKey: pendingKey) ?? []
        defaults?.removeObject(forKey: pendingKey)
        return values.compactMap(UUID.init(uuidString:))
    }
}
