import Foundation
import SwiftData

@MainActor
final class HabitStore: ObservableObject {
    @Published private(set) var habits: [Habit] = []
    @Published private(set) var completions: [HabitCompletion] = []
    @Published private(set) var progress = PlayerProgress()
    @Published private(set) var errorMessage: String?

    private let context: ModelContext
    private let retainedContainer: ModelContainer?
    private let clock: any TenoraClock
    private let calendar: Calendar
    private let engine = HabitTrackingEngine()
    var didChange: (() async -> Void)?

    init(
        modelContext: ModelContext,
        clock: any TenoraClock = SystemClock(),
        calendar: Calendar = .autoupdatingCurrent,
        retainedContainer: ModelContainer? = nil
    ) {
        context = modelContext
        self.retainedContainer = retainedContainer
        self.clock = clock
        self.calendar = calendar
    }

    var activeHabits: [Habit] { habits.filter { !$0.isArchived } }
    var today: Date { clock.now }

    var todayHabits: [Habit] {
        engine.scheduleCalculator.scheduledHabits(activeHabits, on: clock.now, completions: completions, calendar: calendar)
    }

    var todaySummary: HabitDaySummary {
        engine.daySummary(habits: activeHabits, completions: completions, on: clock.now, calendar: calendar)
    }

    func scheduledHabits(on date: Date) -> [Habit] {
        engine.scheduleCalculator.scheduledHabits(activeHabits, on: date, completions: completions, calendar: calendar)
    }

    func daySummary(on date: Date) -> HabitDaySummary {
        engine.daySummary(habits: activeHabits, completions: completions, on: date, calendar: calendar)
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
            try refresh()
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
            try refresh()
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
            try refresh()
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
        do {
            let id = habit.id
            let stored = try context.fetch(FetchDescriptor<StoredHabitCompletion>(predicate: #Predicate { $0.habitID == id }))
            if let existing = stored.first(where: { calendar.isDate($0.completionDate, inSameDayAs: targetDate) }) {
                context.delete(existing)
                try context.save()
                try refresh()
            } else {
                let completion = HabitCompletion(
                    habitID: habit.id,
                    completionDate: targetDate,
                    xpAwarded: 0,
                    createdAt: clock.now
                )
                context.insert(StoredHabitCompletion(completion: completion))
                try context.save()
                try refresh()
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
            await didChange?()
            return true
        } catch {
            errorMessage = "Tenora couldn't delete your habit data."
            return false
        }
    }

    func completionRate(for habit: Habit, through date: Date? = nil, lastDays: Int? = nil) -> Double {
        let end = date ?? clock.now
        let created = calendar.startOfDay(for: habit.createdAt)
        let windowStart = lastDays.flatMap { calendar.date(byAdding: .day, value: -max(0, $0 - 1), to: calendar.startOfDay(for: end)) }
        let start = max(created, windowStart ?? created)
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

    func periodSummary(from start: Date, through end: Date, habits: [Habit]? = nil) -> HabitPeriodSummary {
        let includedHabits = habits ?? activeHabits
        var day = calendar.startOfDay(for: start)
        let last = calendar.startOfDay(for: end)
        var scheduled = 0
        var completed = 0
        var activeDays = 0
        while day <= last {
            let summary = engine.daySummary(habits: includedHabits, completions: completions, on: day, calendar: calendar)
            scheduled += summary.scheduled
            completed += summary.completed
            if summary.completed > 0 { activeDays += 1 }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day), next > day else { break }
            day = next
        }
        return HabitPeriodSummary(scheduled: scheduled, completed: completed, activeDays: activeDays)
    }

    func thisWeekSummary(for habit: Habit? = nil) -> HabitPeriodSummary {
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: clock.now) else { return .init() }
        return periodSummary(from: interval.start, through: clock.now, habits: habit.map { [$0] })
    }

    func recentConsistencyText(for habit: Habit) -> String {
        let summary = thisWeekSummary(for: habit)
        guard summary.scheduled > 0 else { return "No check-ins due yet this week" }
        return "This week: \(summary.completed) of \(summary.scheduled)"
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
        let habits = todayHabits.map {
            HabitWidgetHabit(id: $0.id, title: $0.name, iconName: $0.iconName, isCompleted: isCompleted($0))
        }
        return HabitWidgetSnapshot(updatedAt: clock.now, habits: habits,
                                   completedCount: habits.filter(\.isCompleted).count, totalCount: habits.count)
    }

    private func refresh() throws {
        habits = try context.fetch(FetchDescriptor<StoredHabit>(sortBy: [SortDescriptor(\.createdAt)])).map(\.domainModel)
        completions = try context.fetch(FetchDescriptor<StoredHabitCompletion>(sortBy: [SortDescriptor(\.completionDate)])).map(\.domainModel)
        progress = engine.progress(habits: activeHabits, completions: completions, now: clock.now, calendar: calendar)

        let storedProgress = try context.fetch(FetchDescriptor<StoredPlayerProgress>()).first
        if let storedProgress { storedProgress.update(from: progress) }
        else { context.insert(StoredPlayerProgress(progress: progress)) }

        try context.save()
    }

    #if DEBUG
    static func preview(_ scenario: HabitPreviewScenario) -> HabitStore {
        let container = try! ModelContainer(
            for: StoredTask.self, StoredHabit.self, StoredHabitCompletion.self, StoredPlayerProgress.self, StoredGameUnlock.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let store = HabitStore(modelContext: container.mainContext, retainedContainer: container)
        guard scenario != .empty else { try? store.refresh(); return store }

        let start = Calendar.current.date(byAdding: .day, value: scenario == .highLevel ? -90 : -7, to: Date()) ?? Date()
        let read = Habit(name: "Read 20 Minutes", iconName: "habit_icon_book", colorIdentifier: "forest", createdAt: start, difficulty: .standard)
        let water = Habit(name: "Drink Water", iconName: "habit_icon_water", colorIdentifier: "copper", createdAt: start, difficulty: .easy)
        container.mainContext.insert(StoredHabit(habit: read))
        if scenario != .newPlayer { container.mainContext.insert(StoredHabit(habit: water)) }

        if scenario == .partial || scenario == .perfect {
            container.mainContext.insert(StoredHabitCompletion(completion: HabitCompletion(habitID: read.id, completionDate: Date(), xpAwarded: 0)))
        }
        if scenario == .perfect {
            container.mainContext.insert(StoredHabitCompletion(completion: HabitCompletion(habitID: water.id, completionDate: Date(), xpAwarded: 0)))
        }
        if scenario == .highLevel {
            for offset in 0..<90 {
                let day = Calendar.current.date(byAdding: .day, value: -offset, to: Date()) ?? Date()
                container.mainContext.insert(StoredHabitCompletion(completion: HabitCompletion(habitID: read.id, completionDate: day, xpAwarded: 0)))
                container.mainContext.insert(StoredHabitCompletion(completion: HabitCompletion(habitID: water.id, completionDate: day, xpAwarded: 0)))
            }
        }
        try? container.mainContext.save()
        try? store.refresh()
        return store
    }
    #endif
}

#if DEBUG
enum HabitPreviewScenario { case empty, newPlayer, partial, perfect, highLevel }
#endif
