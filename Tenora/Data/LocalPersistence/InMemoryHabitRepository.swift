import Foundation

@MainActor
final class InMemoryHabitRepository: HabitRepository, HabitCompletionRepository, HabitProgressRepository {
    private(set) var habits: [Habit]
    private(set) var completions: [HabitCompletion]
    private(set) var progress: PlayerProgress?

    init(habits: [Habit] = [], completions: [HabitCompletion] = [], progress: PlayerProgress? = nil) {
        self.habits = habits
        self.completions = completions
        self.progress = progress
    }

    func fetchHabits() throws -> [Habit] { habits.sorted { $0.createdAt < $1.createdAt } }

    func saveHabit(_ habit: Habit) throws {
        habits.removeAll { $0.id == habit.id }
        habits.append(habit)
    }

    func deleteHabit(id: UUID) throws { habits.removeAll { $0.id == id } }
    func deleteAllHabits() throws { habits = [] }

    func fetchHabitCompletions() throws -> [HabitCompletion] {
        completions.sorted { $0.completionDate < $1.completionDate }
    }

    func saveHabitCompletion(_ completion: HabitCompletion) throws {
        completions.removeAll { $0.id == completion.id }
        completions.append(completion)
    }

    func deleteHabitCompletion(id: UUID) throws { completions.removeAll { $0.id == id } }
    func deleteHabitCompletions(habitID: UUID) throws { completions.removeAll { $0.habitID == habitID } }
    func deleteAllHabitCompletions() throws { completions = [] }

    func fetchPlayerProgress() throws -> PlayerProgress? { progress }
    func savePlayerProgress(_ progress: PlayerProgress) throws { self.progress = progress }
    func deleteAllHabitProgress() throws { progress = nil }
}
