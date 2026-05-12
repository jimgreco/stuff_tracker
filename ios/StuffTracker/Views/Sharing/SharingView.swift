import SwiftUI

struct SharingView: View {
    let homeId: String
    let userRole: String
    @Environment(\.dismiss) private var dismiss
    @State private var members: [Member] = []
    @State private var isLoading = true
    @State private var showInvite = false
    @State private var inviteEmail = ""
    @State private var inviteRole = "editor"
    @State private var errorMessage: String?

    var canManage: Bool { userRole == "owner" || userRole == "admin" }

    var body: some View {
        NavigationStack {
            List {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                } else {
                    Section("Members") {
                        ForEach(members) { member in
                            MemberRow(
                                member: member,
                                canManage: canManage,
                                onRoleChange: { newRole in
                                    Task { await changeRole(userId: member.id, role: newRole) }
                                },
                                onRemove: {
                                    Task { await removeMember(userId: member.id) }
                                }
                            )
                        }
                    }

                    if canManage {
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
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
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
    }

    private func loadMembers() async {
        isLoading = true
        do {
            members = try await APIClient.shared.listMembers(homeId: homeId)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func invite() async {
        do {
            try await APIClient.shared.inviteMember(homeId: homeId, email: inviteEmail, role: inviteRole)
            inviteEmail = ""
            await loadMembers()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func changeRole(userId: String, role: String) async {
        do {
            try await APIClient.shared.updateMember(homeId: homeId, userId: userId, role: role)
            await loadMembers()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func removeMember(userId: String) async {
        do {
            try await APIClient.shared.removeMember(homeId: homeId, userId: userId)
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
            // Avatar
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
                    ForEach(["admin", "editor", "viewer"], id: \.self) { role in
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

    var body: some View {
        NavigationStack {
            Form {
                Section("Email") {
                    TextField("user@example.com", text: $email)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                }
                Section("Role") {
                    Picker("Role", selection: $role) {
                        Text("Admin").tag("admin")
                        Text("Editor").tag("editor")
                        Text("Viewer").tag("viewer")
                    }
                    .pickerStyle(.segmented)

                    Group {
                        switch role {
                        case "admin":
                            Text("Can invite others and manage members.")
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
            .navigationTitle("Invite Member")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Invite") {
                        onInvite()
                        dismiss()
                    }
                    .disabled(email.isEmpty)
                }
            }
        }
    }
}
