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

/// Phase 4 adds private sync bookkeeping as a sidecar. Existing content models are
/// unchanged, so migration cannot reinterpret or expose their fields.
enum TenoraSchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        TenoraSchemaV1.models + [StoredSyncMetadata.self, StoredLocalMutation.self]
    }
}

enum TenoraMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [TenoraSchemaV1.self, TenoraSchemaV2.self] }
    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: TenoraSchemaV1.self, toVersion: TenoraSchemaV2.self)]
    }
}

enum TenoraModelContainerFactory {
    static func makeInMemory() throws -> ModelContainer {
        let schema = Schema(versionedSchema: TenoraSchemaV2.self)
        return try ModelContainer(
            for: schema,
            migrationPlan: TenoraMigrationPlan.self,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
    }

    static func makePersistent(profileID: LocalProfileID = .offline) throws -> ModelContainer {
        let schema = Schema(versionedSchema: TenoraSchemaV2.self)
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
        let schema = Schema(versionedSchema: TenoraSchemaV2.self)
        let configuration = ModelConfiguration("Tenora", schema: schema, url: url, allowsSave: true)
        return try ModelContainer(
            for: schema,
            migrationPlan: TenoraMigrationPlan.self,
            configurations: configuration
        )
    }
}
