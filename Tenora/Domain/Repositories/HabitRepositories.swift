import Foundation

@MainActor
protocol HabitRepository {
    func fetchHabits() throws -> [Habit]
    func saveHabit(_ habit: Habit) throws
    func deleteHabit(id: UUID) throws
    func deleteAllHabits() throws
}

@MainActor
protocol HabitCompletionRepository {
    func fetchHabitCompletions() throws -> [HabitCompletion]
    func saveHabitCompletion(_ completion: HabitCompletion) throws
    func deleteHabitCompletion(id: UUID) throws
    func deleteHabitCompletions(habitID: UUID) throws
    func deleteAllHabitCompletions() throws
}

@MainActor
protocol HabitProgressRepository {
    func fetchPlayerProgress() throws -> PlayerProgress?
    func savePlayerProgress(_ progress: PlayerProgress) throws
    func deleteAllHabitProgress() throws
}
