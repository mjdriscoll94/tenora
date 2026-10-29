import XCTest
@testable import Tenora

@MainActor
final class HouseholdStoreTests: XCTestCase {
    private let adult = AuthenticatedAdult(
        userID: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
        provider: .supabase,
        providerSubject: "auth-a",
        email: "adult@example.com"
    )

    func testInvitationTokenAcceptsCodeAndTenoraLink() {
        let token = String(repeating: "a1", count: 32)

        XCTAssertEqual(HouseholdStore.invitationToken(from: token.uppercased()), token)
        XCTAssertEqual(HouseholdStore.invitationToken(from: "tenora://household/invite/\(token)"), token)
        XCTAssertNil(HouseholdStore.invitationToken(from: "not-a-token"))
    }

    func testRefreshLoadsHouseholdForAuthenticatedAdult() async {
        let service = FakeHouseholdService(snapshot: snapshot)
        let store = makeStore(service: service)

        await store.refresh(for: adult)

        XCTAssertEqual(store.household, snapshot)
        XCTAssertNil(store.message)
    }

    func testSignedOutRefreshClearsHouseholdAndSensitiveInvitationState() async {
        let service = FakeHouseholdService(snapshot: snapshot)
        let store = makeStore(service: service)
        await store.refresh(for: adult)
        await store.createInvitation(email: nil, role: .adult)

        await store.refresh(for: nil)

        XCTAssertNil(store.household)
        XCTAssertNil(store.latestInvitation)
        XCTAssertNil(store.invitationPreview)
    }

    func testCreateHouseholdTrimsNameAndPreservesReturnedSnapshot() async {
        let service = FakeHouseholdService(snapshot: nil)
        let store = makeStore(service: service)
        await store.refresh(for: adult)

        await store.createHousehold(name: "  Driscoll Home  ")

        XCTAssertEqual(service.createdName, "Driscoll Home")
        XCTAssertEqual(store.household?.name, "Driscoll Home")
    }

    func testPreviewAndAcceptInvitation() async {
        let service = FakeHouseholdService(snapshot: nil)
        let store = makeStore(service: service)
        let token = String(repeating: "ab", count: 32)
        await store.refresh(for: adult)

        await store.previewInvitation(token)
        XCTAssertEqual(store.invitationPreview?.householdName, "Driscoll Home")

        await store.acceptInvitation(token)
        XCTAssertEqual(service.acceptedToken, token)
        XCTAssertEqual(store.household?.name, "Driscoll Home")
        XCTAssertNil(store.invitationPreview)
    }

    func testInvalidInvitationNeverCallsService() async {
        let service = FakeHouseholdService(snapshot: nil)
        let store = makeStore(service: service)
        await store.refresh(for: adult)

        await store.previewInvitation("bad")

        XCTAssertEqual(service.previewCallCount, 0)
        XCTAssertEqual(store.message, HouseholdServiceError.invalidInvitation.localizedDescription)
    }

    func testInvitationLinkSurvivesRefreshUntilInvitationIsRevoked() async {
        let service = FakeHouseholdService(snapshot: snapshot)
        let links = FakeInvitationLinkStorage()
        let store = HouseholdStore(service: service, linkStorage: links)
        await store.refresh(for: adult)

        await store.createInvitation(email: nil, role: .adult)

        guard let pending = store.household?.pendingInvitations.first else {
            return XCTFail("Expected a pending invitation")
        }
        XCTAssertEqual(
            store.shareableInvitation(for: pending)?.shareURL?.absoluteString,
            "tenora://household/invite/\(String(repeating: "cd", count: 32))"
        )

        await store.refresh(for: adult)
        XCTAssertNotNil(store.shareableInvitation(for: pending))

        await store.revokeInvitation(pending)
        XCTAssertNil(store.shareableInvitation(for: pending))
        XCTAssertTrue(links.load().isEmpty)
    }

    func testAdultCanLeaveHouseholdWithoutChangingPersonalData() async {
        let service = FakeHouseholdService(snapshot: memberSnapshot)
        let store = makeStore(service: service)
        await store.refresh(for: adult)

        await store.leaveHousehold()

        XCTAssertTrue(service.didLeave)
        XCTAssertNil(store.household)
        XCTAssertEqual(store.message, "You left the household. Your personal Tenora data is unchanged.")
    }

    func testOwnerCanCloseHouseholdWithoutChangingPersonalData() async {
        let service = FakeHouseholdService(snapshot: snapshot)
        let store = makeStore(service: service)
        await store.refresh(for: adult)

        await store.closeHousehold()

        XCTAssertTrue(service.didClose)
        XCTAssertNil(store.household)
        XCTAssertEqual(store.message, "Household closed. Everyone's personal Tenora data is unchanged.")
    }

