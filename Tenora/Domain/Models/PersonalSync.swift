import Foundation

/// The privacy boundary for a record that may eventually participate in sync.
/// Phase 4 only creates `.personal` metadata; household scope remains unavailable.
enum SyncRecordScope: String, Codable, Sendable {
    case personal
    case household
}

enum SyncRecordState: String, Codable, Sendable {
    /// The record is inventoried locally but cannot upload until the user explicitly opts in.
    case localOnly
    case pendingUpload
    case synchronized
    case conflicted
}

enum SyncEntity: String, Codable, CaseIterable, Sendable {
    case task
    case habit
    case habitCompletion
    case playerProgress
    case gameUnlock
}

struct PersonalSyncMetadata: Equatable, Sendable {
    let entity: SyncEntity
    let recordID: String
    let scope: SyncRecordScope
    let localOwnerProfileID: LocalProfileID
    let ownerUserID: UUID?
    let householdID: UUID?
    let serverVersion: Int64?
    let updatedAt: Date
    let deletedAt: Date?
    let state: SyncRecordState
    let lastAcknowledgedAt: Date?
}

/// Content-free information that can be shown to a user or support without exposing
/// task titles, notes, habit names, or calendar data.
struct PersonalSyncInventoryReport: Equatable, Sendable {
    var taskCount = 0
    var habitCount = 0
    var habitCompletionCount = 0
    var playerProgressCount = 0
    var gameUnlockCount = 0
    var metadataCreatedCount = 0
    var metadataAlreadyPresentCount = 0

    var recordCount: Int {
        taskCount + habitCount + habitCompletionCount + playerProgressCount + gameUnlockCount
    }
}

enum PersonalSyncConflict: Equatable, Sendable {
    case incompatibleEdit(entity: SyncEntity, recordID: String)
    case editedAfterRemoteDeletion(entity: SyncEntity, recordID: String)
}

enum PersonalSyncConflictRule {
    /// Immutable completion events deduplicate by their stable UUID. Mutable records
    /// require matching server versions; deletions never silently discard an offline edit.
    static func resolution(
        entity: SyncEntity,
        recordID: String,
        baseServerVersion: Int64?,
        currentServerVersion: Int64?,
        remoteDeleted: Bool
    ) -> Result<Void, PersonalSyncConflict> {
        if entity == .habitCompletion {
            return .success(())
        }
        if remoteDeleted {
            return .failure(.editedAfterRemoteDeletion(entity: entity, recordID: recordID))
        }
        guard baseServerVersion == currentServerVersion else {
            return .failure(.incompatibleEdit(entity: entity, recordID: recordID))
        }
        return .success(())
    }
}

extension PersonalSyncConflict: Error {}
