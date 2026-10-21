import Foundation
import SwiftData

@Model
final class StoredHabit {
    @Attribute(.unique) var id: UUID
    var name: String
    var habitDescription: String
    var iconName: String
    var colorIdentifier: String
    var createdAt: Date
    var isArchived: Bool
    var difficultyValue: String
    var scheduleData: Data
    var reminderMinute: Int?

    init(habit: Habit) {
        id = habit.id
        name = habit.name
        habitDescription = habit.details
        iconName = habit.iconName
        colorIdentifier = habit.colorIdentifier
        createdAt = habit.createdAt
        isArchived = habit.isArchived
        difficultyValue = habit.difficulty.rawValue
        scheduleData = (try? JSONEncoder().encode(habit.schedule)) ?? Data()
        reminderMinute = habit.reminderMinute
    }

    func update(from habit: Habit) {
        name = habit.name
        habitDescription = habit.details
        iconName = habit.iconName
        colorIdentifier = habit.colorIdentifier
        isArchived = habit.isArchived
        difficultyValue = habit.difficulty.rawValue
        scheduleData = (try? JSONEncoder().encode(habit.schedule)) ?? Data()
        reminderMinute = habit.reminderMinute
    }

    var domainModel: Habit {
        Habit(
            id: id,
            name: name,
            details: habitDescription,
            iconName: iconName,
            colorIdentifier: colorIdentifier,
            createdAt: createdAt,
            isArchived: isArchived,
            difficulty: HabitDifficulty(rawValue: difficultyValue) ?? .standard,
            schedule: (try? JSONDecoder().decode(HabitSchedule.self, from: scheduleData)) ?? HabitSchedule(),
            reminderMinute: reminderMinute
        )
    }
}

@Model
final class StoredHabitCompletion {
    @Attribute(.unique) var id: UUID
    var habitID: UUID
    var completionDate: Date
    var xpAwarded: Int
    var createdAt: Date

    init(completion: HabitCompletion) {
        id = completion.id
        habitID = completion.habitID
        completionDate = completion.completionDate
        xpAwarded = completion.xpAwarded
        createdAt = completion.createdAt
    }

    var domainModel: HabitCompletion {
        HabitCompletion(id: id, habitID: habitID, completionDate: completionDate, xpAwarded: xpAwarded, createdAt: createdAt)
    }
}

@Model
final class StoredPlayerProgress {
    @Attribute(.unique) var recordID: String
    var totalXP: Int
    var level: Int
    var xpIntoLevel: Int
    var xpForNextLevel: Int
    var totalCompletions: Int
    var currentMomentum: Int
    var longestMomentum: Int
    var perfectDays: Int

    init(recordID: String = "local-player", progress: PlayerProgress = PlayerProgress()) {
        self.recordID = recordID
        totalXP = progress.totalXP
        level = progress.level
        xpIntoLevel = progress.xpIntoLevel
        xpForNextLevel = progress.xpForNextLevel
        totalCompletions = progress.totalCompletions
        currentMomentum = progress.currentMomentum
        longestMomentum = progress.longestMomentum
        perfectDays = progress.perfectDays
    }

    func update(from progress: PlayerProgress) {
        totalXP = progress.totalXP
        level = progress.level
        xpIntoLevel = progress.xpIntoLevel
        xpForNextLevel = progress.xpForNextLevel
        totalCompletions = progress.totalCompletions
        currentMomentum = progress.currentMomentum
        longestMomentum = progress.longestMomentum
        perfectDays = progress.perfectDays
    }

    /// The practical tracker still refreshes completion statistics, but retired game
    /// values remain byte-for-byte available for a future user-directed migration.
    func updateTracking(from practical: PlayerProgress) {
        totalCompletions = practical.totalCompletions
        currentMomentum = practical.currentMomentum
        longestMomentum = max(longestMomentum, practical.longestMomentum)
        perfectDays = practical.perfectDays
    }

    func mergingTracking(from practical: PlayerProgress) -> PlayerProgress {
        PlayerProgress(
            totalXP: totalXP,
            level: level,
            xpIntoLevel: xpIntoLevel,
            xpForNextLevel: xpForNextLevel,
            totalCompletions: practical.totalCompletions,
            currentMomentum: practical.currentMomentum,
            longestMomentum: max(longestMomentum, practical.longestMomentum),
            perfectDays: practical.perfectDays
        )
    }
}

@Model
final class StoredGameUnlock {
    @Attribute(.unique) var id: String
    var kind: String
    var unlockedAt: Date

    init(id: String, kind: String, unlockedAt: Date = Date()) {
        self.id = id
        self.kind = kind
        self.unlockedAt = unlockedAt
    }
}