    private func makeStore(service: FakeHouseholdService) -> HouseholdStore {
        HouseholdStore(service: service, linkStorage: FakeInvitationLinkStorage())
    }

    private var snapshot: HouseholdSnapshot {
        HouseholdSnapshot(
            id: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
            name: "Driscoll Home",
            currentUserID: adult.userID,
            memberships: [
                HouseholdMembership(
                    id: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!,
                    userID: adult.userID,
                    role: .owner,
                    status: .active,
                    joinedAt: Date(timeIntervalSince1970: 100)
                )
            ],
            invitations: []
        )
    }

    private var memberSnapshot: HouseholdSnapshot {
        HouseholdSnapshot(
            id: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
            name: "Driscoll Home",
            currentUserID: adult.userID,
            memberships: [
                HouseholdMembership(
                    id: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!,
                    userID: adult.userID,
                    role: .adult,
                    status: .active,
                    joinedAt: Date(timeIntervalSince1970: 100)
                )
            ],
            invitations: []
        )
    }
}

private final class FakeHouseholdService: HouseholdService, @unchecked Sendable {
    let isConfigured = true
    var snapshot: HouseholdSnapshot?
    var createdName: String?
    var acceptedToken: String?
    var previewCallCount = 0
    var didLeave = false
    var didClose = false

    init(snapshot: HouseholdSnapshot?) { self.snapshot = snapshot }

    func fetchHousehold(for adult: AuthenticatedAdult) async throws -> HouseholdSnapshot? { snapshot }

    func createHousehold(named name: String, for adult: AuthenticatedAdult) async throws -> HouseholdSnapshot {
        createdName = name
        let household = makeSnapshot(adult: adult, name: name)
        snapshot = household
        return household
    }

    func createInvitation(email: String?, role: HouseholdRole) async throws -> CreatedHouseholdInvitation {
        let created = CreatedHouseholdInvitation(
            id: UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!,
            token: String(repeating: "cd", count: 32),
            expiresAt: Date(timeIntervalSinceNow: 10_000)
        )
        if let current = snapshot {
            snapshot = HouseholdSnapshot(
                id: current.id,
                name: current.name,
                currentUserID: current.currentUserID,
                memberships: current.memberships,
                invitations: current.invitations + [
                    HouseholdInvitation(
                        id: created.id,
                        recipientEmail: email,
                        role: role,
                        status: .pending,
                        expiresAt: created.expiresAt
                    )
                ]
            )
        }
        return created
    }

    func previewInvitation(token: String) async throws -> HouseholdInvitationPreview? {
        previewCallCount += 1
        return HouseholdInvitationPreview(
            householdName: "Driscoll Home",
            role: .adult,
            expiresAt: Date(timeIntervalSinceNow: 3_600),
            status: .pending
        )
    }

    func acceptInvitation(token: String, for adult: AuthenticatedAdult) async throws -> HouseholdSnapshot {
        acceptedToken = token
        let household = makeSnapshot(adult: adult, name: "Driscoll Home")
        snapshot = household
        return household
    }

    func revokeInvitation(id: UUID) async throws {
        guard let current = snapshot else { return }
        snapshot = HouseholdSnapshot(
            id: current.id,
            name: current.name,
            currentUserID: current.currentUserID,
            memberships: current.memberships,
            invitations: current.invitations.map { invitation in
                guard invitation.id == id else { return invitation }
                return HouseholdInvitation(
                    id: invitation.id,
                    recipientEmail: invitation.recipientEmail,
                    role: invitation.role,
                    status: .revoked,
                    expiresAt: invitation.expiresAt
                )
            }
        )
    }

    func leaveHousehold() async throws {
        didLeave = true
        snapshot = nil
    }

    func closeHousehold() async throws {
        didClose = true
        snapshot = nil
    }

    private func makeSnapshot(adult: AuthenticatedAdult, name: String) -> HouseholdSnapshot {
        HouseholdSnapshot(
            id: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
            name: name,
            currentUserID: adult.userID,
            memberships: [
                HouseholdMembership(
                    id: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!,
                    userID: adult.userID,
                    role: .owner,
                    status: .active,
                    joinedAt: Date(timeIntervalSince1970: 100)
                )
            ],
            invitations: []
        )
    }
}

private final class FakeInvitationLinkStorage: HouseholdInvitationLinkStorage {
    private var invitations: [CreatedHouseholdInvitation] = []

    func load() -> [CreatedHouseholdInvitation] { invitations }

    func save(_ invitation: CreatedHouseholdInvitation) throws {
        invitations.removeAll { $0.id == invitation.id }
        invitations.append(invitation)
    }

    func remove(id: UUID) {
        invitations.removeAll { $0.id == id }
    }
}
