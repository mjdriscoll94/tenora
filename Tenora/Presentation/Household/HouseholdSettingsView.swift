import SwiftUI

struct HouseholdSettingsView: View {
    @EnvironmentObject private var account: AccountStore
    @EnvironmentObject private var store: HouseholdStore
    @State private var householdName = ""
    @State private var invitationInput: String
    @State private var invitationEmail = ""
    @State private var invitationRole: HouseholdRole = .adult
    @State private var hasHandledInitialInvitation = false

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
            TextField("Household name", text: $householdName)
                .textInputAutocapitalization(.words)
                .accessibilityIdentifier("household-name")
            Button("Create Household") {
                Task { await store.createHousehold(name: householdName) }
            }
            .disabled(store.isWorking || householdName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }

        Section("Join with an invitation") {
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
                    Task { await store.acceptInvitation(invitationInput) }
                }
                .buttonStyle(TenoraPrimaryButtonStyle())
                .disabled(store.isWorking || !preview.canAccept)
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

        Section("Adult members") {
            ForEach(household.activeMembers) { membership in
                HStack {
                    Image(systemName: membership.userID == adult.userID ? "person.crop.circle.fill" : "person.crop.circle")
                        .foregroundStyle(Color.tenoraSage)
                    VStack(alignment: .leading) {
                        Text(membership.userID == adult.userID ? "You" : "Adult member")
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

            if let invitation = store.latestInvitation {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Invitation ready").font(.headline)
                    Text(invitation.token)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .accessibilityIdentifier("generated-invitation-code")
                    Text("Expires \(invitation.expiresAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let url = invitation.shareURL {
                        ShareLink(
                            item: url,
                            subject: Text("Join my Tenora household"),
                            message: Text("Join \(household.name) in Tenora. This private link can be used once.")
                        ) {
                            Label("Share Invitation", systemImage: "square.and.arrow.up")
                        }
                    }
                    Button("Done") { store.dismissGeneratedInvitation() }
                }
                .padding(.vertical, 4)
            }
        }

        if !household.pendingInvitations.isEmpty {
            Section("Pending invitations") {
                ForEach(household.pendingInvitations) { invitation in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(invitation.recipientEmail ?? "Invitation link")
                        Text("\(invitation.role.displayName) · Expires \(invitation.expiresAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Revoke", role: .destructive) {
                            Task { await store.revokeInvitation(invitation) }
                        }
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
