import Foundation

struct WorkDay: Codable, Equatable, Identifiable, Sendable {
    /// Calendar weekday: Sunday = 1, Saturday = 7. A shift belongs to its starting day.
    var weekday: Int
    var isEnabled: Bool = true
    var startMinute: Int = 480
    var endMinute: Int = 1080
    var id: Int { weekday }
    var endsNextDay: Bool { endMinute <= startMinute || endMinute == 1440 }
    var isValid: Bool { (1...7).contains(weekday) && (0..<1440).contains(startMinute) && (0...1440).contains(endMinute) }

    func interval(on day: Date, calendar: Calendar) -> DateInterval? {
        guard isEnabled, isValid else { return nil }
        let dayStart = calendar.startOfDay(for: day)
        guard let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart),
              let start = calendar.date(bySettingHour: startMinute / 60, minute: startMinute % 60, second: 0, of: dayStart) else { return nil }
        let endDay = endsNextDay ? nextDay : dayStart
        guard let end = calendar.date(bySettingHour: (endMinute % 1440) / 60, minute: endMinute % 60, second: 0, of: endDay), end > start else { return nil }
        return DateInterval(start: start, end: end)
    }
}

struct WorkingSchedule: Codable, Equatable, Sendable {
    var days: [WorkDay]

    init(hours: WorkingHours = WorkingHours()) {
        days = (1...7).map { WorkDay(weekday: $0, startMinute: hours.startHour * 60, endMinute: hours.endHour * 60) }
    }

    var isValid: Bool { days.count == 7 && Set(days.map(\.weekday)).count == 7 && days.allSatisfy(\.isValid) }

    func day(_ weekday: Int) -> WorkDay {
        days.first { $0.weekday == weekday } ?? WorkDay(weekday: weekday, isEnabled: false)
    }

    /// Includes yesterday's overnight shift and shifts starting today, merging overlaps.
    func intervals(around date: Date, calendar: Calendar = .current) -> [DateInterval] {
        guard isValid else { return [] }
        let today = calendar.startOfDay(for: date)
        let dates = [-1, 0].compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
        let intervals = dates.compactMap { day(calendar.component(.weekday, from: $0)).interval(on: $0, calendar: calendar) }
            .filter { $0.end > today }.sorted { $0.start < $1.start }
        var merged: [DateInterval] = []
        for interval in intervals {
            if let last = merged.last, interval.start <= last.end {
                merged[merged.count - 1] = DateInterval(start: last.start, end: max(last.end, interval.end))
            } else { merged.append(interval) }
        }
        return merged
    }

    func isWorking(at date: Date, calendar: Calendar = .current) -> Bool {
        intervals(around: date, calendar: calendar).contains { $0.start <= date && date < $0.end }
    }
}
