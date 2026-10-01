import SwiftUI

struct SettingsView: View {
    var body: some View {
        Form {
            Section {
                destination("Weekly schedule", icon: "calendar.badge.clock") { WorkingScheduleView() }
                destination("Calendar", icon: "calendar") { CalendarSettingsView() }
                destination("Reminders", icon: "bell") { ReminderSettingsView() }
                destination("Recovery", icon: "arrow.uturn.backward.circle") { RecoverySettingsView() }
            }

            Section {
                destination("Data & Privacy", icon: "hand.raised") { DataPrivacySettingsView() }
                destination("About Tenora", icon: "info.circle") { AboutSettingsView() }
            }

            if TenoraFeatures.agentBridgeEnabled {
                AgentBridgeSettingsSection()
            }
        }
        .scrollContentBackground(.hidden)
        .background(TenoraScreenBackground())
        .tint(.tenoraForest)
        .navigationTitle("Settings")
    }

    private func destination<Destination: View>(
        _ title: String,
        icon: String,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            Label(title, systemImage: icon)
        }
    }
}

private struct AgentBridgeSettingsSection: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var calendarStore: CalendarStore
    @ObservedObject private var bridge = AgentBridgeSyncService.shared

    var body: some View {
        Section("ChatGPT") {
            if bridge.configuration == nil {
                Text("ChatGPT access is included, but this build still needs its server and sign-in settings.")
                Text("Configure TENORA_BRIDGE_URL, TENORA_OAUTH_ISSUER, and TENORA_OAUTH_CLIENT_ID before distribution.")
                    .font(.footnote).foregroundStyle(.secondary)
            } else if !bridge.isConnected {
                if bridge.isWarmingUp {
                    Label("Preparing secure connection…", systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Button(bridge.isConnecting ? "Opening secure sign-in…" : "Enable ChatGPT access") {
                    Task {
                        guard await bridge.connect() else { return }
                        await bridge.syncNow(tasks: store.tasks, events: calendarStore.events, focusedTaskID: store.focusedTaskID)
                    }
                }
                .disabled(bridge.isConnecting)
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
        .task { await bridge.warmUp() }
    }
}
