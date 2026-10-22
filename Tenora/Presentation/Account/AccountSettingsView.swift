import AuthenticationServices
import SwiftUI

struct AccountSettingsView: View {
    @EnvironmentObject private var account: AccountStore
    @State private var rawNonce: String?
    @State private var showingSignOutConfirmation = false

    var body: some View {
        Form {
            statusSection
            actionSection
            Section("Privacy") {
                Text("An account identifies you as an adult. It does not create a household, share tasks, or upload your local data.")
                Text("Your tasks, habits, calendar choices, working hours, focus state, and settings remain on this device in this release.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(TenoraScreenBackground())
        .navigationTitle("Account")
        .confirmationDialog("Sign out on this device?", isPresented: $showingSignOutConfirmation) {
            Button("Sign Out", role: .destructive) { Task { await account.signOut() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Signing out does not delete your local data.")
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        Section("Status") {
            switch account.state {
            case .localOnly:
                Label("Using Tenora locally", systemImage: "iphone")
                if !account.isConfigured {
                    Text("Account sign-in is not configured in this build. All current features still work without an account.")
                        .foregroundStyle(.secondary)
                }
            case .restoring:
                ProgressView("Checking your account…")
            case .signedOut:
                Label("Not signed in", systemImage: "person.crop.circle")
            case .needsAssociation(let adult, let interrupted):
                accountIdentity(adult)
                if interrupted {
                    Label("Profile connection needs attention", systemImage: "exclamationmark.arrow.triangle.2.circlepath")
                        .foregroundStyle(Color.tenoraCopper)
                }
            case .profileSwitchRequired(let adult, _, let activated):
                accountIdentity(adult)
                Label(activated ? "Profile switch ready" : "Different local profile", systemImage: "person.2.arrow.trianglehead.swap")
            case .authenticated(let adult, let association):
                accountIdentity(adult)
                Label(association.profileID == .offline ? "Current local profile connected" : "Separate local profile connected", systemImage: "checkmark.shield")
                    .foregroundStyle(Color.tenoraForest)
            case .sessionExpired:
                Label("Session expired", systemImage: "clock.badge.exclamationmark")
            case .sessionRevoked:
                Label("Session revoked", systemImage: "person.crop.circle.badge.xmark")
            }
            if let message = account.message {
                Text(message).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var actionSection: some View {
        Section {
            switch account.state {
            case .signedOut, .sessionExpired, .sessionRevoked:
                appleButton
                Text("Sign in is optional. You can continue using Tenora without an account.")
                    .font(.footnote).foregroundStyle(.secondary)
            case .needsAssociation(_, let interrupted):
                if interrupted {
                    Button("Finish connecting this profile") { account.finishInterruptedAssociation() }
                    Button("Remove unfinished connection", role: .destructive) { account.discardInterruptedAssociation() }
                } else {
                    Button("Connect this local profile") { account.associateCurrentProfile() }
                    Button("Start with a separate local profile") { account.associateSeparateProfile() }
                }
                Text("Connecting a profile only remembers which on-device data belongs with this account. It does not upload or share anything.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("Sign out instead") { showingSignOutConfirmation = true }
            case .profileSwitchRequired(_, _, let activated):
                if activated {
                    Label("Close and reopen Tenora to finish the protected profile switch.", systemImage: "checkmark.circle")
                } else {
                    Button("Switch to this account's local profile") { account.activateAssociatedProfile() }
                        .buttonStyle(TenoraPrimaryButtonStyle())
                    Button("Sign out instead") { showingSignOutConfirmation = true }
                }
            case .authenticated:
                Button("Sign out on this device") { showingSignOutConfirmation = true }
            case .localOnly, .restoring:
                EmptyView()
            }
        }
    }

    private var appleButton: some View {
        SignInWithAppleButton(.continue) { request in
            do {
                let nonce = try AppleSignInNonce.make()
                rawNonce = nonce
                request.requestedScopes = [.email]
                request.nonce = AppleSignInNonce.hashed(nonce)
            } catch {
                account.report(error)
            }
        } onCompletion: { result in
            do {
                guard let rawNonce else { throw AccountAuthenticationError.invalidCredential }
                let token = try AppleSignInNonce.identityToken(from: result)
                Task { await account.signInWithApple(identityToken: token, rawNonce: rawNonce) }
            } catch {
                account.report(error)
            }
            rawNonce = nil
        }
        .signInWithAppleButtonStyle(.black)
        .frame(height: 50)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .disabled(account.isWorking)
        .accessibilityLabel("Continue with Apple")
    }

    @ViewBuilder
    private func accountIdentity(_ adult: AuthenticatedAdult) -> some View {
        if let email = adult.email, !email.isEmpty {
            Label(email, systemImage: "person.crop.circle.fill")
        } else {
            Label("Tenora adult account", systemImage: "person.crop.circle.fill")
        }
    }
}

/// A privacy gate replaces the productivity UI while a signed-in account is not
/// associated with the local profile currently loaded in memory.
struct AccountProfileGateView: View {
    var body: some View {
        NavigationStack {
            AccountSettingsView()
        }
    }
}
