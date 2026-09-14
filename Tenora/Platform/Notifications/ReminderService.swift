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
    private var lastSignature: Data?
    private var lastDay: Date?
    private var lastZone: String?
    private var lastStatus: UNAuthorizationStatus?

    func configure() {
        center.delegate = self
        let taskCategory = UNNotificationCategory(identifier: "TASK", actions: [
            UNNotificationAction(identifier: "DONE", title: "Done", options: []),
            UNNotificationAction(identifier: "LATER", title: "Later", options: []),
            UNNotificationAction(identifier: "TOMORROW", title: "Tomorrow", options: []),
            UNNotificationAction(identifier: "OPEN", title: "Open", options: [.foreground])
        ], intentIdentifiers: [], options: [])
        let justStartCategory = UNNotificationCategory(identifier: "JUST_START", actions: [
            UNNotificationAction(identifier: "KEEP_GOING", title: "Keep going", options: []),
            UNNotificationAction(identifier: "DONE_FOR_NOW", title: "Done for now", options: []),
            UNNotificationAction(identifier: "DONE", title: "Complete task", options: [])
        ], intentIdentifiers: [], options: [])
        let transitionCategory = UNNotificationCategory(identifier: "TRANSITION", actions: [
            UNNotificationAction(identifier: "OPEN", title: "Open Tenora", options: [.foreground])
        ], intentIdentifiers: [], options: [])
        center.setNotificationCategories([taskCategory, justStartCategory, transitionCategory])
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
            guard [.authorized, .provisional, .ephemeral].contains(status) else { lastSignature = nil; return }
            let signature = try? JSONEncoder().encode(snapshot)
            let day = Calendar.current.startOfDay(for: Date())
            let zone = TimeZone.current.identifier
            if signature == lastSignature && day == lastDay && zone == lastZone && status == lastStatus {
                if currentRevision != revision { continue }
                return
            }
            let pending = await center.pendingNotificationRequests()
            center.removePendingNotificationRequests(withIdentifiers: pending.filter { $0.identifier.hasPrefix("tenora.reminder.") }.map(\.identifier))
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
                do { try await center.add(UNNotificationRequest(identifier: "tenora.reminder.\(reminder.taskID).\(index)", content: content, trigger: trigger)) }
                catch { errorMessage = "Some reminders couldn't be scheduled. Open Tenora to try again." }
            }
            if errorMessage == nil { lastSignature = signature; lastDay = day; lastZone = zone; lastStatus = status }
            if currentRevision == revision { break }
        } while true
    }

    func synchronizeJustStart(tasks: [TenoraTask]) async {
        await refreshStatus()
        let sessions = tasks.filter { ![.completed, .archived].contains($0.status) && $0.justStartEndsAt != nil }
        let identifiers = Set(sessions.map { "tenora.juststart.\($0.id)" })
        let pending = await center.pendingNotificationRequests()
        let stale = pending.filter { $0.identifier.hasPrefix("tenora.juststart.") && !identifiers.contains($0.identifier) }.map(\.identifier)
        if !stale.isEmpty { center.removePendingNotificationRequests(withIdentifiers: stale) }
        let delivered = await center.deliveredNotifications()
        let obsoleteDelivered = delivered.filter { $0.request.identifier.hasPrefix("tenora.juststart.") && !identifiers.contains($0.request.identifier) }.map { $0.request.identifier }
        if !obsoleteDelivered.isEmpty { center.removeDeliveredNotifications(withIdentifiers: obsoleteDelivered) }
        guard [.authorized, .provisional, .ephemeral].contains(status) else { return }
        let existing = Set(pending.map(\.identifier))
        for task in sessions {
            let identifier = "tenora.juststart.\(task.id)"
            guard !existing.contains(identifier), let end = task.justStartEndsAt, end > Date() else { continue }
            let content = UNMutableNotificationContent()
            content.title = "Your short start is complete"
            content.body = "Keep going, stop here for now, or complete the task."
            content.sound = .default
            content.categoryIdentifier = "JUST_START"
            content.userInfo = ["taskID": task.id.uuidString]
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, end.timeIntervalSinceNow), repeats: false)
            do { try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)) }
            catch { errorMessage = "Tenora couldn't schedule the end of this short session." }
        }
    }

    func synchronizeTransitions(plans: [TransitionPlan]) async {
        await refreshStatus()
        let prefix = "tenora.transition."
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.filter { $0.identifier.hasPrefix(prefix) }.map(\.identifier))
        guard [.authorized, .provisional, .ephemeral].contains(status) else { return }
        let now = Date()
        for plan in plans {
            let safeID = plan.eventID.data(using: .utf8)?.base64EncodedString() ?? plan.eventID
            if plan.wrapUpLeadMinutes > 0, plan.wrapUpAt > now {
                await addTransition(identifier: "\(prefix)\(safeID).wrap", date: plan.wrapUpAt,
                                    title: "Start wrapping up", body: "\(plan.eventTitle) is coming up. Tenora is holding what you were doing.")
            }
            if plan.leaveAt > now {
                await addTransition(identifier: "\(prefix)\(safeID).leave", date: plan.leaveAt,
                                    title: plan.leaveLeadMinutes == 0 ? "It’s time for \(plan.eventTitle)" : "Leave for \(plan.eventTitle)",
                                    body: "You planned this transition ahead of time.")
            }
        }
    }

    private func addTransition(identifier: String, date: Date, title: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = "TRANSITION"
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, date.timeIntervalSinceNow), repeats: false)
        do { try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)) }
        catch { errorMessage = "Some transition reminders couldn't be scheduled." }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let value = response.notification.request.content.userInfo["taskID"] as? String, let id = UUID(uuidString: value) else { return }
        let action = response.actionIdentifier
        await process(id: id, action: action)
    }

    private func process(id: UUID, action: String) async {
        if action == UNNotificationDefaultActionIdentifier || action == "OPEN" { openedTaskID = id; return }
        guard ["DONE", "LATER", "TOMORROW", "KEEP_GOING", "DONE_FOR_NOW"].contains(action) else { return }
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
