import SwiftUI

struct InboxView: View {
    @EnvironmentObject private var taskStore: TaskStore

    var body: some View {
        Group {
            if taskStore.inboxTasks.isEmpty {
                ContentUnavailableView(
                    "Nothing waiting",
                    systemImage: "tray",
                    description: Text("Capture something once. Tenora will hold onto it.")
                )
            } else {
                List(taskStore.inboxTasks) { task in
                    HStack(spacing: 12) {
                        Button {
                            Task { await taskStore.complete(task) }
                        } label: {
                            Image(systemName: "circle")
                                .font(.title3)
                                .foregroundStyle(Color.tenoraCopper)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Complete \(task.title)")

                        NavigationLink { TaskDetailView(task: task) } label: { VStack(alignment: .leading, spacing: 3) {
                            Text(task.title)
                            if !task.notes.isEmpty {
                                Text(task.notes)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            if let date = task.scheduledDate {
                                Text(date, style: .date).font(.caption).foregroundStyle(.secondary)
                            }
                        } }
                    }
                    .padding(.vertical, 7)
                    .listRowBackground(Color.tenoraCard)
                    .listRowSeparatorTint(Color.tenoraSage.opacity(0.35))
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button {
                            Task { await taskStore.complete(task) }
                        } label: {
                            Label("Done", systemImage: "checkmark")
                        }
                        .tint(.tenoraForest)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button {
                            Task { await taskStore.postpone(task) }
                        } label: {
                            Label("Not now", systemImage: "clock.arrow.circlepath")
                        }
                        .tint(.tenoraSage)

                        Button {
                            Task { await taskStore.setKeepInFrontToday(!task.isKeptInFront(at: Date()), for: task.id) }
                        } label: {
                            Label(
                                task.isKeptInFront(at: Date()) ? "Unpin Today" : "Keep Today",
                                systemImage: task.isKeptInFront(at: Date()) ? "pin.slash" : "pin"
                            )
                        }
                        .tint(.tenoraCopper)
                    }
                    .contextMenu {
                        Button {
                            Task { await taskStore.start(task) }
                        } label: {
                            Label(taskStore.focusedTaskID == task.id ? "Resume" : "Start", systemImage: "play.fill")
                        }

                        Button {
                            Task { await taskStore.setKeepInFrontToday(!task.isKeptInFront(at: Date()), for: task.id) }
                        } label: {
                            Label(
                                task.isKeptInFront(at: Date()) ? "Stop keeping in front" : "Keep in front today",
                                systemImage: task.isKeptInFront(at: Date()) ? "pin.slash" : "pin"
                            )
                        }

                        Button {
                            Task { await taskStore.postpone(task) }
                        } label: {
                            Label("Not now", systemImage: "clock.arrow.circlepath")
                        }

                        Button(role: .destructive) {
                            Task { await taskStore.complete(task) }
                        } label: {
                            Label("Done", systemImage: "checkmark.circle")
                        }
                    }
                    .accessibilityAction(named: "Done") {
                        Task { await taskStore.complete(task) }
                    }
                    .accessibilityAction(named: "Not now") {
                        Task { await taskStore.postpone(task) }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(TenoraScreenBackground())
        .navigationTitle("Inbox")
        .overlay(alignment: .bottom) {
            if let errorMessage = taskStore.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .padding(10)
                    .background(.regularMaterial, in: Capsule())
                    .padding()
            }
        }
    }
}
