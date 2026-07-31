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
            if !ownedHomeIds.isEmpty {
                Section {
                    Label(
                        ownedHomeIds.count == 1
                            ? "Access applies to this shared home."
                            : "Access changes apply across \(ownedHomeIds.count) homes you manage.",
                        systemImage: "house.fill"
                    )
                    .font(.subheadline)
                    .foregroundStyle(CubbyTheme.mutedInk)
                }
                .cubbySheetRows(prominence: 0.78)
            }

            if isLoading {
                Section {
                    VStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.large)
                            .tint(CubbyTheme.green)
                        Text("Loading collaborators…")
                            .font(.subheadline)
                            .foregroundStyle(CubbyTheme.mutedInk)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 26)
                }
                .cubbySheetRows(prominence: 0.82)
            } else {
                if members.isEmpty {
                    Section {
                        ContentUnavailableView(
                            "Just You for Now",
                            systemImage: "person.2",
                            description: Text("Invite someone when you want to organize a home together.")
                        )
                    }
                    .cubbySheetRows(prominence: 0.86)
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
                    .cubbySheetRows()
                }

                if !ownedHomeIds.isEmpty {
                    Section {
                        Button {
                            showInvite = true
                        } label: {
                            Label("Invite someone", systemImage: "person.badge.plus")
                                .font(.body.weight(.semibold))
                        }
                        .foregroundStyle(CubbyTheme.green)
                    }
                    .cubbySheetRows()
                }
            }

            if let error = errorMessage {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(CubbyTheme.danger)
                        .font(.caption)
                }
                .cubbySheetRows(prominence: 0.92)
            }
        }
        .cubbySheetChrome(title: "Sharing")
        .navigationBarTitleDisplayMode(.inline)
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
                    .fill(CubbyTheme.greenSoft.opacity(0.78))
                    .frame(width: 42, height: 42)
                Text(String(member.name.prefix(1)).uppercased())
                    .font(.headline)
                    .foregroundStyle(CubbyTheme.green)
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
                    CubbyStatusPill(
                        title: member.role.capitalized,
                        systemImage: member.role == "editor" ? "pencil" : "eye"
                    )
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
            } else {
                CubbyStatusPill(
                    title: member.role.capitalized,
                    systemImage: member.role == "editor" ? "pencil" : "eye",
                    tint: CubbyTheme.mutedInk
                )
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
                .cubbySheetRows()
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
                .cubbySheetRows()
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .cubbySheetChrome()
            .tint(CubbyTheme.green)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    CubbyNavigationBrandTitle(title: "Invite Member")
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Invite") {
                        onInvite()
                        dismiss()
                    }
                    .disabled(!canInvite)
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }
}
