import Foundation

enum AttentionPreferences {
    static let scheduleKey = "workingSchedule.v1"
    static let capacityModeKey = "attention.capacityMode"
    static let capacitySelectedAtKey = "attention.capacitySelectedAt"
    static var schedule: WorkingSchedule { schedule(from: UserDefaults.standard.string(forKey: scheduleKey) ?? "") }

    static func schedule(from json: String, fallback: WorkingHours? = nil) -> WorkingSchedule {
        if let data = json.data(using: .utf8), let decoded = try? JSONDecoder().decode(WorkingSchedule.self, from: data), decoded.isValid { return decoded }
        return WorkingSchedule(hours: fallback ?? workingHours)
    }

    static var workingHours: WorkingHours {
        let defaults = UserDefaults.standard
        let start = defaults.object(forKey: "workStart") as? Int ?? 8
        let end = defaults.object(forKey: "workEnd") as? Int ?? 18
        guard (0...23).contains(start), (1...24).contains(end), start < end else { return WorkingHours() }
        return WorkingHours(startHour: start, endHour: end)
    }

    static func capacityMode(rawValue: String, selectedAt: Double, now: Date, calendar: Calendar = .current) -> TaskCapacityMode {
        guard selectedAt > 0,
              calendar.isDate(Date(timeIntervalSince1970: selectedAt), inSameDayAs: now),
              let mode = TaskCapacityMode(rawValue: rawValue) else { return .balanced }
        return mode
    }
}
