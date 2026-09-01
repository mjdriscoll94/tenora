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
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Complete \(task.title)")

                        VStack(alignment: .leading, spacing: 3) {
                            Text(task.title)
                            if !task.notes.isEmpty {
                                Text(task.notes)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
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

