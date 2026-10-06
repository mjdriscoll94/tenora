import XCTest
@testable import Tenora

final class HabitGameEngineTests: XCTestCase {
    private let engine = HabitGameEngine()
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "America/Chicago")!
        return value
    }

    private func date(_ day: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    func testDifficultyAwardsAreCentralized() {
        XCTAssertEqual(engine.xpAward(for: .easy), 10)
        XCTAssertEqual(engine.xpAward(for: .standard), 20)
        XCTAssertEqual(engine.xpAward(for: .challenging), 30)
    }

    func testLevelCurveAndMultipleLevelGain() {
        XCTAssertEqual(engine.levelProgress(totalXP: 99).level, 1)
        XCTAssertEqual(engine.levelProgress(totalXP: 100).level, 2)
        let progress = engine.levelProgress(totalXP: 100 + 125 + 150 + 25)
        XCTAssertEqual(progress.level, 4)
        XCTAssertEqual(progress.current, 25)
        XCTAssertEqual(progress.required, 175)
    }

    func testScheduledWeekdaysAndCustomInterval() {
        var weekdays = Habit(name: "Weekdays", createdAt: date(1))
        weekdays.schedule = HabitSchedule(type: .specificWeekdays, weekdays: [2, 4, 6])
        XCTAssertTrue(engine.scheduleCalculator.isScheduled(weekdays, on: date(2), calendar: calendar)) // Friday
        XCTAssertFalse(engine.scheduleCalculator.isScheduled(weekdays, on: date(3), calendar: calendar))

        var custom = Habit(name: "Alternate", createdAt: date(1))
        custom.schedule = HabitSchedule(type: .custom, intervalDays: 2)
        XCTAssertTrue(engine.scheduleCalculator.isScheduled(custom, on: date(1), calendar: calendar))
        XCTAssertFalse(engine.scheduleCalculator.isScheduled(custom, on: date(2), calendar: calendar))
        XCTAssertTrue(engine.scheduleCalculator.isScheduled(custom, on: date(3), calendar: calendar))
    }

    func testTimesPerWeekStaysVisibleOnCompletionDayThenStopsAtTarget() {
        var habit = Habit(name: "Exercise", createdAt: date(1))
        habit.schedule = HabitSchedule(type: .timesPerWeek, weeklyTarget: 1)
        let completion = HabitCompletion(habitID: habit.id, completionDate: date(1), xpAwarded: 20)
        XCTAssertTrue(engine.scheduleCalculator.isScheduled(habit, on: date(1), completions: [completion], calendar: calendar))
        XCTAssertFalse(engine.scheduleCalculator.isScheduled(habit, on: date(2), completions: [completion], calendar: calendar))
    }

    func testFiftyPercentKeepsMomentumAndFullCompletionIsPerfect() {
        let first = Habit(name: "Read", createdAt: date(1))
        let second = Habit(name: "Walk", createdAt: date(1))
        let half = [HabitCompletion(habitID: first.id, completionDate: date(1), xpAwarded: 10)]
        let summary = engine.daySummary(habits: [first, second], completions: half, on: date(1), calendar: calendar)
        XCTAssertTrue(summary.keepsMomentum)
        XCTAssertFalse(summary.isPerfect)

        let full = half + [HabitCompletion(habitID: second.id, completionDate: date(1), xpAwarded: 10)]
        XCTAssertTrue(engine.daySummary(habits: [first, second], completions: full, on: date(1), calendar: calendar).isPerfect)
    }

    func testMomentumContinuesAndResetsOnlyAfterPastMissedDay() {
        let habit = Habit(name: "Read", createdAt: date(1))
        var completions = [1, 2].map { HabitCompletion(habitID: habit.id, completionDate: date($0), xpAwarded: 10) }
        XCTAssertEqual(engine.progress(habits: [habit], completions: completions, now: date(2), calendar: calendar).currentMomentum, 2)
        XCTAssertEqual(engine.progress(habits: [habit], completions: completions, now: date(3), calendar: calendar).currentMomentum, 2, "An unfinished current day does not erase momentum early")
        XCTAssertEqual(engine.progress(habits: [habit], completions: completions, now: date(4), calendar: calendar).currentMomentum, 0)

        completions.append(HabitCompletion(habitID: habit.id, completionDate: date(4), xpAwarded: 10))
        XCTAssertEqual(engine.progress(habits: [habit], completions: completions, now: date(4), calendar: calendar).currentMomentum, 1)
    }

    func testAchievementsAndRewardUnlocking() {
        let progress = PlayerProgress(totalXP: 500, level: 5, xpIntoLevel: 0, xpForNextLevel: 200,
                                      totalCompletions: 100, currentMomentum: 7, longestMomentum: 7, perfectDays: 1)
        let ids = HabitAchievementEngine().earnedIDs(progress: progress, perfectWeek: true, backInMotion: true)
        for id in ["first-step", "getting-started", "completions-10", "completions-50", "completions-100", "momentum-3", "momentum-7", "perfect-day", "level-5", "back-in-motion"] {
            XCTAssertTrue(ids.contains(id), id)
        }
        XCTAssertFalse(ids.contains("momentum-14"))
        XCTAssertFalse(ids.contains("level-10"))
        XCTAssertTrue(HabitRewardCatalog.all.filter { $0.levelRequired <= 5 }.contains { $0.id == "small-tree" })
        XCTAssertFalse(HabitRewardCatalog.all.filter { $0.levelRequired <= 5 }.contains { $0.id == "lantern" })
    }

    func testReturnMilestonesCountDistinctGapsAndUnlockRecoveryBadges() {
        let habitID = UUID()
        let completions = [1, 2, 6, 10].map {
            HabitCompletion(habitID: habitID, completionDate: date($0), xpAwarded: 10)
        }
        let returns = engine.returningMilestoneCount(completions: completions, calendar: calendar)
        XCTAssertEqual(returns, 2)

        let progress = PlayerProgress(totalXP: 40, level: 1, xpIntoLevel: 40, xpForNextLevel: 100,
                                      totalCompletions: 4, currentMomentum: 1, longestMomentum: 2, perfectDays: 0)
        let ids = HabitAchievementEngine().earnedIDs(
            progress: progress,
            perfectWeek: false,
            backInMotion: false,
            returnCount: returns
        )
        XCTAssertTrue(ids.contains("back-in-motion"))
        XCTAssertTrue(ids.contains("second-wind"))
        XCTAssertFalse(ids.contains("fresh-start"))
    }

    func testRewardCatalogHasRegularUniqueUnlocksThroughLevelFifty() {
        XCTAssertEqual(Set(HabitRewardCatalog.all.map(\.id)).count, HabitRewardCatalog.all.count)
        XCTAssertEqual(HabitRewardCatalog.all.first?.levelRequired, 1)
        XCTAssertEqual(HabitRewardCatalog.all.last?.levelRequired, 50)
        XCTAssertTrue(HabitRewardCatalog.all.allSatisfy { $0.assetName != nil })
        for index in 1..<HabitRewardCatalog.all.count {
            XCTAssertLessThan(HabitRewardCatalog.all[index - 1].levelRequired, HabitRewardCatalog.all[index].levelRequired)
        }
    }

    func testWorldStagesFollowProgressionThresholds() {
        XCTAssertEqual(WorldStage(level: 1), .beginning)
        XCTAssertEqual(WorldStage(level: 4), .beginning)
        XCTAssertEqual(WorldStage(level: 5), .sprouting)
        XCTAssertEqual(WorldStage(level: 11), .sprouting)
        XCTAssertEqual(WorldStage(level: 12), .growing)
        XCTAssertEqual(WorldStage(level: 20), .flourishing)
        XCTAssertEqual(WorldStage(level: 30), .thriving)
        XCTAssertEqual(WorldStage(level: 50), .thriving)
    }

    func testLaterWorldUpgradesReplaceEarlierStructures() {
        let unlocked = Set(HabitRewardCatalog.all.map(\.id))
        let scene = HabitWorldCatalog.scene(unlockedRewardIDs: unlocked, level: 50, season: .summer, lighting: .day)
        let visible = Set(scene.objects.map(\.id))

        XCTAssertTrue(visible.contains("observatory"))
        XCTAssertTrue(visible.contains("stone-bridge"))
        for replaced in ["cabin", "upgraded-cabin", "greenhouse", "windmill", "bridge", "bench", "gazebo"] {
            XCTAssertFalse(visible.contains(replaced), replaced)
        }
    }

    func testRemovingCompletionRecalculatesXPPerfectDayAndCounts() {
        let habit = Habit(name: "Read", createdAt: date(1))
        let completion = HabitCompletion(habitID: habit.id, completionDate: date(1), xpAwarded: 20)
        let before = engine.progress(habits: [habit], completions: [completion], now: date(1), calendar: calendar)
        let after = engine.progress(habits: [habit], completions: [], now: date(1), calendar: calendar)
        XCTAssertEqual(before.totalXP, 20)
        XCTAssertEqual(before.perfectDays, 1)
        XCTAssertEqual(after.totalXP, 0)
        XCTAssertEqual(after.totalCompletions, 0)
        XCTAssertEqual(after.perfectDays, 0)
    }

    func testBackInMotionUsesLocalCalendarDays() {
        let previous = HabitCompletion(habitID: UUID(), completionDate: date(1, 23), xpAwarded: 10)
        XCTAssertFalse(engine.isBackInMotion(previousCompletions: [previous], completingAt: date(3, 1), calendar: calendar))
        XCTAssertTrue(engine.isBackInMotion(previousCompletions: [previous], completingAt: date(4, 1), calendar: calendar))
    }

    func testDayBoundaryUsesSelectedTimezoneRatherThanRawHours() {
        let habit = Habit(name: "Late habit", createdAt: date(1, 23))
        let completion = HabitCompletion(habitID: habit.id, completionDate: date(1, 23), xpAwarded: 10)
        XCTAssertEqual(engine.daySummary(habits: [habit], completions: [completion], on: date(1, 1), calendar: calendar).completed, 1)
        XCTAssertEqual(engine.daySummary(habits: [habit], completions: [completion], on: date(2, 1), calendar: calendar).completed, 0)
    }
}
