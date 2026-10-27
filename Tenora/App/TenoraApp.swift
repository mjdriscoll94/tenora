import SwiftData
import SwiftUI

@main
struct TenoraApp: App {
    @UIApplicationDelegateAdaptor(TenoraAppDelegate.self) private var appDelegate
    private let modelContainer: ModelContainer
    private let persistenceIssue: PersistenceIssue?
    @StateObject private var taskStore: TaskStore
    @StateObject private var calendarStore: CalendarStore
    @StateObject private var transitionStore: TransitionStore
    @StateObject private var habitStore: HabitStore
    @StateObject private var appSettings: AppSettingsStore
    @StateObject private var accountStore: AccountStore
    @StateObject private var householdStore: HouseholdStore

    init() {
        let runtime = AppRuntime.shared
        modelContainer = runtime.container
        persistenceIssue = runtime.persistenceIssue
        _taskStore = StateObject(wrappedValue: runtime.tasks)
        _calendarStore = StateObject(wrappedValue: runtime.calendar)
        _transitionStore = StateObject(wrappedValue: runtime.transitions)
        _habitStore = StateObject(wrappedValue: runtime.habits)
        _appSettings = StateObject(wrappedValue: runtime.appSettings)
        let accountProvider = AccountProviderFactory.make()
        _accountStore = StateObject(wrappedValue: AccountStore(provider: accountProvider))
        _householdStore = StateObject(wrappedValue: HouseholdStore(service: accountProvider.householdService))
    }

    var body: some Scene {
        WindowGroup {
            TenoraRootView(persistenceIssue: persistenceIssue)
                .environmentObject(taskStore)
                .environmentObject(calendarStore)
                .environmentObject(transitionStore)
                .environmentObject(habitStore)
                .environmentObject(appSettings)
                .environmentObject(accountStore)
                .environmentObject(householdStore)
                .task { await accountStore.restore() }
        }
        .modelContainer(modelContainer)
    }
}

private struct TenoraRootView: View {
    let persistenceIssue: PersistenceIssue?
    @EnvironmentObject private var accountStore: AccountStore

    @ViewBuilder
    var body: some View {
        #if DEBUG
        if requiresAccountPrivacyGate {
            AccountProfileGateView()
        } else if ProcessInfo.processInfo.arguments.contains("-habit-tracker-test") {
            NavigationStack { HabitDashboardView() }
                .environmentObject(HabitStore.preview(.partial))
        } else if let persistenceIssue {
            PersistenceRecoveryView(issue: persistenceIssue)
        } else {
            standardRoot
        }
        #else
        if requiresAccountPrivacyGate {
            AccountProfileGateView()
        } else if let persistenceIssue {
            PersistenceRecoveryView(issue: persistenceIssue)
        } else {
            standardRoot
        }
        #endif
    }

    private var requiresAccountPrivacyGate: Bool {
        switch accountStore.state {
        case .needsAssociation, .profileSwitchRequired:
            return true
        default:
            return false
        }
    }

    @ViewBuilder
    private var standardRoot: some View {
        if TenoraFeatures.agentBridgeEnabled {
            AgentAccountRootView()
        } else {
            RootTabView()
        }
    }
}

private struct PersistenceRecoveryView: View {
    let issue: PersistenceIssue
    @State private var showingDetails = false

    var body: some View {
        NavigationStack {
            ZStack {
                TenoraScreenBackground()
                VStack(spacing: 20) {
                    Image(systemName: "externaldrive.badge.exclamationmark")
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(Color.tenoraCopper)
                    Text(issue.title)
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                    Text(issue.message)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Text("Do not reinstall or delete the app. Restart once, then contact Tenora support if this screen returns.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Show technical details") { showingDetails = true }
                        .buttonStyle(TenoraSecondaryButtonStyle())
                }
                .padding(32)
            }
            .navigationTitle("Data Recovery")
            .alert("Technical details", isPresented: $showingDetails) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(issue.technicalDetails)
            }
        }
    }
}

private struct AgentAccountRootView: View {
    @ObservedObject private var bridge = AgentBridgeSyncService.shared
    @EnvironmentObject private var settings: AppSettingsStore

    var body: some View {
        Group {
            if bridge.configuration != nil, !bridge.isConnected, !settings.onboardingCompleted {
                AccountOnboardingView(onContinueOffline: { settings.onboardingCompleted = true })
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
    @EnvironmentObject private var settings: AppSettingsStore
    let onContinueOffline: () -> Void

    var body: some View {
        ZStack {
            TenoraScreenBackground()
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
                        .buttonStyle(TenoraSecondaryButtonStyle())
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
            settings.onboardingCompleted = true
        }
    }
}
