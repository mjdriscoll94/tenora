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

    func returningMilestoneCount(
        completions: [HabitCompletion],
        calendar: Calendar = .autoupdatingCurrent
    ) -> Int {
        let days = Set(completions.map { calendar.startOfDay(for: $0.completionDate) }).sorted()
        guard days.count > 1 else { return 0 }
        return zip(days, days.dropFirst()).reduce(0) { count, pair in
            let gap = calendar.dateComponents([.day], from: pair.0, to: pair.1).day ?? 0
            return count + (gap >= 3 ? 1 : 0)
        }
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
        .init(id: "first-step", title: "First Step", detail: "Complete your first quest.", symbol: "shoeprints.fill", assetName: "badge_first_step"),
        .init(id: "getting-started", title: "Getting Started", detail: "Complete five quests.", symbol: "sparkles", assetName: "badge_getting_started"),
        .init(id: "completions-10", title: "10 Completions", detail: "Take ten small steps.", symbol: "10.circle.fill", assetName: "badge_completions_10"),
        .init(id: "completions-50", title: "50 Completions", detail: "Take fifty small steps.", symbol: "50.circle.fill", assetName: "badge_completions_50"),
        .init(id: "completions-100", title: "100 Completions", detail: "Take one hundred small steps.", symbol: "100.circle.fill", assetName: "badge_completions_100"),
        .init(id: "completions-500", title: "500 Completions", detail: "Take five hundred small steps.", symbol: "star.circle.fill", assetName: "badge_completions_500"),
        .init(id: "momentum-3", title: "Momentum 3", detail: "Build three days of Momentum.", symbol: "flame.fill", assetName: "badge_momentum_3"),
        .init(id: "momentum-7", title: "Momentum 7", detail: "Build seven days of Momentum.", symbol: "flame.circle.fill", assetName: "badge_momentum_7"),
        .init(id: "momentum-14", title: "Momentum 14", detail: "Build fourteen days of Momentum.", symbol: "bolt.heart.fill", assetName: "badge_momentum_14"),
        .init(id: "momentum-30", title: "Momentum 30", detail: "Build thirty days of Momentum.", symbol: "crown.fill", assetName: "badge_momentum_30"),
        .init(id: "momentum-60", title: "Momentum 60", detail: "Build sixty days of Momentum.", symbol: "medal.fill", assetName: "badge_momentum_60"),
        .init(id: "momentum-100", title: "Momentum 100", detail: "Build one hundred days of Momentum.", symbol: "trophy.fill", assetName: "badge_momentum_100"),
        .init(id: "perfect-day", title: "First Perfect Day", detail: "Complete every scheduled quest in a day.", symbol: "sun.max.fill", assetName: "badge_perfect_day"),
        .init(id: "perfect-days-5", title: "5 Perfect Days", detail: "Complete five perfect days.", symbol: "sun.max.circle.fill", assetName: "badge_perfect_days_5"),
        .init(id: "perfect-days-25", title: "25 Perfect Days", detail: "Complete twenty-five perfect days.", symbol: "sun.horizon.fill", assetName: "badge_perfect_days_25"),
        .init(id: "level-5", title: "Level 5", detail: "Reach level five.", symbol: "5.circle.fill", assetName: "badge_level_5"),
        .init(id: "level-10", title: "Level 10", detail: "Reach level ten.", symbol: "10.circle.fill", assetName: "badge_level_10"),
        .init(id: "level-20", title: "Level 20", detail: "Reach level twenty.", symbol: "20.circle.fill", assetName: "badge_level_20"),
        .init(id: "level-30", title: "Level 30", detail: "Reach level thirty.", symbol: "30.circle.fill", assetName: "badge_level_30"),
        .init(id: "level-50", title: "Level 50", detail: "Reach level fifty.", symbol: "50.circle.fill", assetName: "badge_level_50"),
        .init(id: "back-in-motion", title: "Back in Motion", detail: "Return after time away.", symbol: "arrow.uturn.forward.circle.fill", assetName: "badge_back_in_motion"),
        .init(id: "second-wind", title: "Second Wind", detail: "Return and begin again twice.", symbol: "wind", assetName: "badge_second_wind"),
        .init(id: "fresh-start", title: "Fresh Start", detail: "Choose progress again three times.", symbol: "leaf.circle.fill", assetName: "badge_fresh_start")
    ]

    func earnedIDs(
        progress: PlayerProgress,
        perfectWeek _: Bool,
        backInMotion: Bool,
        returnCount: Int = 0
    ) -> Set<String> {
        var ids: Set<String> = []
        if progress.totalCompletions >= 1 { ids.insert("first-step") }
        if progress.totalCompletions >= 5 { ids.insert("getting-started") }
        for target in [10, 50, 100, 500] where progress.totalCompletions >= target { ids.insert("completions-\(target)") }
        for target in [3, 7, 14, 30, 60, 100] where progress.longestMomentum >= target { ids.insert("momentum-\(target)") }
        if progress.perfectDays >= 1 { ids.insert("perfect-day") }
        if progress.perfectDays >= 5 { ids.insert("perfect-days-5") }
        if progress.perfectDays >= 25 { ids.insert("perfect-days-25") }
        for target in [5, 10, 20, 30, 50] where progress.level >= target { ids.insert("level-\(target)") }
        let returns = max(returnCount, backInMotion ? 1 : 0)
        if returns >= 1 { ids.insert("back-in-motion") }
        if returns >= 2 { ids.insert("second-wind") }
        if returns >= 3 { ids.insert("fresh-start") }
        return ids
    }
}

