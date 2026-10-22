import Foundation

@MainActor
final class FileMutationOutbox: MutationOutbox {
    private struct Envelope: Codable {
        static let currentVersion = 2
        let format: String
        let version: Int
        var mutations: [LocalMutation]

        init(mutations: [LocalMutation]) {
            format = "com.tenora.mutation-outbox"
            version = Self.currentVersion
            self.mutations = mutations
        }
    }

    private let directory: URL
    private let fileManager: FileManager

    init(directory: URL? = nil, fileManager: FileManager = .default) throws {
        self.fileManager = fileManager
        if let directory {
            self.directory = directory
        } else {
            let support = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            self.directory = support.appending(path: "Tenora Outbox", directoryHint: .isDirectory)
        }
        try fileManager.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    func enqueue(_ mutation: LocalMutation) throws {
        var mutations = try pending(profileID: mutation.profileID)
        mutations.append(mutation)
        try write(mutations, profileID: mutation.profileID)
    }

    func pending(profileID: LocalProfileID) throws -> [LocalMutation] {
        let url = fileURL(profileID)
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        if let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
           envelope.format == "com.tenora.mutation-outbox",
           envelope.version == Envelope.currentVersion {
            return envelope.mutations
        }
        let legacy = try JSONDecoder().decode([LocalMutation].self, from: data)
        try write(legacy, profileID: profileID)
        return legacy
    }

    func recordAttempt(
        ids: Set<UUID>,
        profileID: LocalProfileID,
        attemptedAt: Date,
        outcome: LocalMutationAttemptOutcome
    ) throws {
        var mutations = try pending(profileID: profileID)
        for index in mutations.indices where ids.contains(mutations[index].id) {
            mutations[index].attemptCount += 1
            mutations[index].lastAttemptAt = attemptedAt
            switch outcome {
            case .retryable(let code):
                mutations[index].state = .retryScheduled
                mutations[index].nextAttemptAt = MutationRetryPolicy.nextAttemptDate(
                    attemptCount: mutations[index].attemptCount,
                    attemptedAt: attemptedAt
                )
                mutations[index].lastFailureCode = code
            case .blocked(let code):
                mutations[index].state = .blocked
                mutations[index].nextAttemptAt = nil
                mutations[index].lastFailureCode = code
            }
        }
        try write(mutations, profileID: profileID)
    }

    func remove(ids: Set<UUID>, profileID: LocalProfileID) throws {
        try write(try pending(profileID: profileID).filter { !ids.contains($0.id) }, profileID: profileID)
    }

    func removeAll(profileID: LocalProfileID) throws { try write([], profileID: profileID) }

    /// Moves the Phase 2 file queue into the transactional journal. The source is only
    /// cleared after every idempotent insert succeeds, so interruption is retry-safe.
    @discardableResult
    func migratePending(profileID: LocalProfileID, to destination: MutationOutbox) throws -> Int {
        let mutations = try pending(profileID: profileID)
        guard !mutations.isEmpty else { return 0 }
        for mutation in mutations { try destination.enqueue(mutation) }
        try removeAll(profileID: profileID)
        return mutations.count
    }

    private func write(_ mutations: [LocalMutation], profileID: LocalProfileID) throws {
        let data = try JSONEncoder().encode(Envelope(mutations: mutations))
        try data.write(to: fileURL(profileID), options: .atomic)
    }

    private func fileURL(_ profileID: LocalProfileID) -> URL {
        directory.appending(path: "\(profileID.storageComponent).json")
    }
}
