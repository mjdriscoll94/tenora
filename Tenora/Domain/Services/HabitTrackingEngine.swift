import Foundation

struct HabitScheduleCalculator {
    func isScheduled(
        _ habit: Habit,
        on date: Date,
        completions: [HabitCompletion] = [],
        calendar: Calendar = .autoupdatingCurrent
    ) -> Bool {
        guard !habit.isArchived, date >= calendar.startOfDay(for: habit.createdAt) else { return false }
        switch habit.schedule.type {
        case .everyDay:
            return true
        case .specificWeekdays:
            return habit.schedule.weekdays.contains(calendar.component(.weekday, from: date))
        case .timesPerWeek:
            guard let interval = calendar.dateInterval(of: .weekOfYear, for: date) else { return true }
            if completions.contains(where: { $0.habitID == habit.id && calendar.isDate($0.completionDate, inSameDayAs: date) }) {
                return true
            }
            let startOfDay = calendar.startOfDay(for: date)
            let previousCount = completions.filter {
                $0.habitID == habit.id && interval.contains($0.completionDate) && $0.completionDate < startOfDay
            }.count
            return previousCount < max(1, habit.schedule.weeklyTarget)
        case .custom:
            let start = calendar.startOfDay(for: habit.createdAt)
            let target = calendar.startOfDay(for: date)
            let days = calendar.dateComponents([.day], from: start, to: target).day ?? 0
            return days >= 0 && days.isMultiple(of: max(1, habit.schedule.intervalDays))
        }
    }

    func scheduledHabits(
        _ habits: [Habit],
        on date: Date,
        completions: [HabitCompletion],
        calendar: Calendar = .autoupdatingCurrent
    ) -> [Habit] {
        habits.filter { isScheduled($0, on: date, completions: completions, calendar: calendar) }
    }
}

struct HabitTrackingEngine {
    let scheduleCalculator = HabitScheduleCalculator()

    func daySummary(
        habits: [Habit],
        completions: [HabitCompletion],
        on date: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> HabitDaySummary {
        let day = calendar.startOfDay(for: date)
        let scheduled = scheduleCalculator.scheduledHabits(habits, on: day, completions: completions, calendar: calendar)
        let completedIDs = Set(completions.filter { calendar.isDate($0.completionDate, inSameDayAs: day) }.map(\.habitID))
        return HabitDaySummary(date: day, scheduled: scheduled.count, completed: scheduled.filter { completedIDs.contains($0.id) }.count)
    }

    /// Maintains the legacy persisted summary fields while the functional tracker
    /// presents completion counts and rates instead of points or levels.
    func progress(
        habits: [Habit],
        completions: [HabitCompletion],
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> PlayerProgress {
        guard let firstDate = ([habits.map(\.createdAt).min(), completions.map(\.completionDate).min()]).compactMap({ $0 }).min() else {
            return PlayerProgress(totalCompletions: completions.count)
        }

        let today = calendar.startOfDay(for: now)
        var cursor = calendar.startOfDay(for: firstDate)
        var currentRun = 0
        var longestRun = 0
        var fullyCompletedDays = 0
        while cursor <= today {
            let summary = daySummary(habits: habits, completions: completions, on: cursor, calendar: calendar)
            if summary.isPerfect { fullyCompletedDays += 1 }
            if summary.scheduled > 0 {
                if summary.keepsMomentum {
                    currentRun += 1
                    longestRun = max(longestRun, currentRun)
                } else if cursor < today {
                    currentRun = 0
                }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor), next > cursor else { break }
            cursor = next
        }

        return PlayerProgress(
            totalXP: 0,
            level: 1,
            xpIntoLevel: 0,
            xpForNextLevel: 100,
            totalCompletions: completions.count,
            currentMomentum: currentRun,
            longestMomentum: longestRun,
            perfectDays: fullyCompletedDays
        )
    }
}
