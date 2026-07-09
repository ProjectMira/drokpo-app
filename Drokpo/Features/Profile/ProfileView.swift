import PhotosUI
import SwiftUI

struct ProfileView: View {
    @Environment(SessionStore.self) private var session

    @State private var showEditSheet = false
    @State private var showSettings = false
    @State private var photoSelection: PhotosPickerItem?
    @State private var isWorking = false
    @State private var errorMessage: String?

    private var profile: Profile? { session.myProfile }

    var body: some View {
        NavigationStack {
            List {
                photosSection
                aboutSection
                socialsSection
                preferencesSection
            }
            .navigationTitle("Profile")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") { showEditSheet = true }
                }
            }
            .sheet(isPresented: $showEditSheet) {
                if let profile {
                    EditProfileView(profile: profile) {
                        await session.refreshProfile()
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .refreshable { await session.refreshProfile() }
            .overlay { if isWorking { ProgressView() } }
            .alert("Something went wrong", isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var photosSection: some View {
        Section("Photos") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(profile?.photos ?? []) { photo in
                        RemotePhotoView(photo: photo)
                            .frame(width: 90, height: 120)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(alignment: .topTrailing) {
                                Button {
                                    Task { await deletePhoto(photo) }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.white, .black.opacity(0.6))
                                }
                                .padding(4)
                            }
                    }
                    if (profile?.photos?.count ?? 0) < 6 {
                        PhotosPicker(selection: $photoSelection, matching: .images) {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(.quaternary)
                                .frame(width: 90, height: 120)
                                .overlay { Image(systemName: "plus") }
                        }
                    }
                }
            }
            .onChange(of: photoSelection) {
                guard let item = photoSelection else { return }
                photoSelection = nil
                Task { await addPhoto(item) }
            }
        }
    }

    private var aboutSection: some View {
        Section("About") {
            row("Name", profile?.displayName)
            row("Age", profile?.age.map(String.init))
            row("Region", profile?.region)
            row("Languages", profile?.languages?.joined(separator: ", "))
            row("Interests", profile?.interests?.joined(separator: ", "))
            row("Occupation", profile?.occupation)
            row("Education", profile?.education)
            if let bio = profile?.bio, !bio.isEmpty {
                Text(bio).font(.subheadline)
            }
        }
    }

    private var socialsSection: some View {
        Section("Socials") {
            row("Instagram", profile?.socials?.instagram.map { "@\($0)" })
            if let youtube = profile?.socials?.youtube, !youtube.isEmpty {
                row("YouTube", youtube)
            }
            if let tiktok = profile?.socials?.tiktok, !tiktok.isEmpty {
                row("TikTok", "@\(tiktok)")
            }
        }
    }

    private var preferencesSection: some View {
        Section("Discovery preferences") {
            let preferences = profile?.preferences ?? Preferences()
            row("Age range", "\(preferences.ageMin)–\(preferences.ageMax)")
            row("Distance", "\(preferences.distanceKm) km")
        }
    }

