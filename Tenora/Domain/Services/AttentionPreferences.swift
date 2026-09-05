import Foundation

enum AttentionPreferences {
    static var workingHours: WorkingHours {
        let defaults = UserDefaults.standard
        let start = defaults.object(forKey: "workStart") as? Int ?? 8
        let end = defaults.object(forKey: "workEnd") as? Int ?? 18
        guard (0...23).contains(start), (1...24).contains(end), start < end else { return WorkingHours() }
        return WorkingHours(startHour: start, endHour: end)
    }
}
