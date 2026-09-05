import Foundation
import UserNotifications
import UIKit

@MainActor
final class ReminderService: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = ReminderService()
    @Published private(set) var status: UNAuthorizationStatus = .notDetermined
    @Published private(set) var errorMessage: String?
    @Published var openedTaskID: UUID?
    var handleAction: ((UUID, String) async -> Bool)?
    private let center = UNUserNotificationCenter.current()
    private var synchronizing = false
    private var latestTasks: [TenoraTask] = []
    private var revision = 0

    func configure() {
        center.delegate = self
        center.setNotificationCategories([UNNotificationCategory(identifier: "TASK", actions: [
            UNNotificationAction(identifier: "DONE", title: "Done", options: []),
            UNNotificationAction(identifier: "LATER", title: "Later", options: []),
            UNNotificationAction(identifier: "TOMORROW", title: "Tomorrow", options: []),
            UNNotificationAction(identifier: "OPEN", title: "Open", options: [.foreground])
        ], intentIdentifiers: [], options: [])])
    }

    func requestAccess() async {
        do { _ = try await center.requestAuthorization(options: [.alert, .sound]) }
        catch { errorMessage = "Reminders couldn't be enabled. Try again in Settings." }
        await refreshStatus()
    }

    func refreshStatus() async { status = await center.notificationSettings().authorizationStatus }

    func synchronize(tasks: [TenoraTask]) async {
        latestTasks = tasks
        revision += 1
        guard !synchronizing else { return }
        synchronizing = true
        defer { synchronizing = false }
        repeat {
            let currentRevision = revision
            let snapshot = latestTasks
            await refreshStatus()
            guard [.authorized, .provisional, .ephemeral].contains(status) else { return }
            let pending = await center.pendingNotificationRequests()
            center.removePendingNotificationRequests(withIdentifiers: pending.filter { $0.identifier.hasPrefix("tenora.") }.map(\.identifier))
            let delivered = await center.deliveredNotifications()
            let unresolved = Set(snapshot.filter { ![.completed, .archived].contains($0.status) }.map { $0.id.uuidString })
            center.removeDeliveredNotifications(withIdentifiers: delivered.filter {
                guard let id = $0.request.content.userInfo["taskID"] as? String else { return false }
                return !unresolved.contains(id)
            }.map { $0.request.identifier })
            errorMessage = nil
            let now = Date()
            let oldSlots = UserDefaults.standard.array(forKey: "reminderReservations") as? [Date] ?? []
            let used = oldSlots.filter { $0 <= now && $0 >= Calendar.current.startOfDay(for: now) }
            let plan = ReminderPlanner().plan(tasks: snapshot, now: now, usedSlots: used)
            // Slots already due remain spent even when tasks change or a notification is dismissed.
            UserDefaults.standard.set(used + plan.map(\.date), forKey: "reminderReservations")
            for (index, reminder) in plan.enumerated() {
                let content = UNMutableNotificationContent()
                content.title = reminder.title
                content.body = "Still on your mind? Choose Done, Later, or Tomorrow."
                content.sound = .default
                content.categoryIdentifier = "TASK"
                content.userInfo = ["taskID": reminder.taskID.uuidString]
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, reminder.date.timeIntervalSinceNow), repeats: false)
                do { try await center.add(UNNotificationRequest(identifier: "tenora.\(reminder.taskID).\(index)", content: content, trigger: trigger)) }
                catch { errorMessage = "Some reminders couldn't be scheduled. Open Tenora to try again." }
            }
            if currentRevision == revision { break }
        } while true
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let value = response.notification.request.content.userInfo["taskID"] as? String, let id = UUID(uuidString: value) else { return }
        let action = response.actionIdentifier
        await process(id: id, action: action)
    }

    private func process(id: UUID, action: String) async {
        if action == UNNotificationDefaultActionIdentifier || action == "OPEN" { openedTaskID = id; return }
        guard ["DONE", "LATER", "TOMORROW"].contains(action) else { return }
        if await handleAction?(id, action) != true {
            // Keep the requested decision across a failed save or cold launch.
            var queued = UserDefaults.standard.array(forKey: "pendingReminderActions") as? [[String: String]] ?? []
            queued.append(["id": id.uuidString, "action": action])
            UserDefaults.standard.set(queued, forKey: "pendingReminderActions")
            errorMessage = "Open Tenora to finish saving your reminder decision."
        }
    }

    func drainActions() async {
        let queued = UserDefaults.standard.array(forKey: "pendingReminderActions") as? [[String: String]] ?? []
        UserDefaults.standard.removeObject(forKey: "pendingReminderActions")
        for entry in queued {
            if let value = entry["id"], let id = UUID(uuidString: value), let action = entry["action"] { await process(id: id, action: action) }
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions { [.banner, .sound] }
}

final class TenoraAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        ReminderService.shared.configure()
        return true
    }
}
