import SwiftData
import SwiftUI

@main
struct TenoraApp: App {
    @UIApplicationDelegateAdaptor(TenoraAppDelegate.self) private var appDelegate
    private let modelContainer: ModelContainer
    @StateObject private var taskStore: TaskStore
    @StateObject private var calendarStore: CalendarStore
    @StateObject private var transitionStore: TransitionStore

    init() {
        let runtime = AppRuntime.shared
        modelContainer = runtime.container
        _taskStore = StateObject(wrappedValue: runtime.tasks)
        _calendarStore = StateObject(wrappedValue: runtime.calendar)
        _transitionStore = StateObject(wrappedValue: runtime.transitions)
    }

    var body: some Scene {
        WindowGroup {
            TenoraRootView()
                .environmentObject(taskStore)
                .environmentObject(calendarStore)
                .environmentObject(transitionStore)
        }
        .modelContainer(modelContainer)
    }
}

private struct TenoraRootView: View {
    @ObservedObject private var bridge = AgentBridgeSyncService.shared
    @AppStorage("account.onboardingCompleted") private var onboardingCompleted = false

    var body: some View {
        Group {
            if bridge.configuration != nil, !bridge.isConnected, !onboardingCompleted {
                AccountOnboardingView(onContinueOffline: { onboardingCompleted = true })
            } else {
                RootTabView()
            }
        }
        .task { await bridge.warmUp() }
    }
}

private struct AccountOnboardingView: View {
    @EnvironmentObject private var taskStore: TaskStore
    @EnvironmentObject private var calendarStore: CalendarStore
    @ObservedObject private var bridge = AgentBridgeSyncService.shared
    @AppStorage("account.onboardingCompleted") private var onboardingCompleted = false
    let onContinueOffline: () -> Void

    var body: some View {
        ZStack {
            Color.tenoraSurface.ignoresSafeArea()
            VStack(spacing: 24) {
                Spacer()
                Image("TenoraLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 132, height: 132)
                    .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                    .shadow(color: .black.opacity(0.18), radius: 22, y: 12)
                    .accessibilityHidden(true)

                VStack(spacing: 10) {
                    Text("Welcome to Tenora")
                        .font(.largeTitle.bold())
                    Text("Keep your place, return to what matters, and securely connect your own ChatGPT account when you choose.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 12) {
                    Button("Create Tenora account") { authorize(.signUp) }
                        .buttonStyle(TenoraPrimaryButtonStyle())
                        .disabled(bridge.isConnecting)
                    Button("Sign in") { authorize(.signIn) }
                        .disabled(bridge.isConnecting)
                    Button("Continue without an account") { onContinueOffline() }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .disabled(bridge.isConnecting)
                }

                if bridge.isConnecting {
                    ProgressView("Opening secure sign-in…")
                } else if let error = bridge.errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Text("Your password is handled by Tenora's secure identity provider and is never stored in the app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Spacer()
            }
            .padding(32)
        }
    }

    private func authorize(_ mode: AgentBridgeAuthorizationMode) {
        Task {
            guard await bridge.connect(mode: mode) else { return }
            await bridge.syncNow(tasks: taskStore.tasks, events: calendarStore.events, focusedTaskID: taskStore.focusedTaskID)
            onboardingCompleted = true
        }
    }
}
