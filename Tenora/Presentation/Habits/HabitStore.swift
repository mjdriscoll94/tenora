import Foundation
import SwiftData

@MainActor
final class HabitStore: ObservableObject {
    @Published private(set) var habits: [Habit] = []
    @Published private(set) var completions: [HabitCompletion] = []
    @Published private(set) var progress = PlayerProgress()
    @Published private(set) var achievementIDs: Set<String> = []
    @Published private(set) var rewardIDs: Set<String> = []
    @Published var celebration: HabitCelebration?
    @Published private(set) var errorMessage: String?

    private let context: ModelContext
    private let clock: any TenoraClock
    private let calendar: Calendar
    private let engine = HabitGameEngine()
    var didChange: (() async -> Void)?

    init(modelContext: ModelContext, clock: any TenoraClock = SystemClock(), calendar: Calendar = .autoupdatingCurrent) {
        context = modelContext
        self.clock = clock
        self.calendar = calendar
    }

    var activeHabits: [Habit] { habits.filter { !$0.isArchived } }

    var todayHabits: [Habit] {
        engine.scheduleCalculator.scheduledHabits(activeHabits, on: clock.now, completions: completions, calendar: calendar)
    }

    var todaySummary: HabitDaySummary {
        engine.daySummary(habits: activeHabits, completions: completions, on: clock.now, calendar: calendar)
    }

    func isCompleted(_ habit: Habit, on date: Date? = nil) -> Bool {
        let target = date ?? clock.now
        return completions.contains { $0.habitID == habit.id && calendar.isDate($0.completionDate, inSameDayAs: target) }
    }

    func completion(for habit: Habit, on date: Date) -> HabitCompletion? {
        completions.first { $0.habitID == habit.id && calendar.isDate($0.completionDate, inSameDayAs: date) }
    }

    func completions(for habit: Habit) -> [HabitCompletion] {
        completions.filter { $0.habitID == habit.id }.sorted { $0.completionDate > $1.completionDate }
    }

    func load() async {
        do {
            try refresh(backInMotion: false)
            errorMessage = nil
            await didChange?()
        } catch {
            errorMessage = "Tenora couldn't load your habits."
        }
    }

    @discardableResult
    func save(_ habit: Habit) async -> Bool {
        let cleanName = habit.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return false }
        var clean = habit
        clean.name = cleanName
        do {
            let id = clean.id
            let descriptor = FetchDescriptor<StoredHabit>(predicate: #Predicate { $0.id == id })
            if let stored = try context.fetch(descriptor).first { stored.update(from: clean) }
            else { context.insert(StoredHabit(habit: clean)) }
            try context.save()
            try refresh(backInMotion: false)
            errorMessage = nil
            await didChange?()
            return true
        } catch {
            errorMessage = "Tenora couldn't save that habit."
            return false
        }
    }

    @discardableResult
    func archive(_ habit: Habit) async -> Bool {
        var updated = habit
        updated.isArchived = true
        return await save(updated)
    }

