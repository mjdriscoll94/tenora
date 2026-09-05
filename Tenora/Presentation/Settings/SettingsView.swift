import SwiftUI
import UIKit

struct SettingsView: View {
    @AppStorage("workStart") private var workStart = 8
    @AppStorage("workEnd") private var workEnd = 18
    @EnvironmentObject private var store: TaskStore
    @ObservedObject private var reminders = ReminderService.shared
    @Environment(\.openURL) private var openURL

    var body: some View {
        Form {
            Section("Working hours") {
                Picker("Start", selection: $workStart) {
                    ForEach(0..<workEnd, id: \.self) { Text(String(format: "%02d:00", $0)).tag($0) }
                }
                Picker("End", selection: $workEnd) {
                    ForEach((workStart + 1)...24, id: \.self) { Text(String(format: "%02d:00", $0)).tag($0) }
                }
                Text("NOW rests outside these hours. Reminder quiet hours are separate.").font(.footnote)
            }
            Section("Reminders") {
                Text("Tenora can bring unfinished tasks back while the app is closed.")
                Button("Enable reminders") {
                    Task { await reminders.requestAccess(); await store.load() }
                }
                Text("Up to three per day, between 9 AM and 8 PM. Opening Tenora refreshes the next seven days of reminders.")
                    .font(.footnote).foregroundStyle(.secondary)
                Text(reminders.status == .authorized || reminders.status == .provisional ? "Notifications allowed" : "Notifications are not enabled")
                Button("Notification settings") { openURL(URL(string: UIApplication.openSettingsURLString)!) }
                if let error = reminders.errorMessage { Text(error) }
            }
        }.navigationTitle("Settings").task { await reminders.refreshStatus() }
    }
}
