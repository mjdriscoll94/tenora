import Foundation

enum HabitDifficulty: String, Codable, CaseIterable, Identifiable {
    case easy, standard, challenging

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum HabitScheduleType: String, Codable, CaseIterable, Identifiable {
    case everyDay
    case specificWeekdays
    case timesPerWeek
    case custom

    var id: String { rawValue }
    var title: String {
        switch self {
        case .everyDay: "Every day"
        case .specificWeekdays: "Specific weekdays"
        case .timesPerWeek: "Times per week"
        case .custom: "Custom repeat"
        }
    }
}

struct HabitSchedule: Codable, Equatable {
    var type: HabitScheduleType = .everyDay
    /// Calendar weekday values, Sunday = 1 ... Saturday = 7.
    var weekdays: Set<Int> = [2, 3, 4, 5, 6]
    var weeklyTarget: Int = 3
    var intervalDays: Int = 2
}

struct Habit: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var details: String = ""
    var iconName: String = "habit_icon_planning"
    var colorIdentifier: String = "forest"
    var createdAt: Date = Date()
    var isArchived: Bool = false
    var difficulty: HabitDifficulty = .standard
    var schedule: HabitSchedule = HabitSchedule()
    /// Minutes after local midnight. Nil means no reminder.
    var reminderMinute: Int?
}

struct HabitCompletion: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var habitID: UUID
    var completionDate: Date
    var xpAwarded: Int
    var createdAt: Date = Date()
}

struct PlayerProgress: Codable, Equatable {
    var totalXP = 0
    var level = 1
    var xpIntoLevel = 0
    var xpForNextLevel = 100
    var totalCompletions = 0
    var currentMomentum = 0
    var longestMomentum = 0
    var perfectDays = 0
}

struct HabitDaySummary: Equatable {
    let date: Date
    let scheduled: Int
    let completed: Int

    var isPerfect: Bool { scheduled > 0 && completed == scheduled }
    var keepsMomentum: Bool { scheduled > 0 && completed * 2 >= scheduled }
    var completionFraction: Double { scheduled == 0 ? 0 : Double(completed) / Double(scheduled) }
}

struct HabitAchievement: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
    let symbol: String
    var assetName: String? = nil
}

struct GameReward: Identifiable, Equatable {
    let id: String
    let levelRequired: Int
    let title: String
    let detail: String
    let symbol: String
    var assetName: String? = nil
}

struct HabitCelebration: Identifiable, Equatable {
    enum Kind: Equatable { case completion, perfectDay, achievement, levelUp }
    let id = UUID()
    let kind: Kind
    let title: String
    let detail: String
    let symbol: String
    var assetName: String? = nil
}
