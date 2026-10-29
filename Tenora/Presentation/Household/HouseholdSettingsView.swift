import SwiftUI

struct HouseholdSettingsView: View {
    @EnvironmentObject private var account: AccountStore
    @EnvironmentObject private var store: HouseholdStore
    @State private var householdName = ""
    @State private var memberName = ""
    @State private var invitationInput: String
    @State private var invitationEmail = ""
    @State private var invitationRole: HouseholdRole = .adult
    @State private var hasHandledInitialInvitation = false
    @State private var isConfirmingLeave = false
    @State private var isConfirmingClosure = false
    @State private var isShowingClosureBlocked = false
    @State private var closureConfirmationName = ""
    @State private var transferRecipientID: UUID?
    @State private var isConfirmingTransfer = false
    @State private var isConfirmingTransferAcceptance = false

    init(initialInvitationToken: String = "") {
        _invitationInput = State(initialValue: initialInvitationToken)
    }

    var body: some View {
        Form {
            if let adult = account.authenticatedAdult {
                if let household = store.household {
                    householdSections(household, adult: adult)
                } else {
                    createOrJoinSections
                }
            } else {
                signedOutSection
            }

            if let message = store.message {
                Section {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("household-message")
                }
            }

            Section("Privacy") {
                Label("Households share only records you explicitly create as household items.", systemImage: "hand.raised.fill")
                Text("Your personal tasks, habits, working hours, capacity, calendar details, focus state, and settings remain private.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(TenoraScreenBackground())
        .tint(.tenoraForest)
        .navigationTitle("Household")
        .confirmationDialog(
            "Leave this household?",
            isPresented: $isConfirmingLeave,
            titleVisibility: .visible
        ) {
            Button("Leave Household", role: .destructive) {
                Task { await store.leaveHousehold() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You will lose access to household information. Your personal tasks, habits, schedule, and settings will stay in Tenora.")
        }
        .alert("Close household?", isPresented: $isConfirmingClosure) {
            TextField("Type household name", text: $closureConfirmationName)
                .textInputAutocapitalization(.words)
            Button("Close Household", role: .destructive) {
                Task { await store.closeHousehold() }
            }
            .disabled(!closureNameMatches)
            Button("Cancel", role: .cancel) {}
        } message: {
            if let name = store.household?.name {
                Text("Type “\(name)” below to confirm. This ends household collaboration and revokes unused invitations. Personal Tenora data is not deleted.")
            }
        }
        .alert("Household can’t be closed yet", isPresented: $isShowingClosureBlocked) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Every other adult must leave this household first. This protects them from losing household access without their consent.")
        }
        .confirmationDialog(
            "Transfer household ownership?",
            isPresented: $isConfirmingTransfer,
            titleVisibility: .visible
        ) {
            if let recipientID = transferRecipientID {
                Button("Send Transfer Request") {
                    Task { await store.requestOwnershipTransfer(to: recipientID) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let recipientID = transferRecipientID, let household = store.household {
                Text("\(household.memberName(for: recipientID)) must accept within 7 days. After acceptance, you will become an adult member.")
            }
        }
        .confirmationDialog(
            "Accept household ownership?",
            isPresented: $isConfirmingTransferAcceptance,
            titleVisibility: .visible
        ) {
            if let transfer = store.household?.ownershipTransfer {
                Button("Accept Ownership") {
                    Task { await store.acceptOwnershipTransfer(id: transfer.id) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You will become the household owner. The current owner will remain as an adult member.")
        }
        .overlay {
            if store.isWorking {
                ProgressView()
                    .padding(18)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .accessibilityLabel("Updating household")
            }
        }
        .task(id: account.state) {
            await store.refresh(for: account.authenticatedAdult)
            guard account.authenticatedAdult != nil,
                  !hasHandledInitialInvitation,
                  !invitationInput.isEmpty
            else { return }
            hasHandledInitialInvitation = true
            await store.previewInvitation(invitationInput)
        }
    }

    private var signedOutSection: some View {
        Section("Sign in required") {
            Label("Use an adult Tenora account to create or join a household.", systemImage: "person.2")
            NavigationLink("Open Account") { AccountSettingsView() }
            Text("Signing in remains optional for personal, on-device Tenora use.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var createOrJoinSections: some View {
        Section("Create a household") {
            TextField("Your name", text: $memberName)
                .textContentType(.name)
                .textInputAutocapitalization(.words)
            TextField("Household name", text: $householdName)
                .textInputAutocapitalization(.words)
                .accessibilityIdentifier("household-name")
            Button("Create Household") {
                Task { await store.createHousehold(name: householdName, memberName: memberName) }
            }
            .disabled(
                store.isWorking
                || householdName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || memberName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )
        }

        Section("Join with an invitation") {
            TextField("Your name", text: $memberName)
                .textContentType(.name)
                .textInputAutocapitalization(.words)
            TextField("Paste invitation code or link", text: $invitationInput, axis: .vertical)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(.body, design: .monospaced))
                .accessibilityIdentifier("household-invitation-input")
            Button("Review Invitation") {
                Task { await store.previewInvitation(invitationInput) }
            }
            .disabled(store.isWorking || invitationInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if let preview = store.invitationPreview {
                VStack(alignment: .leading, spacing: 8) {
                    Text(preview.householdName).font(.headline)
                    Label("Join as \(preview.role.displayName)", systemImage: "person.badge.plus")
                    Text(invitationStatusText(preview))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)

                Button("Join Household") {
                    Task { await store.acceptInvitation(invitationInput, memberName: memberName) }
                }
                .buttonStyle(TenoraPrimaryButtonStyle())
                .disabled(
                    store.isWorking
                    || !preview.canAccept
                    || memberName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
                .accessibilityIdentifier("join-household")
            }
        }
    }

    @ViewBuilder
    private func householdSections(_ household: HouseholdSnapshot, adult: AuthenticatedAdult) -> some View {
        Section("Your household") {
            VStack(alignment: .leading, spacing: 8) {
                Text(household.name).font(.title2.bold())
                if let role = household.currentRole {
                    Label(role.displayName, systemImage: role == .owner ? "crown.fill" : "person.fill")
                        .foregroundStyle(Color.tenoraForest)
                }
            }
            .padding(.vertical, 6)
            LabeledContent("Adults", value: "\(household.activeMembers.count)")
        }

        if household.currentMembership?.displayName == nil {
            Section("Add your name") {
                TextField("Your name", text: $memberName)
                    .textContentType(.name)
                    .textInputAutocapitalization(.words)
                Button("Save Name") {
                    Task { await store.setMemberName(memberName) }
                }
                .disabled(store.isWorking || memberName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Text("Names help everyone recognize household members and are required before ownership can be transferred.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }

        Section("Adult members") {
            ForEach(household.activeMembers) { membership in
                HStack {
                    Image(systemName: membership.userID == adult.userID ? "person.crop.circle.fill" : "person.crop.circle")
                        .foregroundStyle(Color.tenoraSage)
                    VStack(alignment: .leading) {
                        HStack(spacing: 5) {
                            Text(membership.displayName ?? "Name needed")
                            if membership.userID == adult.userID {
                                Text("(You)").foregroundStyle(.secondary)
                            }
                        }
                        Text(membership.role.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }

        if household.currentRole?.canManageInvitations == true {
            invitationManagementSection(household)
        }

        ownershipTransferSection(household)

        membershipManagementSection(household)
    }

    @ViewBuilder
    private func ownershipTransferSection(_ household: HouseholdSnapshot) -> some View {
        if let transfer = household.ownershipTransfer {
            Section("Ownership transfer") {
                if transfer.requestedBy == household.currentUserID {
                    Text("Waiting for \(household.memberName(for: transfer.recipientUserID)) to accept.")
                    Text("Expires \(transfer.expiresAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("Cancel Transfer", role: .destructive) {
                        Task { await store.cancelOwnershipTransfer(id: transfer.id) }
                    }
                    .disabled(store.isWorking)
                } else if transfer.recipientUserID == household.currentUserID {
                    Text("\(household.memberName(for: transfer.requestedBy)) asked you to become the household owner.")
                    Text("Expires \(transfer.expiresAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("Accept Ownership") { isConfirmingTransferAcceptance = true }
                        .buttonStyle(TenoraPrimaryButtonStyle())
                        .disabled(store.isWorking || !transfer.isPending)
                    Button("Decline", role: .destructive) {
                        Task { await store.declineOwnershipTransfer(id: transfer.id) }
                    }
                    .disabled(store.isWorking || !transfer.isPending)
                }
            }
        } else if household.currentRole == .owner {
            let eligibleMembers = household.activeMembers.filter {
                $0.userID != household.currentUserID
                && ($0.role == .adult || $0.role == .admin)
                && $0.displayName?.isEmpty == false
            }
            Section("Transfer ownership") {
                if eligibleMembers.isEmpty {
                    Text("Another active adult must add their name before ownership can be transferred.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Picker("New owner", selection: $transferRecipientID) {
                        Text("Choose an adult").tag(nil as UUID?)
                        ForEach(eligibleMembers) { membership in
                            Text(membership.displayName ?? "Adult member").tag(membership.userID as UUID?)
                        }
                    }
                    Button("Request Ownership Transfer") {
                        isConfirmingTransfer = true
                    }
                    .disabled(
                        store.isWorking
                        || transferRecipientID == nil
                        || household.currentMembership?.displayName == nil
                    )
                    Text("The selected adult must accept. Requests expire after 7 days, and you can cancel while one is pending.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func membershipManagementSection(_ household: HouseholdSnapshot) -> some View {
        Section("Membership") {
            if household.currentRole == .owner {
                Button(role: .destructive) {
                    if household.activeMembers.count > 1 {
                        isShowingClosureBlocked = true
                    } else {
                        closureConfirmationName = ""
                        isConfirmingClosure = true
                    }
                } label: {
                    Label("Close Household", systemImage: "lock.rectangle.stack")
                }
                .disabled(store.isWorking)
                .accessibilityIdentifier("close-household")

                if household.activeMembers.count > 1 {
                    Text("Every other adult must leave before this household can be closed. This prevents one person from removing everyone else's access.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Closing ends this household and revokes unused invitations. Its history is retained, and personal data is not deleted.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                Button(role: .destructive) {
                    isConfirmingLeave = true
                } label: {
                    Label("Leave Household", systemImage: "rectangle.portrait.and.arrow.right")
                }
                .disabled(store.isWorking)
                .accessibilityIdentifier("leave-household")

                Text("Leaving removes your access to household information. It does not delete your personal Tenora data or affect other members.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var closureNameMatches: Bool {
        guard let name = store.household?.name else { return false }
        return closureConfirmationName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .localizedCaseInsensitiveCompare(name) == .orderedSame
    }

    @ViewBuilder
    private func invitationManagementSection(_ household: HouseholdSnapshot) -> some View {
        Section("Invite an adult") {
            TextField("Email (optional)", text: $invitationEmail)
                .textContentType(.emailAddress)
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)

            if household.currentRole == .owner {
                Picker("Role", selection: $invitationRole) {
                    Text("Adult").tag(HouseholdRole.adult)
                    Text("Admin").tag(HouseholdRole.admin)
                }
            }

            Button("Create Invitation") {
                Task { await store.createInvitation(email: invitationEmail, role: invitationRole) }
            }
            .disabled(store.isWorking)

            Text("Tenora creates a private one-time link. Share it yourself by Messages, Mail, or another trusted method.")
                .font(.footnote)
                .foregroundStyle(.secondary)

        }

        if !household.pendingInvitations.isEmpty {
            Section("Pending invitations") {
                ForEach(household.pendingInvitations) { invitation in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(invitation.recipientEmail ?? "Invitation link")
                        Text("\(invitation.role.displayName) · Expires \(invitation.expiresAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let createdInvitation = store.shareableInvitation(for: invitation),
                           let url = createdInvitation.shareURL {
                            Text(url.absoluteString)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .accessibilityIdentifier("generated-invitation-link")
                        }

                        HStack(spacing: 12) {
                            if let createdInvitation = store.shareableInvitation(for: invitation),
                               let url = createdInvitation.shareURL {
                                ShareLink(
                                    item: url,
                                    subject: Text("Join my Tenora household"),
                                    message: Text("Join \(household.name) in Tenora. This private link can be used once.")
                                ) {
                                    Label("Share Invitation", systemImage: "square.and.arrow.up")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.tenoraForest)
                                .accessibilityIdentifier("share-household-invitation")
                            }

                            Button(role: .destructive) {
                                Task { await store.revokeInvitation(invitation) }
                            } label: {
                                Label("Revoke", systemImage: "xmark.circle")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                            .accessibilityIdentifier("revoke-household-invitation")
                        }
                        .controlSize(.large)
                    }
                    .padding(.vertical, 3)
                }
            }
        }
    }

    private func invitationStatusText(_ preview: HouseholdInvitationPreview) -> String {
        switch preview.status {
        case .pending:
            return "Expires \(preview.expiresAt.formatted(date: .abbreviated, time: .shortened))"
        case .accepted:
            return "This invitation has already been used."
        case .revoked:
            return "This invitation was revoked."
        case .expired:
            return "This invitation has expired."
        }
    }
}
