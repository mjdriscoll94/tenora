import SwiftUI
import UIKit

struct CalendarSettingsView: View {
    @EnvironmentObject private var calendarStore: CalendarStore
    @Environment(\.openURL) private var openURL
    @AppStorage(AttentionPreferences.useAllCalendarsKey) private var useAllCalendars = true
    @AppStorage(AttentionPreferences.meetingBufferMinutesKey) private var meetingBufferMinutes = 0
    @AppStorage(AttentionPreferences.minimumGapMinutesKey) private var minimumGapMinutes = 15
    @State private var selectedCalendarIDs = AttentionPreferences.selectedCalendarIDs

    var body: some View {
        Form {
            Section {
                LabeledContent("Status", value: statusText)
                connectionAction
            } header: {
                Text("Connection")
            } footer: {
                Text("Tenora reads calendars already connected to Apple Calendar, including iCloud, Google, and Outlook. Calendar details stay on this device.")
            }

            if calendarStore.authorization == .fullAccess {
                Section {
                    Picker("Meeting buffer", selection: $meetingBufferMinutes) {
                        Text("None").tag(0)
                        Text("5 minutes").tag(5)
                        Text("10 minutes").tag(10)
                        Text("15 minutes").tag(15)
                        Text("30 minutes").tag(30)
                    }
                    Picker("Minimum usable gap", selection: $minimumGapMinutes) {
                        Text("Any length").tag(0)
                        Text("10 minutes").tag(10)
                        Text("15 minutes").tag(15)
                        Text("30 minutes").tag(30)
                        Text("45 minutes").tag(45)
                    }
                } header: {
                    Text("Availability")
                } footer: {
                    Text("Buffers protect transition time around meetings. Gaps shorter than your minimum are not offered for task work.")
                }

                Section {
                    Toggle("Use all calendars", isOn: $useAllCalendars)
                    if !useAllCalendars {
                        ForEach(calendarStore.availableCalendars) { calendar in
                            Toggle(isOn: selectionBinding(calendar.id)) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(calendar.title)
                                    Text(calendar.sourceTitle).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Calendars")
                } footer: {
                    Text("Only events from selected calendars block time. At least one calendar must remain selected.")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(TenoraScreenBackground())
        .tint(.tenoraForest)
        .navigationTitle("Calendar")
        .task {
            await calendarStore.refresh()
            if selectedCalendarIDs.isEmpty {
                selectedCalendarIDs = Set(calendarStore.availableCalendars.map(\.id))
            }
        }
        .onChange(of: useAllCalendars) { _, newValue in
            if !newValue, selectedCalendarIDs.isEmpty {
                selectedCalendarIDs = Set(calendarStore.availableCalendars.map(\.id))
                AttentionPreferences.saveSelectedCalendarIDs(selectedCalendarIDs)
            }
            refresh()
        }
        .onChange(of: meetingBufferMinutes) { _, _ in refresh() }
        .onChange(of: minimumGapMinutes) { _, _ in refresh() }
    }

    @ViewBuilder
    private var connectionAction: some View {
        switch calendarStore.authorization {
        case .notDetermined:
            Button("Allow Calendar Access") { Task { await calendarStore.requestAccess() } }
        case .fullAccess:
            Button("Refresh calendars") { Task { await calendarStore.refresh() } }
        case .denied, .restricted, .writeOnly:
            Button("Open iOS Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
        }
    }

    private var statusText: String {
        switch calendarStore.authorization {
        case .notDetermined: "Not connected"
        case .fullAccess: "Connected"
        case .writeOnly: "Read access needed"
        case .denied: "Access denied"
        case .restricted: "Restricted"
        }
    }

    private func selectionBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { selectedCalendarIDs.contains(id) },
            set: { selected in
                if selected {
                    selectedCalendarIDs.insert(id)
                } else if selectedCalendarIDs.count > 1 {
                    selectedCalendarIDs.remove(id)
                }
                AttentionPreferences.saveSelectedCalendarIDs(selectedCalendarIDs)
                refresh()
            }
        )
    }

    private func refresh() {
        Task { await calendarStore.refresh() }
    }
}
