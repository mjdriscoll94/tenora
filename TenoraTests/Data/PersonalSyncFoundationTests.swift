import SwiftData
import XCTest
@testable import Tenora

@MainActor
final class PersonalSyncFoundationTests: XCTestCase {
    func testVersionOneStoreMigratesToV2WithoutChangingContent() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "TenoraPhase4Migration-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appending(path: "Tenora.store")
        let task = TenoraTask(title: "Preserve me", notes: "Still private")

        do {
            let schema = Schema(versionedSchema: TenoraSchemaV1.self)
            let configuration = ModelConfiguration("Tenora", schema: schema, url: storeURL, allowsSave: true)
            let v1 = try ModelContainer(for: schema, configurations: configuration)
            v1.mainContext.insert(StoredTask(task: task))
            try v1.mainContext.save()
        }

        let v2 = try TenoraModelContainerFactory.make(at: storeURL)
        XCTAssertEqual(try v2.mainContext.fetch(FetchDescriptor<StoredTask>()).map(\.domainModel), [task])
        XCTAssertTrue(try v2.mainContext.fetch(FetchDescriptor<StoredSyncMetadata>()).isEmpty)

        let report = try PersonalSyncMetadataStore(modelContext: v2.mainContext).backfill(profileID: .offline)
        XCTAssertEqual(report.metadataCreatedCount, 1)
        XCTAssertEqual(try PersonalSyncMetadataStore(modelContext: v2.mainContext).allMetadata().first?.state, .localOnly)
    }

    func testBackfillInventoriesExistingRecordsAsPrivateLocalOnlyData() throws {
        let container = try TenoraModelContainerFactory.makeInMemory()
        let profile = LocalProfileID(rawValue: "adult-a")
        let task = TenoraTask(title: "Private task", notes: "Never include this in diagnostics")
        let habit = Habit(name: "Private habit")
        let completion = HabitCompletion(habitID: habit.id, completionDate: Date(), xpAwarded: 0)
        container.mainContext.insert(StoredTask(task: task))
        container.mainContext.insert(StoredHabit(habit: habit))
        container.mainContext.insert(StoredHabitCompletion(completion: completion))
        container.mainContext.insert(StoredPlayerProgress())
        container.mainContext.insert(StoredGameUnlock(id: "legacy-item", kind: "retired"))
        try container.mainContext.save()

        let store = PersonalSyncMetadataStore(modelContext: container.mainContext)
        let report = try store.backfill(profileID: profile)
        let metadata = try store.allMetadata()

        XCTAssertEqual(report.recordCount, 5)
        XCTAssertEqual(report.metadataCreatedCount, 5)
        XCTAssertEqual(Set(metadata.map(\.entity)), Set(SyncEntity.allCases))
        XCTAssertTrue(metadata.allSatisfy { $0.scope == .personal })
        XCTAssertTrue(metadata.allSatisfy { $0.localOwnerProfileID == profile })
        XCTAssertTrue(metadata.allSatisfy { $0.ownerUserID == nil && $0.householdID == nil })
        XCTAssertTrue(metadata.allSatisfy { $0.state == .localOnly })
        XCTAssertTrue(metadata.allSatisfy { $0.serverVersion == nil && $0.lastAcknowledgedAt == nil })
    }

    func testBackfillIsIdempotent() throws {
        let container = try TenoraModelContainerFactory.makeInMemory()
        container.mainContext.insert(StoredTask(task: TenoraTask(title: "One")))
        try container.mainContext.save()
        let store = PersonalSyncMetadataStore(modelContext: container.mainContext)

        XCTAssertEqual(try store.backfill(profileID: .offline).metadataCreatedCount, 1)
        let second = try store.backfill(profileID: .offline)

        XCTAssertEqual(second.metadataCreatedCount, 0)
        XCTAssertEqual(second.metadataAlreadyPresentCount, 1)
        XCTAssertEqual(try store.allMetadata().count, 1)
    }

    func testRepositoryMaintainsMetadataAndDeletionTombstoneWithoutEnablingUpload() async throws {
        let container = try TenoraModelContainerFactory.makeInMemory()
        let profile = LocalProfileID(rawValue: "adult-b")
        let repository = SwiftDataTaskRepository(modelContext: container.mainContext, profileID: profile)
        let task = TenoraTask(title: "Keep private")

        try await repository.save(task)
        var metadata = try PersonalSyncMetadataStore(modelContext: container.mainContext).allMetadata()
        XCTAssertEqual(metadata.count, 1)
        XCTAssertNil(metadata[0].deletedAt)
        XCTAssertEqual(metadata[0].state, .localOnly)

        try await repository.delete(id: task.id)
        metadata = try PersonalSyncMetadataStore(modelContext: container.mainContext).allMetadata()
        XCTAssertEqual(metadata.count, 1)
        XCTAssertNotNil(metadata[0].deletedAt)
        XCTAssertEqual(metadata[0].state, .localOnly)
        XCTAssertFalse(TenoraFeatures.personalSyncReadEnabled)
        XCTAssertFalse(TenoraFeatures.personalSyncWriteEnabled)
    }

    func testMutableVersionMismatchAndDeletionRequireVisibleConflict() {
        let mismatch = PersonalSyncConflictRule.resolution(
            entity: .task,
            recordID: "task",
            baseServerVersion: 1,
            currentServerVersion: 2,
            remoteDeleted: false
        )
        let deleted = PersonalSyncConflictRule.resolution(
            entity: .habit,
            recordID: "habit",
            baseServerVersion: 2,
            currentServerVersion: 2,
            remoteDeleted: true
        )
        let immutableEvent = PersonalSyncConflictRule.resolution(
            entity: .habitCompletion,
            recordID: "completion",
            baseServerVersion: nil,
            currentServerVersion: 99,
            remoteDeleted: false
        )

        if case .failure(let conflict) = mismatch {
            XCTAssertEqual(conflict, .incompatibleEdit(entity: .task, recordID: "task"))
        } else {
            XCTFail("A mutable version mismatch must remain visible")
        }
        if case .failure(let conflict) = deleted {
            XCTAssertEqual(conflict, .editedAfterRemoteDeletion(entity: .habit, recordID: "habit"))
        } else {
            XCTFail("An edit after remote deletion must remain visible")
        }
        XCTAssertNoThrow(try immutableEvent.get())
    }
}
