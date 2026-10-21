import Foundation
import SwiftData

/// The exact local data model shipped before household collaboration.
/// Future model changes must add a new `VersionedSchema` and migration stage.
enum TenoraSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            StoredTask.self,
            StoredHabit.self,
            StoredHabitCompletion.self,
            StoredPlayerProgress.self,
            StoredGameUnlock.self
        ]
    }
}

enum TenoraMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [TenoraSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

enum TenoraModelContainerFactory {
    static func makeInMemory() throws -> ModelContainer {
        let schema = Schema(versionedSchema: TenoraSchemaV1.self)
        return try ModelContainer(
            for: schema,
            migrationPlan: TenoraMigrationPlan.self,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
    }

    static func makePersistent(profileID: LocalProfileID = .offline) throws -> ModelContainer {
        let schema = Schema(versionedSchema: TenoraSchemaV1.self)
        if profileID != .offline {
            let support = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let directory = support
                .appending(path: "Tenora Profiles", directoryHint: .isDirectory)
                .appending(path: profileID.storageComponent, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return try make(at: directory.appending(path: "Tenora.store"))
        }
        return try ModelContainer(
            for: schema,
            migrationPlan: TenoraMigrationPlan.self,
            configurations: ModelConfiguration(schema: schema)
        )
    }

    static func make(at url: URL) throws -> ModelContainer {
        let schema = Schema(versionedSchema: TenoraSchemaV1.self)
        let configuration = ModelConfiguration("Tenora", schema: schema, url: url, allowsSave: true)
        return try ModelContainer(
            for: schema,
            migrationPlan: TenoraMigrationPlan.self,
            configurations: configuration
        )
    }
}
