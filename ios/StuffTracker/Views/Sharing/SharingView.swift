import SwiftUI

struct SharingView: View {
    let homes: [HomeDetail]
    @Environment(\.dismiss) private var dismiss
    @State private var members: [Member] = []
    @State private var isLoading = true
    @State private var showInvite = false
    @State private var inviteEmail = ""
    @State private var inviteRole = "editor"
    @State private var errorMessage: String?

    private var ownedHomeIds: [String] {
        homes.filter { $0.role == "owner" || $0.role == "admin" }.map(\.id)
    }

    var body: some View {
        List {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            } else {
                if members.isEmpty {
                    Section {
                        Text("No one else has access yet.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section("Members") {
                        ForEach(members) { member in
                            MemberRow(
                                member: member,
                                canManage: !ownedHomeIds.isEmpty,
                                onRoleChange: { newRole in
                                    Task { await changeRole(userId: member.id, role: newRole) }
                                },
                                onRemove: {
                                    Task { await removeMember(userId: member.id) }
                                }
                            )
                        }
                    }
                }

                if !ownedHomeIds.isEmpty {
                    Section {
                        Button {
                            showInvite = true
                        } label: {
                            Label("Invite someone", systemImage: "person.badge.plus")
                        }
                    }
                }
            }

            if let error = errorMessage {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
        }
        .navigationTitle("Sharing")
        .navigationBarTitleDisplayMode(.inline)
        .cubbyNavigationBarChrome(title: "Sharing")
        .sheet(isPresented: $showInvite) {
            InviteSheet(
                email: $inviteEmail,
                role: $inviteRole,
                onInvite: {
                    Task { await invite() }
                }
            )
        }
        .task { await loadMembers() }
    }

    private func loadMembers() async {
        isLoading = true
        var seen = Set<String>()
        var allMembers: [Member] = []
        for homeId in ownedHomeIds {
            do {
                let homeMembers = try await APIClient.shared.listMembers(homeId: homeId)
                for m in homeMembers where !seen.contains(m.id) {
                    seen.insert(m.id)
                    allMembers.append(m)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        members = allMembers
        isLoading = false
    }

    private func invite() async {
        errorMessage = nil
        let email = inviteEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !email.isEmpty else { return }

        do {
            for homeId in ownedHomeIds {
                try await APIClient.shared.inviteMember(homeId: homeId, email: email, role: inviteRole)
            }
            inviteEmail = ""
            await loadMembers()
        } catch APIError.httpError(_, let message) {
            errorMessage = message
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func changeRole(userId: String, role: String) async {
        errorMessage = nil
        do {
            for homeId in ownedHomeIds {
                try await APIClient.shared.updateMember(homeId: homeId, userId: userId, role: role)
            }
            await loadMembers()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func removeMember(userId: String) async {
        errorMessage = nil
        do {
            for homeId in ownedHomeIds {
                try await APIClient.shared.removeMember(homeId: homeId, userId: userId)
            }
            members.removeAll { $0.id == userId }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Member row

struct MemberRow: View {
    let member: Member
    let canManage: Bool
    let onRoleChange: (String) -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.2))
                    .frame(width: 38, height: 38)
                Text(String(member.name.prefix(1)).uppercased())
                    .font(.headline)
                    .foregroundStyle(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(member.name)
                    .font(.body)
                Text(member.email)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if canManage {
                Menu {
                    ForEach(["editor", "viewer"], id: \.self) { role in
                        Button {
                            onRoleChange(role)
                        } label: {
                            HStack {
                                Text(role.capitalized)
                                if member.role == role {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                    Divider()
                    Button("Remove", role: .destructive) { onRemove() }
                } label: {
                    Text(member.role.capitalized)
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(Capsule())
                }
            } else {
                Text(member.role.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Invite sheet

struct InviteSheet: View {
    @Binding var email: String
    @Binding var role: String
    let onInvite: () -> Void
    @Environment(\.dismiss) private var dismiss

    private var canInvite: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Email") {
                    TextField(
                        "Email",
                        text: $email,
                        prompt: Text("user@example.com").foregroundStyle(.secondary)
                    )
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                }
                Section("Role") {
                    Picker("Role", selection: $role) {
                        Text("Editor").tag("editor")
                        Text("Viewer").tag("viewer")
                    }
                    .pickerStyle(.segmented)

                    Group {
                        switch role {
                        case "editor":
                            Text("Can add/edit items and locations.")
                        default:
                            Text("Can view items and locations only.")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .cubbyNavigationBarChrome()
            .toolbar {
                ToolbarItem(placement: .principal) {
                    CubbyNavigationBrandTitle(title: "Invite Member")
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        CubbyWoodTextButtonLabel(title: "Cancel")
                    }
                    .buttonStyle(.plain)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onInvite()
                        dismiss()
                    } label: {
                        CubbyWoodTextButtonLabel(title: "Invite")
                    }
                    .buttonStyle(.plain)
                    .disabled(!canInvite)
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }
}
