import Foundation

@MainActor
final class FileMutationOutbox: MutationOutbox {
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
        return try JSONDecoder().decode([LocalMutation].self, from: Data(contentsOf: url))
    }

    func remove(ids: Set<UUID>, profileID: LocalProfileID) throws {
        try write(try pending(profileID: profileID).filter { !ids.contains($0.id) }, profileID: profileID)
    }

    func removeAll(profileID: LocalProfileID) throws { try write([], profileID: profileID) }

    private func write(_ mutations: [LocalMutation], profileID: LocalProfileID) throws {
        let data = try JSONEncoder().encode(mutations)
        try data.write(to: fileURL(profileID), options: .atomic)
    }

    private func fileURL(_ profileID: LocalProfileID) -> URL {
        directory.appending(path: "\(profileID.storageComponent).json")
    }
}
