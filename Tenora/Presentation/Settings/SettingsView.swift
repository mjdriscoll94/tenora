import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var store: TaskStore
    @ObservedObject private var reminders = ReminderService.shared
    @ObservedObject private var bridge = AgentBridgeSyncService.shared
    @EnvironmentObject private var calendarStore: CalendarStore
    @Environment(\.openURL) private var openURL

    var body: some View {
        Form {
            Section("Working hours") {
                NavigationLink("Weekly schedule") { WorkingScheduleView() }
                Text("Set different hours for each day, including days off and overnight shifts. NOW uses your schedule; reminder quiet hours are separate.").font(.footnote)
            }
            Section("Reminders") {
                Text("Tenora can bring unfinished tasks back while the app is closed.")
                Button("Enable reminders") {
                    Task { await reminders.requestAccess(); await store.load() }
                }
                Text("Task reminders: up to three per day, between 9 AM and 8 PM. An active Just Start session adds one end prompt. Opening Tenora refreshes the next seven days of reminders.")
                    .font(.footnote).foregroundStyle(.secondary)
                Text(reminders.status == .authorized || reminders.status == .provisional ? "Notifications allowed" : "Notifications are not enabled")
                Button("Notification settings") { openURL(URL(string: UIApplication.openSettingsURLString)!) }
                if let error = reminders.errorMessage { Text(error) }
            }
            Section("ChatGPT") {
                if bridge.configuration == nil {
                    Text("ChatGPT access is included, but this build still needs its server and sign-in settings.")
                    Text("Configure TENORA_BRIDGE_URL, TENORA_OAUTH_ISSUER, and TENORA_OAUTH_CLIENT_ID before distribution.")
                        .font(.footnote).foregroundStyle(.secondary)
                } else if !bridge.isConnected {
                    Button("Enable ChatGPT access") { Task { await bridge.connect() } }
                    Text("Sign in to your Tenora account to create a private shared copy of the data you choose. Then connect Tenora from your own ChatGPT account using the same Tenora sign-in.")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    Label("Ready to connect from ChatGPT", systemImage: "checkmark.shield")
                    Text("In ChatGPT, add Tenora and sign in with the same Tenora account. Tenora never receives your ChatGPT password or API key.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Toggle("Share updates with ChatGPT", isOn: Binding(get: { bridge.sharingEnabled }, set: bridge.setSharingEnabled))
                    Toggle("Include task notes", isOn: Binding(get: { bridge.includeNotes }, set: bridge.setIncludeNotes))
                        .disabled(!bridge.sharingEnabled)
                    Toggle("Include calendar context", isOn: Binding(get: { bridge.includeCalendar }, set: bridge.setIncludeCalendar))
                        .disabled(!bridge.sharingEnabled)
                    Text("Titles, status, dates, priorities, tags, and next steps are included. Notes and calendar details stay off unless you enable them.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("Turning sharing off keeps the last shared copy. Use Delete shared data to remove it from the server.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button(bridge.isSyncing ? "Syncing…" : "Sync now") {
                        Task { await bridge.syncNow(tasks: store.tasks, events: calendarStore.events, focusedTaskID: store.focusedTaskID) }
                    }.disabled(!bridge.sharingEnabled || bridge.isSyncing)
                    if let date = bridge.lastSyncedAt { Text("Last synced \(date.formatted(.relative(presentation: .named)))").font(.footnote) }
                    Button("Delete shared data and disconnect", role: .destructive) {
                        Task { await bridge.deleteSharedDataAndDisconnect() }
                    }
                    Button("Sign out on this device") { bridge.disconnect() }
                }
                if let error = bridge.errorMessage { Text(error).foregroundStyle(.secondary) }
            }
        }.navigationTitle("Settings").task { await reminders.refreshStatus() }
    }
}
