import SwiftUI
import UIKit

struct ReminderSettingsView: View {
    @EnvironmentObject private var store: TaskStore
    @Environment(\.openURL) private var openURL
    @ObservedObject private var reminders = ReminderService.shared
    @AppStorage(AttentionPreferences.taskRemindersEnabledKey) private var taskRemindersEnabled = true
    @AppStorage(AttentionPreferences.reminderLevelKey) private var reminderLevelRaw = ReminderLevel.standard.rawValue
    @AppStorage(AttentionPreferences.reminderStartMinuteKey) private var startMinute = 9 * 60
    @AppStorage(AttentionPreferences.reminderEndMinuteKey) private var endMinute = 20 * 60

    var body: some View {
        Form {
            Section {
                Toggle("Allow task reminders", isOn: $taskRemindersEnabled)
                LabeledContent("System permission", value: permissionText)
                if !permissionGranted {
                    Button("Enable notifications") { Task { await reminders.requestAccess(); await reschedule() } }
                }
                Button("Open notification settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            } header: {
                Text("Task reminders")
            } footer: {
                Text("Just Start and calendar transition alerts remain available when they are explicitly requested. This switch controls automatic unfinished-task reminders.")
            }

            Section {
                Picker("Reminder level", selection: $reminderLevelRaw) {
                    ForEach(ReminderLevel.allCases) { level in
                        Text("\(level.title) · up to \(level.dailyLimit)/day").tag(level.rawValue)
                    }
                }
            } header: {
                Text("Frequency")
            } footer: {
                Text("Tenora spaces automatic reminders at least two hours apart and plans no more than seven days ahead.")
            }

            Section {
                DatePicker("Start", selection: minuteBinding($startMinute, other: $endMinute, isStart: true), displayedComponents: .hourAndMinute)
                DatePicker("End", selection: minuteBinding($endMinute, other: $startMinute, isStart: false), displayedComponents: .hourAndMinute)
            } header: {
                Text("Delivery hours")
            } footer: {
                Text("Automatic task reminders stay inside this window. Your working schedule is configured separately.")
            }

            if let error = reminders.errorMessage {
                Section { Text(error).foregroundStyle(.secondary) }
            }
        }
        .scrollContentBackground(.hidden)
        .background(TenoraScreenBackground())
        .tint(.tenoraForest)
        .navigationTitle("Reminders")
        .task { await reminders.refreshStatus() }
        .onChange(of: taskRemindersEnabled) { _, enabled in
            Task {
                if enabled, !permissionGranted { await reminders.requestAccess() }
                await reschedule()
            }
        }
        .onChange(of: reminderLevelRaw) { _, _ in Task { await reschedule() } }
        .onChange(of: startMinute) { _, _ in Task { await reschedule() } }
        .onChange(of: endMinute) { _, _ in Task { await reschedule() } }
    }

    private var permissionGranted: Bool {
        reminders.status == .authorized || reminders.status == .provisional || reminders.status == .ephemeral
    }

    private var permissionText: String {
        switch reminders.status {
        case .authorized, .provisional, .ephemeral: "Allowed"
        case .denied: "Denied"
        case .notDetermined: "Not requested"
        @unknown default: "Unavailable"
        }
    }

    private func minuteBinding(_ value: Binding<Int>, other: Binding<Int>, isStart: Bool) -> Binding<Date> {
        Binding(
            get: { Self.timeDate(value.wrappedValue) },
            set: { date in
                let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                let minute = (components.hour ?? 0) * 60 + (components.minute ?? 0)
                if isStart {
                    value.wrappedValue = min(minute, max(0, other.wrappedValue - 30))
                } else {
                    value.wrappedValue = max(minute, min(23 * 60 + 30, other.wrappedValue + 30))
                }
            }
        )
    }

    private static func timeDate(_ minutes: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: 2001, month: 1, day: 15, hour: minutes / 60, minute: minutes % 60)) ?? Date()
    }

    private func reschedule() async {
        await reminders.synchronize(tasks: store.tasks.filter { $0.id != store.focusedTaskID })
    }
}
