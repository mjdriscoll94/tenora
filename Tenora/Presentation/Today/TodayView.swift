import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var taskStore: TaskStore

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                nowSection

                if !remainingResurfacedTasks.isEmpty {
                    resurfacedSection
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .navigationTitle("Today")
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

    @ViewBuilder
    private var nowSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("NOW")

            if let task = taskStore.nowRecommendation {
                VStack(alignment: .leading, spacing: 16) {
                    Text(task.title)
                        .font(.title2.weight(.semibold))

                    if let duration = task.estimatedDurationMinutes {
                        Label("About \(duration) minutes", systemImage: "clock")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Button("Complete") {
                            Task { await taskStore.complete(task) }
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Later") {
                            Task { await taskStore.postpone(task) }
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
                .accessibilityElement(children: .contain)
            } else {
                ContentUnavailableView(
                    "Nothing needs you right now",
                    systemImage: "checkmark.circle",
                    description: Text("Capture something and Tenora will hold your place.")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical)
            }
        }
    }

    private var resurfacedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("RESURFACED")
            ForEach(remainingResurfacedTasks) { task in
                VStack(alignment: .leading, spacing: 12) {
                    Text("This is ready for another look:")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(task.title)
                        .font(.headline)
                    HStack {
                        Button("Done") {
                            Task { await taskStore.complete(task) }
                        }
                        Button("Later") {
                            Task { await taskStore.postpone(task) }
                        }
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    private var remainingResurfacedTasks: [TenoraTask] {
        taskStore.resurfacedTasks.filter { $0.id != taskStore.nowRecommendation?.id }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .tracking(1.2)
    }
}