    private func row(_ title: String, _ value: String?) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value ?? "—").foregroundStyle(.secondary)
        }
    }

    private func addPhoto(_ item: PhotosPickerItem) async {
        isWorking = true
        defer { isWorking = false }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                errorMessage = PhotoUploaderError.invalidImage.errorDescription
                return
            }
            let storagePath = try await PhotoUploader.upload(image)
            let order = profile?.photos?.count ?? 0
            let _: EmptyResponse = try await APIClient.shared.post(
                "/api/profile/me/photos",
                body: PhotoConfirm(storagePath: storagePath, order: order)
            )
            await session.refreshProfile()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deletePhoto(_ photo: Photo) async {
        isWorking = true
        defer { isWorking = false }
        do {
            let _: EmptyResponse = try await APIClient.shared.delete(
                "/api/profile/me/photos",
                query: [URLQueryItem(name: "storage_path", value: photo.storagePath)]
            )
            await session.refreshProfile()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var showDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var errorMessage: String?

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }

    var body: some View {
        NavigationStack {
            List {
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

// MARK: - Edit profile

struct EditProfileView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var displayName: String
    @State private var bio: String
    @State private var gender: String
    @State private var birthday: Date
    @State private var occupation: String
    @State private var education: String
    @State private var region: String
    @State private var languages: Set<String>
    @State private var interests: Set<String>
    @State private var instagram: String
    @State private var youtube: String
    @State private var tiktok: String
    @State private var ageRange: ClosedRange<Double>
    @State private var distanceKm: Double

    @State private var isSaving = false
    @State private var isLocating = false
    @State private var locationStatus: String?
    @State private var updatedLocation: GeoLocation?
    @State private var errorMessage: String?

    private let onSaved: () async -> Void

    init(profile: Profile, onSaved: @escaping () async -> Void) {
        _displayName = State(initialValue: profile.displayName ?? "")
        _bio = State(initialValue: profile.bio ?? "")
        _gender = State(initialValue: profile.gender ?? "")
        _birthday = State(initialValue: profile.dob.flatMap { Profile.dobFormatter.date(from: $0) } ?? .now)
        _occupation = State(initialValue: profile.occupation ?? "")
        _education = State(initialValue: profile.education ?? "")
        _region = State(initialValue: profile.region ?? "")
        _languages = State(initialValue: Set(profile.languages ?? []))
        _interests = State(initialValue: Set(profile.interests ?? []))
        _instagram = State(initialValue: profile.socials?.instagram ?? "")
        _youtube = State(initialValue: profile.socials?.youtube ?? "")
        _tiktok = State(initialValue: profile.socials?.tiktok ?? "")
        let preferences = profile.preferences ?? Preferences()
        _ageRange = State(initialValue: Double(preferences.ageMin)...Double(preferences.ageMax))
        _distanceKm = State(initialValue: Double(preferences.distanceKm))
        self.onSaved = onSaved
    }

    private var trimmedInstagram: String {
        instagram.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "@", with: "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("About") {
                    TextField("Name", text: $displayName)
                    TextField("Bio", text: $bio, axis: .vertical).lineLimit(3...6)
                    Picker("Gender", selection: $gender) {
                        Text("Not set").tag("")
                        ForEach(Vocabulary.genders, id: \.self) { Text($0.capitalized).tag($0) }
                    }
                    DatePicker(
                        "Birthday",
                        selection: $birthday,
                        in: ...Calendar.current.date(byAdding: .year, value: -18, to: .now)!,
                        displayedComponents: .date
                    )
                    TextField("Occupation", text: $occupation)
                    TextField("Education", text: $education)
                    Picker("Region", selection: $region) {
                        ForEach(Vocabulary.regions, id: \.self) { Text($0).tag($0) }
                    }
                }
                Section {
                    Button {
                        Task { await refreshLocation() }
                    } label: {
                        HStack {
                            Label("Update my location", systemImage: "location")
                            Spacer()
                            if isLocating { ProgressView() }
                        }
                    }
                    .disabled(isLocating)
                } header: {
                    Text("Location")
                } footer: {
                    Text(locationStatus ?? "Your location decides who shows up in your feed. Update it after you move or travel.")
                }
                Section {
                    socialField("Instagram", text: $instagram)
                    socialField("YouTube", text: $youtube)
                    socialField("TikTok", text: $tiktok)
                } header: {
                    Text("Socials")
                } footer: {
                    Text("Instagram is required.")
                }
                Section("Languages") {
                    ForEach(Vocabulary.languages, id: \.self) { language in
                        toggleRow(language, isOn: languages.contains(language)) {
                            toggle(&languages, language)
                        }
                    }
                }
                Section("Interests") {
                    ForEach(Vocabulary.interests, id: \.self) { interest in
                        toggleRow(interest, isOn: interests.contains(interest)) {
                            toggle(&interests, interest)
                        }
                    }
                }
                Section("Discovery preferences") {
                    VStack(alignment: .leading) {
                        Text("Age: \(Int(ageRange.lowerBound))–\(Int(ageRange.upperBound))")
                        RangeSliderRow(range: $ageRange, bounds: 18...99)
                    }
                    VStack(alignment: .leading) {
                        Text("Distance: \(Int(distanceKm)) km")
                        Slider(value: $distanceKm, in: 5...500, step: 5)
                    }
                }
            }
            .navigationTitle("Edit profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(
                            isSaving
                                || displayName.trimmingCharacters(in: .whitespaces).isEmpty
                                || trimmedInstagram.isEmpty
                        )
                }
            }
            .alert("Couldn't save", isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func socialField(_ title: String, text: Binding<String>) -> some View {
        HStack {
            Text(title)
            TextField("handle", text: text)
                .multilineTextAlignment(.trailing)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
    }

    private func toggleRow(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).foregroundStyle(.primary)
                Spacer()
                if isOn { Image(systemName: "checkmark").foregroundStyle(.tint) }
            }
        }
    }

    private func toggle(_ set: inout Set<String>, _ value: String) {
        if set.contains(value) { set.remove(value) } else { set.insert(value) }
    }

    private func refreshLocation() async {
        isLocating = true
        defer { isLocating = false }
        let fetcher = LocationFetcher()
        if let location = await fetcher.requestLocation() {
            updatedLocation = location
            locationStatus = "Location updated — save to apply."
        } else {
            locationStatus = "Couldn't get your location. Check location permissions in Settings."
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let body = ProfileUpdate(
            displayName: displayName.trimmingCharacters(in: .whitespaces),
            bio: bio,
            dob: Profile.dobFormatter.string(from: birthday),
            gender: gender.isEmpty ? nil : gender,
            occupation: occupation,
            education: education,
            region: region,
            languages: Array(languages),
            interests: Array(interests),
            socials: Socials(
                instagram: trimmedInstagram,
                youtube: youtube.trimmingCharacters(in: .whitespaces),
                tiktok: tiktok.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "@", with: "")
            ),
            location: updatedLocation,
            preferences: Preferences(
                ageMin: Int(ageRange.lowerBound),
                ageMax: Int(ageRange.upperBound),
                distanceKm: Int(distanceKm)
            )
        )
        do {
            let _: EmptyResponse = try await APIClient.shared.patch("/api/profile/me", body: body)
            await onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Minimal two-thumb range slider built from two SwiftUI sliders, keeping v1
/// dependency-free.
private struct RangeSliderRow: View {
    @Binding var range: ClosedRange<Double>
    let bounds: ClosedRange<Double>

    var body: some View {
        VStack {
            Slider(
                value: Binding(
                    get: { range.lowerBound },
                    set: { range = min($0, range.upperBound - 1)...range.upperBound }
                ),
                in: bounds
            ) { Text("Minimum age") }
            Slider(
                value: Binding(
                    get: { range.upperBound },
                    set: { range = range.lowerBound...max($0, range.lowerBound + 1) }
                ),
                in: bounds
            ) { Text("Maximum age") }
        }
    }
}
