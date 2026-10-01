import SwiftUI

struct AboutSettingsView: View {
    var body: some View {
        Form {
            Section {
                NavigationLink("How Tenora chooses tasks") { HowTenoraWorksView() }
                Link("Privacy policy", destination: URL(string: "https://github.com/mjdriscoll94/tenora/blob/main/PRIVACY.md")!)
                Link("Support", destination: URL(string: "https://github.com/mjdriscoll94/tenora/issues")!)
            }

            Section("Version") {
                LabeledContent("Tenora", value: version)
            }
        }
        .scrollContentBackground(.hidden)
        .background(TenoraScreenBackground())
        .tint(.tenoraForest)
        .navigationTitle("About Tenora")
    }

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }
}

private struct HowTenoraWorksView: View {
    var body: some View {
        List {
            explanation("What matters now", "Tenora balances deadlines, importance, available time, your working schedule, calendar events, and what you said you can handle.", icon: "scope")
            explanation("Your place is held", "Starting, holding, or returning to a task preserves the smallest next step so interruptions do not erase the thread.", icon: "bookmark")
            explanation("Capacity changes", "Easy win, interesting, important, mindless, quick, and momentum modes adjust ranking for today without hiding the rest of your work.", icon: "gauge.with.dots.needle.50percent")
            explanation("Nothing is locked in", "You can always open Inbox, choose another task, postpone something, or change its details.", icon: "arrow.triangle.branch")
        }
        .scrollContentBackground(.hidden)
        .background(TenoraScreenBackground())
        .navigationTitle("How Tenora works")
    }

    private func explanation(_ title: String, _ text: String, icon: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: icon).foregroundStyle(Color.tenoraCopper)
        }
        .padding(.vertical, 6)
    }
}
