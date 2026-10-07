import SwiftUI
import UIKit
import UserNotifications

// MARK: - Appearance

/// Light/dark override the user can pick in Settings, persisted in @AppStorage.
/// `.system` (nil colorScheme) follows the device setting.
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    @AppStorage("drokpo.appearance") private var appearance: AppearanceMode = .system
    @State private var showDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var errorMessage: String?
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Appearance") {
                    Picker("Theme", selection: $appearance) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    HStack {
                        Label("Likes, matches, and messages", systemImage: "bell.badge")
                        Spacer()
                        Text(notificationStatusLabel)
                            .foregroundStyle(notificationStatus == .denied ? .orange : .secondary)
                    }
                    if notificationStatus == .denied {
                        Button("Open Notification Settings") {
                            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                            UIApplication.shared.open(url)
                        }
                    }
                } header: {
                    Text("Notifications")
                } footer: {
                    Text("Turn these on to know when someone likes you or sends a message.")
                }
                Section("About") {
                    Link(destination: AppConfig.privacyPolicyURL) {
                        HStack {
                            Text("Privacy policy")
                            Spacer()
                            Image(systemName: "arrow.up.right").foregroundStyle(.secondary)
                        }
                    }
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(appVersion).foregroundStyle(.secondary)
                    }
                }
                Section("Privacy & activity") {
                    NavigationLink("Blocked users") { BlockedUsersView() }
                    NavigationLink("Messages you've sent") { SentMessagesView() }
                }
                Section("Account") {
                    Button("Sign out") {
                        dismiss()
                        session.signOut()
                    }
                    Button("Delete account", role: .destructive) {
                        showDeleteConfirmation = true
                    }
                    .disabled(isDeleting)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .overlay { if isDeleting { ProgressView() } }
            .task { await refreshNotificationStatus() }
            .onAppear { Task { await refreshNotificationStatus() } }
            .confirmationDialog(
                "Delete your account?",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete everything", role: .destructive) {
                    Task { await deleteAccount() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your profile, photos, likes, and matches will be permanently removed. This cannot be undone.")
            }
            .alert("Couldn't delete account", isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func deleteAccount() async {
        isDeleting = true
        defer { isDeleting = false }
        do {
            let _: EmptyResponse = try await APIClient.shared.delete("/api/profile/me")
            // The backend already deleted the Firebase Auth user; signing out
            // clears the now-invalid local session.
            dismiss()
            session.signOut()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var notificationStatusLabel: String {
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral: "On"
        case .denied: "Off"
        case .notDetermined: "Not set"
        @unknown default: "Unavailable"
        }
    }

    private func refreshNotificationStatus() async {
        notificationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }
}

// MARK: - Blocked users

struct BlockedUsersView: View {
    @State private var store = BlockStore.shared
    @State private var workingUid: String?
    @State private var errorMessage: String?

    var body: some View {
        List {
            if store.blocked.isEmpty {
                ContentUnavailableView(
                    "No blocked users",
                    systemImage: "hand.raised",
                    description: Text("People you block from the feed will show up here.")
                )
            } else {
                ForEach(store.blocked) { user in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(user.displayName ?? "Member")
                            Text(user.blockedAt, style: .date)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Unblock") {
                            Task { await unblock(user) }
                        }
                        .buttonStyle(.bordered)
                        .disabled(workingUid != nil)
                    }
                }
            }
        }
        .navigationTitle("Blocked users")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Couldn't unblock", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func unblock(_ user: BlockedUser) async {
        workingUid = user.uid
        defer { workingUid = nil }
        do {
            try await BlockStore.shared.unblock(user)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Sent messages

/// Recent messages you've sent across all conversations (GET /api/messages/sent).
struct SentMessagesView: View {
    @State private var messages: [SentMessage] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.secondary)
            } else if messages.isEmpty && !isLoading {
                ContentUnavailableView(
                    "Nothing sent yet",
                    systemImage: "paperplane",
                    description: Text("Messages you send in your chats will show up here.")
                )
            } else {
                ForEach(messages) { message in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(message.text ?? "")
                            .lineLimit(3)
                        if let date = message.sentDate {
                            Text(date, format: .relative(presentation: .named))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Sent messages")
        .navigationBarTitleDisplayMode(.inline)
        .overlay { if isLoading { ProgressView() } }
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        do {
            let list: TolerantList<SentMessage> = try await APIClient.shared.get(
                "/api/messages/sent",
                query: [URLQueryItem(name: "limit", value: "100")]
            )
            messages = list.items
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
