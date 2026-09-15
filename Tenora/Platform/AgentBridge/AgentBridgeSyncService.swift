import Foundation

@MainActor
final class AgentBridgeSyncService: ObservableObject {
    static let shared = AgentBridgeSyncService()

    @Published private(set) var isConnected: Bool
    @Published private(set) var isSyncing = false
    @Published private(set) var lastSyncedAt: Date?
    @Published private(set) var errorMessage: String?
    @Published private(set) var sharingEnabled: Bool
    @Published private(set) var includeNotes: Bool
    @Published private(set) var includeCalendar: Bool

    let configuration: AgentBridgeConfiguration?
    private let defaults: UserDefaults
    private let tokens: AgentBridgeTokenStore
    private let oauth = AgentBridgeOAuthClient()
    private var pendingSync: Task<Void, Never>?

    init(configuration: AgentBridgeConfiguration? = .load(), defaults: UserDefaults = .standard,
         tokens: AgentBridgeTokenStore = AgentBridgeTokenStore()) {
        self.configuration = configuration
        self.defaults = defaults
        self.tokens = tokens
        isConnected = tokens.load() != nil
        sharingEnabled = defaults.bool(forKey: "agentBridge.sharingEnabled")
        includeNotes = defaults.bool(forKey: "agentBridge.includeNotes")
        includeCalendar = defaults.bool(forKey: "agentBridge.includeCalendar")
        lastSyncedAt = defaults.object(forKey: "agentBridge.lastSyncedAt") as? Date
    }

    func connect() async {
        guard let configuration else { errorMessage = "ChatGPT access is not configured for this build."; return }
        do {
            let newTokens = try await oauth.authorize(configuration: configuration)
            try tokens.save(newTokens)
            isConnected = true
            sharingEnabled = true
            defaults.set(true, forKey: "agentBridge.sharingEnabled")
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }

    func disconnect() {
        pendingSync?.cancel()
        tokens.delete()
        isConnected = false
        sharingEnabled = false
        defaults.set(false, forKey: "agentBridge.sharingEnabled")
        errorMessage = nil
    }

    func deleteSharedDataAndDisconnect() async {
        guard let configuration else { disconnect(); return }
        do {
            let accessToken = try await validAccessToken(configuration: configuration)
            var request = URLRequest(url: configuration.bridgeURL.appending(path: "v1/sync/tasks"))
            request.httpMethod = "DELETE"
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            let (_, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 204 else { throw BridgeSyncError.deleteFailed }
            disconnect()
        } catch { errorMessage = error.localizedDescription }
    }

    func setSharingEnabled(_ value: Bool) { sharingEnabled = value; defaults.set(value, forKey: "agentBridge.sharingEnabled") }
    func setIncludeNotes(_ value: Bool) { includeNotes = value; defaults.set(value, forKey: "agentBridge.includeNotes") }
    func setIncludeCalendar(_ value: Bool) { includeCalendar = value; defaults.set(value, forKey: "agentBridge.includeCalendar") }

    func enqueue(tasks: [TenoraTask], events: [CalendarEvent], focusedTaskID: UUID?) {
        guard sharingEnabled, isConnected else { return }
        let snapshot = makeSnapshot(tasks: tasks, events: events, focusedTaskID: focusedTaskID)
        pendingSync?.cancel()
        pendingSync = Task {
            do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
            await send(snapshot)
        }
    }

    func syncNow(tasks: [TenoraTask], events: [CalendarEvent], focusedTaskID: UUID?) async {
        guard sharingEnabled else { errorMessage = "Turn on ChatGPT sharing first."; return }
        await send(makeSnapshot(tasks: tasks, events: events, focusedTaskID: focusedTaskID))
    }

    private func makeSnapshot(tasks: [TenoraTask], events: [CalendarEvent], focusedTaskID: UUID?) -> AgentBridgeSnapshot {
        AgentBridgeSnapshot(tasks: tasks, events: events, focusedTaskID: focusedTaskID,
                            notesIncluded: includeNotes, calendarIncluded: includeCalendar)
    }

    private func send(_ snapshot: AgentBridgeSnapshot) async {
        guard !isSyncing, let configuration, tokens.load() != nil else {
            if tokens.load() == nil { isConnected = false; errorMessage = "Sign in again to resume ChatGPT sharing." }
            return
        }
        isSyncing = true
        defer { isSyncing = false }
        do {
            let token = try await validAccessToken(configuration: configuration)
            var request = URLRequest(url: configuration.bridgeURL.appending(path: "v1/sync/tasks"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
            request.httpBody = try encoder.encode(snapshot)
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw BridgeSyncError.invalidResponse }
            if http.statusCode == 401 { tokens.delete(); isConnected = false; throw BridgeSyncError.reconnect }
            guard http.statusCode == 204 else { throw BridgeSyncError.server(http.statusCode) }
            lastSyncedAt = snapshot.generatedAt
            defaults.set(snapshot.generatedAt, forKey: "agentBridge.lastSyncedAt")
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }

    private func validAccessToken(configuration: AgentBridgeConfiguration) async throws -> String {
        guard let current = tokens.load() else { throw BridgeSyncError.reconnect }
        if current.expiresAt > Date().addingTimeInterval(60) { return current.accessToken }
        guard let refreshToken = current.refreshToken else { throw BridgeSyncError.reconnect }
        do {
            let refreshed = try await oauth.refresh(configuration: configuration, refreshToken: refreshToken)
            try tokens.save(refreshed)
            return refreshed.accessToken
        } catch {
            tokens.delete()
            isConnected = false
            throw BridgeSyncError.reconnect
        }
    }
}

private enum BridgeSyncError: LocalizedError {
    case invalidResponse, reconnect, server(Int), deleteFailed
    var errorDescription: String? {
        switch self {
        case .invalidResponse: "The ChatGPT connection returned an invalid response."
        case .reconnect: "Your Tenora session expired. Sign in again to continue sharing."
        case .server: "Tenora couldn't update your shared data right now."
        case .deleteFailed: "Tenora couldn't delete the shared copy. Your connection was kept so you can try again."
        }
    }
}