enum HabitRewardCatalog {
    static let all: [GameReward] = [
        .init(id: "terrain", levelRequired: 1, title: "Quiet Ground", detail: "A place to begin.", symbol: "circle.fill", assetName: "world_terrain_grass_01"),
        .init(id: "path", levelRequired: 2, title: "Winding Path", detail: "The next step becomes visible.", symbol: "point.topleft.down.to.point.bottomright.curvepath", assetName: "world_path_straight"),
        .init(id: "small-plant", levelRequired: 3, title: "First Sprout", detail: "Something is growing.", symbol: "leaf.fill", assetName: "world_tree_sapling"),
        .init(id: "rocks", levelRequired: 4, title: "River Stones", detail: "A grounded detail for your world.", symbol: "circle.hexagongrid.fill", assetName: "world_decor_rock_small"),
        .init(id: "small-tree", levelRequired: 5, title: "Young Tree", detail: "Your consistency takes root.", symbol: "tree.fill", assetName: "world_tree_young"),
        .init(id: "medium-plant", levelRequired: 6, title: "Wildflowers", detail: "Color returns to the path.", symbol: "camera.macro", assetName: "world_flower_mixed"),
        .init(id: "bench", levelRequired: 7, title: "Resting Bench", detail: "Progress includes rest.", symbol: "chair.lounge.fill", assetName: "world_structure_bench"),
        .init(id: "lantern", levelRequired: 8, title: "Trail Lantern", detail: "A little more of the way is lit.", symbol: "light.beacon.max.fill", assetName: "world_structure_lantern"),
        .init(id: "round-bush", levelRequired: 9, title: "Garden Bush", detail: "The clearing fills in.", symbol: "leaf.circle.fill", assetName: "world_bush_round"),
        .init(id: "large-tree", levelRequired: 10, title: "Shelter Tree", detail: "Your world has a canopy.", symbol: "tree.circle.fill", assetName: "world_tree_large"),
        .init(id: "fence", levelRequired: 11, title: "Garden Fence", detail: "A boundary for what is growing.", symbol: "rectangle.split.3x1", assetName: "world_structure_fence_wood"),
        .init(id: "cabin", levelRequired: 12, title: "Small Haven", detail: "A steady place along the path.", symbol: "house.fill", assetName: "world_structure_cabin"),
        .init(id: "birdhouse", levelRequired: 13, title: "Birdhouse", detail: "A small welcome for visitors.", symbol: "bird.fill", assetName: "world_structure_birdhouse"),
        .init(id: "butterfly", levelRequired: 14, title: "Butterfly", detail: "The first wildlife arrives.", symbol: "butterfly.fill", assetName: "world_animal_butterfly"),
        .init(id: "hills", levelRequired: 15, title: "Distant Hills", detail: "The horizon opens.", symbol: "mountain.2.fill", assetName: "world_background_forest"),
        .init(id: "garden-bed", levelRequired: 16, title: "Garden Bed", detail: "There is room to tend new things.", symbol: "square.grid.3x3.fill", assetName: "world_structure_garden_bed"),
        .init(id: "bird", levelRequired: 17, title: "Bluebird", detail: "A bright visitor settles in.", symbol: "bird.fill", assetName: "world_animal_bird"),
        .init(id: "bridge", levelRequired: 18, title: "Wooden Bridge", detail: "The path reaches farther.", symbol: "water.waves", assetName: "world_structure_bridge_wood"),
        .init(id: "flowering-tree", levelRequired: 19, title: "Flowering Tree", detail: "The canopy comes into bloom.", symbol: "tree.fill", assetName: "world_tree_flowering"),
        .init(id: "mountains", levelRequired: 20, title: "Mountain Horizon", detail: "Accumulated progress changes the view.", symbol: "mountain.2.circle.fill", assetName: "world_background_mountains"),
        .init(id: "pond", levelRequired: 22, title: "Lily Pond", detail: "Still water joins the clearing.", symbol: "drop.circle.fill", assetName: "world_water_pond"),
        .init(id: "rabbit", levelRequired: 24, title: "Garden Rabbit", detail: "The world feels more alive.", symbol: "hare.fill", assetName: "world_animal_rabbit"),
        .init(id: "stars", levelRequired: 25, title: "Evening Sparkles", detail: "A quiet glow for the world you built.", symbol: "sparkles", assetName: "effect_sparkle_02"),
        .init(id: "stone-bridge", levelRequired: 27, title: "Stone Bridge", detail: "A lasting crossing appears.", symbol: "water.waves", assetName: "world_structure_bridge_stone"),
        .init(id: "fountain", levelRequired: 28, title: "Garden Fountain", detail: "The heart of the garden shines.", symbol: "drop.fill", assetName: "world_structure_fountain"),
        .init(id: "cabin-upgraded", levelRequired: 30, title: "Flourishing Haven", detail: "Your home in the clearing grows.", symbol: "house.and.flag.fill", assetName: "world_structure_cabin_upgraded"),
        .init(id: "fox", levelRequired: 32, title: "Woodland Fox", detail: "A curious visitor appears.", symbol: "pawprint.fill", assetName: "world_animal_fox"),
        .init(id: "gazebo", levelRequired: 35, title: "Garden Gazebo", detail: "A place to pause and look around.", symbol: "building.columns.fill", assetName: "world_structure_gazebo"),
        .init(id: "windmill", levelRequired: 38, title: "Garden Windmill", detail: "The clearing catches the breeze.", symbol: "fanblades.fill", assetName: "world_structure_windmill"),
        .init(id: "deer", levelRequired: 40, title: "Woodland Deer", detail: "The thriving world draws gentle company.", symbol: "pawprint.fill", assetName: "world_animal_deer"),
        .init(id: "greenhouse", levelRequired: 45, title: "Greenhouse", detail: "Growth continues in every season.", symbol: "house.lodge.fill", assetName: "world_structure_greenhouse"),
        .init(id: "observatory", levelRequired: 50, title: "Observatory", detail: "The path now reaches the stars.", symbol: "telescope.fill", assetName: "world_structure_observatory")
    ]
}
