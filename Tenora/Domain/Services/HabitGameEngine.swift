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

struct HabitGameEngine {
    let scheduleCalculator = HabitScheduleCalculator()

    func xpAward(for difficulty: HabitDifficulty) -> Int {
        switch difficulty {
        case .easy: 10
        case .standard: 20
        case .challenging: 30
        }
    }

    func xpRequired(forLevel level: Int) -> Int { 100 + max(0, level - 1) * 25 }

    func levelProgress(totalXP: Int) -> (level: Int, current: Int, required: Int) {
        var remaining = max(0, totalXP)
        var level = 1
        while remaining >= xpRequired(forLevel: level) {
            remaining -= xpRequired(forLevel: level)
            level += 1
        }
        return (level, remaining, xpRequired(forLevel: level))
    }

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

    func progress(
        habits: [Habit],
        completions: [HabitCompletion],
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> PlayerProgress {
        let totalXP = completions.reduce(0) { $0 + $1.xpAwarded }
        let level = levelProgress(totalXP: totalXP)
        guard let firstDate = ([habits.map(\.createdAt).min(), completions.map(\.completionDate).min()]).compactMap({ $0 }).min() else {
            return PlayerProgress(totalXP: totalXP, level: level.level, xpIntoLevel: level.current, xpForNextLevel: level.required)
        }

        let today = calendar.startOfDay(for: now)
        var cursor = calendar.startOfDay(for: firstDate)
        var momentum = 0
        var longest = 0
        var perfectDays = 0
        while cursor <= today {
            let summary = daySummary(habits: habits, completions: completions, on: cursor, calendar: calendar)
            if summary.isPerfect { perfectDays += 1 }
            if summary.scheduled > 0 {
                if summary.keepsMomentum {
                    momentum += 1
                    longest = max(longest, momentum)
                } else if cursor < today {
                    momentum = 0
                }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor), next > cursor else { break }
            cursor = next
        }
        return PlayerProgress(
            totalXP: totalXP,
            level: level.level,
            xpIntoLevel: level.current,
            xpForNextLevel: level.required,
            totalCompletions: completions.count,
            currentMomentum: momentum,
            longestMomentum: longest,
            perfectDays: perfectDays
        )
    }

    func isBackInMotion(
        previousCompletions: [HabitCompletion],
        completingAt date: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Bool {
        guard let last = previousCompletions.map(\.completionDate).max() else { return false }
        let gap = calendar.dateComponents([.day], from: calendar.startOfDay(for: last), to: calendar.startOfDay(for: date)).day ?? 0
        return gap >= 3
    }

    func hasPerfectWeek(
        habits: [Habit],
        completions: [HabitCompletion],
        endingAt date: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Bool {
        (0..<7).allSatisfy { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: date) else { return false }
            return daySummary(habits: habits, completions: completions, on: day, calendar: calendar).isPerfect
        }
    }
}

struct HabitAchievementEngine {
    static let all: [HabitAchievement] = [
        .init(id: "first-step", title: "First Step", detail: "Complete your first quest.", symbol: "shoeprints.fill"),
        .init(id: "getting-started", title: "Getting Started", detail: "Complete five quests.", symbol: "sparkles"),
        .init(id: "momentum-3", title: "Momentum 3", detail: "Build three days of Momentum.", symbol: "flame.fill"),
        .init(id: "momentum-7", title: "Momentum 7", detail: "Build seven days of Momentum.", symbol: "flame.circle.fill"),
        .init(id: "momentum-14", title: "Momentum 14", detail: "Build fourteen days of Momentum.", symbol: "bolt.heart.fill"),
        .init(id: "momentum-30", title: "Momentum 30", detail: "Build thirty days of Momentum.", symbol: "crown.fill"),
        .init(id: "perfect-day", title: "Perfect Day", detail: "Complete every scheduled quest in a day.", symbol: "sun.max.fill"),
        .init(id: "perfect-week", title: "Perfect Week", detail: "Complete every scheduled quest for seven days.", symbol: "calendar.badge.checkmark"),
        .init(id: "completions-100", title: "100 Completions", detail: "Take one hundred small steps.", symbol: "100.circle.fill"),
        .init(id: "completions-500", title: "500 Completions", detail: "Take five hundred small steps.", symbol: "star.circle.fill"),
        .init(id: "level-5", title: "Level 5", detail: "Reach level five.", symbol: "5.circle.fill"),
        .init(id: "level-10", title: "Level 10", detail: "Reach level ten.", symbol: "10.circle.fill"),
        .init(id: "level-25", title: "Level 25", detail: "Reach level twenty-five.", symbol: "medal.fill"),
        .init(id: "back-in-motion", title: "Back in Motion", detail: "Return after three or more days away.", symbol: "arrow.uturn.forward.circle.fill")
    ]

    func earnedIDs(
        progress: PlayerProgress,
        perfectWeek: Bool,
        backInMotion: Bool
    ) -> Set<String> {
        var ids: Set<String> = []
        if progress.totalCompletions >= 1 { ids.insert("first-step") }
        if progress.totalCompletions >= 5 { ids.insert("getting-started") }
        for target in [3, 7, 14, 30] where progress.longestMomentum >= target { ids.insert("momentum-\(target)") }
        if progress.perfectDays >= 1 { ids.insert("perfect-day") }
        if perfectWeek { ids.insert("perfect-week") }
        if progress.totalCompletions >= 100 { ids.insert("completions-100") }
        if progress.totalCompletions >= 500 { ids.insert("completions-500") }
        for target in [5, 10, 25] where progress.level >= target { ids.insert("level-\(target)") }
        if backInMotion { ids.insert("back-in-motion") }
        return ids
    }
}

enum HabitRewardCatalog {
    static let all: [GameReward] = [
        .init(id: "terrain", levelRequired: 1, title: "Quiet Ground", detail: "A place to begin.", symbol: "circle.fill"),
        .init(id: "path", levelRequired: 2, title: "Winding Path", detail: "The next step becomes visible.", symbol: "point.topleft.down.to.point.bottomright.curvepath"),
        .init(id: "small-plant", levelRequired: 3, title: "First Sprout", detail: "Something is growing.", symbol: "leaf.fill"),
        .init(id: "rocks", levelRequired: 4, title: "River Stones", detail: "A grounded detail for your world.", symbol: "circle.hexagongrid.fill"),
        .init(id: "small-tree", levelRequired: 5, title: "Young Tree", detail: "Your consistency takes root.", symbol: "tree.fill"),
        .init(id: "medium-plant", levelRequired: 6, title: "Wildflowers", detail: "Color returns to the path.", symbol: "camera.macro"),
        .init(id: "bench", levelRequired: 7, title: "Resting Bench", detail: "Progress includes rest.", symbol: "chair.lounge.fill"),
        .init(id: "lantern", levelRequired: 8, title: "Trail Lantern", detail: "A little more of the way is lit.", symbol: "light.beacon.max.fill"),
        .init(id: "large-tree", levelRequired: 10, title: "Shelter Tree", detail: "Your world has a canopy.", symbol: "tree.circle.fill"),
        .init(id: "cabin", levelRequired: 12, title: "Small Haven", detail: "A steady place along the path.", symbol: "house.fill"),
        .init(id: "hills", levelRequired: 15, title: "Distant Hills", detail: "The horizon opens.", symbol: "mountain.2.fill"),
        .init(id: "mountains", levelRequired: 20, title: "Mountain Horizon", detail: "Your accumulated progress changes the view.", symbol: "mountain.2.circle.fill"),
        .init(id: "stars", levelRequired: 25, title: "Evening Stars", detail: "A quiet sky for the world you built.", symbol: "sparkles")
    ]
}