    @discardableResult
    func delete(_ habit: Habit) async -> Bool {
        do {
            let id = habit.id
            let storedHabits = try context.fetch(FetchDescriptor<StoredHabit>(predicate: #Predicate { $0.id == id }))
            storedHabits.forEach(context.delete)
            let storedCompletions = try context.fetch(FetchDescriptor<StoredHabitCompletion>(predicate: #Predicate { $0.habitID == id }))
            storedCompletions.forEach(context.delete)
            try context.save()
            try refresh(backInMotion: false)
            await didChange?()
            return true
        } catch {
            errorMessage = "Tenora couldn't delete that habit."
            return false
        }
    }

    /// Toggles a completion for correction-friendly history editing.
    @discardableResult
    func toggleCompletion(_ habit: Habit, on date: Date? = nil) async -> Bool {
        let targetDate = date ?? clock.now
        let oldProgress = progress
        let previous = completions
        do {
            let id = habit.id
            let stored = try context.fetch(FetchDescriptor<StoredHabitCompletion>(predicate: #Predicate { $0.habitID == id }))
            if let existing = stored.first(where: { calendar.isDate($0.completionDate, inSameDayAs: targetDate) }) {
                context.delete(existing)
                try context.save()
                try refresh(backInMotion: false)
                celebration = nil
            } else {
                let backInMotion = engine.isBackInMotion(previousCompletions: previous, completingAt: targetDate, calendar: calendar)
                let completion = HabitCompletion(
                    habitID: habit.id,
                    completionDate: targetDate,
                    xpAwarded: engine.xpAward(for: habit.difficulty),
                    createdAt: clock.now
                )
                context.insert(StoredHabitCompletion(completion: completion))
                try context.save()
                let previousAchievements = achievementIDs
                try refresh(backInMotion: backInMotion)
                celebration = celebrationFor(
                    habit: habit,
                    xp: completion.xpAwarded,
                    oldProgress: oldProgress,
                    newAchievements: achievementIDs.subtracting(previousAchievements)
                )
            }
            errorMessage = nil
            await didChange?()
            return true
        } catch {
            errorMessage = "Tenora couldn't update that completion."
            return false
        }
    }

    func completeFromWidget(id: UUID) async -> Bool {
        guard let habit = habits.first(where: { $0.id == id }), !isCompleted(habit) else { return true }
        return await toggleCompletion(habit)
    }

    func drainWidgetActions() async {
        let ids = HabitWidgetSnapshot.takePendingCompletionIDs()
        for id in ids { _ = await completeFromWidget(id: id) }
    }

    func deleteAll() async -> Bool {
        do {
            for model in try context.fetch(FetchDescriptor<StoredHabit>()) { context.delete(model) }
            for model in try context.fetch(FetchDescriptor<StoredHabitCompletion>()) { context.delete(model) }
            for model in try context.fetch(FetchDescriptor<StoredPlayerProgress>()) { context.delete(model) }
            for model in try context.fetch(FetchDescriptor<StoredGameUnlock>()) { context.delete(model) }
            try context.save()
            habits = []
            completions = []
            progress = PlayerProgress()
            achievementIDs = []
            rewardIDs = []
            celebration = nil
            await didChange?()
            return true
        } catch {
            errorMessage = "Tenora couldn't delete your habit data."
            return false
        }
    }

    func completionRate(for habit: Habit, through date: Date? = nil) -> Double {
        let end = date ?? clock.now
        let start = calendar.startOfDay(for: habit.createdAt)
        var day = start
        var scheduled = 0
        var complete = 0
        while day <= end {
            if engine.scheduleCalculator.isScheduled(habit, on: day, completions: completions, calendar: calendar) {
                scheduled += 1
                if isCompleted(habit, on: day) { complete += 1 }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day), next > day else { break }
            day = next
        }
        return scheduled == 0 ? 0 : Double(complete) / Double(scheduled)
    }

    func xpEarned(for habit: Habit) -> Int { completions(for: habit).reduce(0) { $0 + $1.xpAwarded } }

    func currentMomentum(for habit: Habit) -> Int {
        engine.progress(habits: [habit], completions: completions.filter { $0.habitID == habit.id }, now: clock.now, calendar: calendar).currentMomentum
    }

    func weeklySummary(containing date: Date? = nil) -> [HabitDaySummary] {
        let target = date ?? clock.now
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: target) else { return [] }
        return (0..<7).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: interval.start).map {
                engine.daySummary(habits: activeHabits, completions: completions, on: $0, calendar: calendar)
            }
        }
    }

    var widgetSnapshot: HabitWidgetSnapshot {
        let quests = todayHabits.map {
            HabitWidgetQuest(id: $0.id, title: $0.name, iconName: $0.iconName,
                             xp: engine.xpAward(for: $0.difficulty), isCompleted: isCompleted($0))
        }
        return HabitWidgetSnapshot(updatedAt: clock.now, quests: quests, momentum: progress.currentMomentum,
                                   level: progress.level, completedCount: quests.filter(\.isCompleted).count, totalCount: quests.count)
    }

    private func refresh(backInMotion: Bool) throws {
        habits = try context.fetch(FetchDescriptor<StoredHabit>(sortBy: [SortDescriptor(\.createdAt)])).map(\.domainModel)
        completions = try context.fetch(FetchDescriptor<StoredHabitCompletion>(sortBy: [SortDescriptor(\.completionDate)])).map(\.domainModel)
        progress = engine.progress(habits: activeHabits, completions: completions, now: clock.now, calendar: calendar)

        let storedProgress = try context.fetch(FetchDescriptor<StoredPlayerProgress>()).first
        if let storedProgress { storedProgress.update(from: progress) }
        else { context.insert(StoredPlayerProgress(progress: progress)) }

        var unlocks = try context.fetch(FetchDescriptor<StoredGameUnlock>())
        let perfectWeek = engine.hasPerfectWeek(habits: activeHabits, completions: completions, endingAt: clock.now, calendar: calendar)
        let earned = HabitAchievementEngine().earnedIDs(progress: progress, perfectWeek: perfectWeek, backInMotion: backInMotion)
        let existingAchievementIDs = Set(unlocks.filter { $0.kind == "achievement" }.map(\.id))
        for id in earned.subtracting(existingAchievementIDs) { context.insert(StoredGameUnlock(id: id, kind: "achievement", unlockedAt: clock.now)) }

        let eligibleRewards = Set(HabitRewardCatalog.all.filter { $0.levelRequired <= progress.level }.map(\.id))
        let existingRewardIDs = Set(unlocks.filter { $0.kind == "reward" }.map(\.id))
        for id in eligibleRewards.subtracting(existingRewardIDs) { context.insert(StoredGameUnlock(id: id, kind: "reward", unlockedAt: clock.now)) }
        try context.save()
        unlocks = try context.fetch(FetchDescriptor<StoredGameUnlock>())
        achievementIDs = Set(unlocks.filter { $0.kind == "achievement" }.map(\.id))
        rewardIDs = Set(unlocks.filter { $0.kind == "reward" }.map(\.id))
    }

    private func celebrationFor(habit: Habit, xp: Int, oldProgress: PlayerProgress, newAchievements: Set<String>) -> HabitCelebration {
        if progress.level > oldProgress.level {
            let reward = HabitRewardCatalog.all.first { $0.levelRequired == progress.level }
            return HabitCelebration(kind: .levelUp, title: "Level \(progress.level)",
                                    detail: reward.map { "\($0.title) unlocked" } ?? "Your world grew.", symbol: "sparkles")
        }
        if let id = newAchievements.sorted().first,
           let achievement = HabitAchievementEngine.all.first(where: { $0.id == id }) {
            return HabitCelebration(kind: .achievement, title: achievement.title, detail: achievement.detail, symbol: achievement.symbol)
        }
        if todaySummary.isPerfect {
            return HabitCelebration(kind: .perfectDay, title: "Perfect Day", detail: "Every quest for today is complete.", symbol: "sun.max.fill")
        }
        return HabitCelebration(kind: .completion, title: habit.name, detail: "+\(xp) XP", symbol: "checkmark")
    }

    #if DEBUG
    static func preview(_ scenario: HabitPreviewScenario) -> HabitStore {
        let container = try! ModelContainer(
            for: StoredTask.self, StoredHabit.self, StoredHabitCompletion.self, StoredPlayerProgress.self, StoredGameUnlock.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let store = HabitStore(modelContext: container.mainContext)
        guard scenario != .empty else { try? store.refresh(backInMotion: false); return store }

        let start = Calendar.current.date(byAdding: .day, value: scenario == .highLevel ? -90 : -7, to: Date()) ?? Date()
        let read = Habit(name: "Read 20 Minutes", iconName: "book.fill", colorIdentifier: "forest", createdAt: start, difficulty: .standard)
        let water = Habit(name: "Drink Water", iconName: "drop.fill", colorIdentifier: "copper", createdAt: start, difficulty: .easy)
        container.mainContext.insert(StoredHabit(habit: read))
        if scenario != .newPlayer { container.mainContext.insert(StoredHabit(habit: water)) }

        if scenario == .partial || scenario == .perfect {
            container.mainContext.insert(StoredHabitCompletion(completion: HabitCompletion(habitID: read.id, completionDate: Date(), xpAwarded: 20)))
        }
        if scenario == .perfect {
            container.mainContext.insert(StoredHabitCompletion(completion: HabitCompletion(habitID: water.id, completionDate: Date(), xpAwarded: 10)))
        }
        if scenario == .highLevel {
            for offset in 0..<90 {
                let day = Calendar.current.date(byAdding: .day, value: -offset, to: Date()) ?? Date()
                container.mainContext.insert(StoredHabitCompletion(completion: HabitCompletion(habitID: read.id, completionDate: day, xpAwarded: 30)))
                container.mainContext.insert(StoredHabitCompletion(completion: HabitCompletion(habitID: water.id, completionDate: day, xpAwarded: 30)))
            }
        }
        try? container.mainContext.save()
        try? store.refresh(backInMotion: false)
        return store
    }
    #endif
}

#if DEBUG
enum HabitPreviewScenario { case empty, newPlayer, partial, perfect, highLevel }
#endif
