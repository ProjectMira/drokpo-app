import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct ProfileView: View {
    @Environment(SessionStore.self) private var session

    @State private var showEditSheet = false
    @State private var showSettings = false
    @State private var showPreview = false
    @State private var photoSelection: PhotosPickerItem?
    @State private var isWorking = false
    @State private var errorMessage: String?

    /// Optimistic mirror of `profile?.photos` so drag-to-reorder feels instant;
    /// re-synced from the server profile after each commit (or on failure).
    @State private var orderedPhotos: [Photo] = []
    @State private var draggedPhoto: Photo?
    /// Optimistic value for the "Show me in Discover" switch while its save
    /// is in flight; nil means "use the server profile".
    @State private var pendingDiscoverable: Bool?

    private var profile: Profile? { session.myProfile }

    var body: some View {
        NavigationStack {
            List {
                if profileCompletionCount < profileCompletionTotal {
                    profileStrengthSection
                }
                photosSection
                aboutSection
                promptsSection
                socialsSection
                preferencesSection
                accountSection
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
                    Button {
                        showPreview = true
                    } label: {
                        Image(systemName: "eye")
                    }
                    .disabled(profile == nil)
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
            .sheet(isPresented: $showPreview) {
                if let profile {
                    NavigationStack {
                        ProfileDetailView(card: profile.asFeedCard)
                            .navigationTitle("Preview")
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar {
                                ToolbarItem(placement: .confirmationAction) {
                                    Button("Done") { showPreview = false }
                                }
                            }
                    }
                }
            }
            .refreshable { await session.refreshProfile() }
            .onAppear { syncPhotos() }
            .onChange(of: profile?.photos) { syncPhotos() }
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
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(orderedPhotos) { photo in
                        photoCell(photo)
                            .opacity(draggedPhoto?.id == photo.id ? 0.5 : 1)
                            .onDrag {
                                draggedPhoto = photo
                                return NSItemProvider(object: photo.storagePath as NSString)
                            }
                            .onDrop(of: [.text], delegate: PhotoDropDelegate(
                                photo: photo,
                                orderedPhotos: $orderedPhotos,
                                draggedPhoto: $draggedPhoto,
                                onCommit: { Task { await commitOrder() } }
                            ))
                    }
                    if orderedPhotos.count < 6 {
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
        } header: {
            Text("Photos")
        } footer: {
            Text("Drag to reorder — your first photo is the one people see on your card.")
        }
    }

    // A usable dating profile needs more than a name. This deliberately
    // focuses on the details that help someone decide to start a conversation
    // and leaves optional social links out of the score.
    private let profileCompletionTotal = 4

    private var answeredPromptCount: Int {
        Vocabulary.questions.reduce(into: 0) { count, question in
            if let answer = profile?.answers?[question.key], !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                count += 1
            }
        }
    }

    private var profileCompletionCount: Int {
        var count = 0
        if !(profile?.photos ?? []).isEmpty { count += 1 }
        if !(profile?.bio ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { count += 1 }
        if !(profile?.interests ?? []).isEmpty { count += 1 }
        if answeredPromptCount >= 2 { count += 1 }
        return count
    }

    private var profileCompletionHint: String {
        if (profile?.photos ?? []).isEmpty { return "Add a photo so people can recognize you." }
        if (profile?.bio ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Add a short bio to share a little about yourself." }
        if (profile?.interests ?? []).isEmpty { return "Choose a few interests to find common ground." }
        return "Answer one more prompt to make starting a conversation easier."
    }

    private var profileStrengthSection: some View {
        Section("Profile strength") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("\(profileCompletionCount) of \(profileCompletionTotal) essentials complete")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(profileCompletionCount * 25)%")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: Double(profileCompletionCount), total: Double(profileCompletionTotal))
                    .tint(.accentColor)
                Text(profileCompletionHint)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Complete profile") { showEditSheet = true }
                    .buttonStyle(.bordered)
            }
            .padding(.vertical, 4)
        }
    }

    private func photoCell(_ photo: Photo) -> some View {
        let isPrimary = orderedPhotos.first?.id == photo.id
        return RemotePhotoView(photo: photo)
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
            .overlay(alignment: .bottomLeading) {
                if isPrimary {
                    Text("Primary")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(.black.opacity(0.6)))
                        .padding(4)
                }
            }
    }

    /// Re-mirror the server photos into the local order, unless a drag is in
    /// flight (so a mid-drag profile refresh doesn't clobber the reorder).
    private func syncPhotos() {
        guard draggedPhoto == nil else { return }
        orderedPhotos = profile?.photos ?? []
    }

    private func commitOrder() async {
        draggedPhoto = nil
        let newOrder = orderedPhotos.map(\.storagePath)
        guard newOrder != (profile?.photos ?? []).map(\.storagePath) else { return }
        do {
            let _: EmptyResponse = try await APIClient.shared.patch(
                "/api/profile/me/photos/order",
                body: PhotoOrderUpdate(storagePaths: newOrder)
            )
            await session.refreshProfile()
        } catch {
            errorMessage = error.localizedDescription
            await session.refreshProfile() // revert the optimistic order
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

    private var promptsSection: some View {
        Section {
            let answered = Vocabulary.questions.compactMap { question -> (label: String, answer: String)? in
                guard let answer = profile?.answers?[question.key], !answer.isEmpty else { return nil }
                return (question.label, answer)
            }
            if answered.isEmpty {
                Text("Answer a few prompts in Edit — they're the easiest way to start conversations.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(answered, id: \.label) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.label).font(.caption).foregroundStyle(.secondary)
                        Text(item.answer)
                    }
                }
            }
        } header: {
            Text("Prompts")
        }
    }

    private var socialsSection: some View {
        Section("Socials") {
            row("Instagram", profile?.socials?.instagram.flatMap { $0.isEmpty ? nil : "@\($0)" })
            if let youtube = profile?.socials?.youtube, !youtube.isEmpty {
                row("YouTube", youtube)
            }
            if let tiktok = profile?.socials?.tiktok, !tiktok.isEmpty {
                row("TikTok", "@\(tiktok)")
            }
        }
    }

    private var isDiscoverable: Bool {
        pendingDiscoverable ?? profile?.discoverable ?? true
    }

    private var preferencesSection: some View {
        Section {
            Toggle("Show me in Discover", isOn: Binding(
                get: { isDiscoverable },
                set: { newValue in Task { await setDiscoverable(newValue) } }
            ))
            .disabled(profile == nil || pendingDiscoverable != nil)
            let preferences = profile?.preferences ?? Preferences()
            row("Age range", "\(preferences.ageMin)–\(preferences.ageMax)")
            row("Distance", "\(preferences.distanceKm) km")
        } header: {
            Text("Discovery preferences")
        } footer: {
            Text(isDiscoverable
                ? "Your profile can appear in other people's swipe deck."
                : "Your profile is hidden — nobody can find you by swiping. Your matches and chats keep working.")
        }
    }

    private func setDiscoverable(_ value: Bool) async {
        pendingDiscoverable = value
        defer { pendingDiscoverable = nil }
        do {
            let _: EmptyResponse = try await APIClient.shared.patch(
                "/api/profile/me",
                body: ProfileUpdate(discoverable: value)
            )
            await session.refreshProfile()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var accountSection: some View {
        Section {
            row("Email", session.email)
        } header: {
            Text("Account")
        } footer: {
            Text("The account you're signed in with. Only you can see this.")
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
    @State private var answers: [String: String]
    @State private var instagram: String
    @State private var youtube: String
    @State private var tiktok: String
    @State private var ageRange: ClosedRange<Double>
    @State private var distanceKm: Double

    @State private var isSaving = false
    @State private var isLocating = false
    @State private var locationStatus: String?
    @State private var updatedLocation: GeoLocation?
    /// Location permission is off — the footer offers a Settings shortcut.
    @State private var locationDenied = false
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
        _answers = State(initialValue: profile.answers ?? [:])
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

    /// Region options, prepending the user's stored value when it's a legacy
    /// region (e.g. U-Tsang/Kham/Amdo) no longer offered — otherwise a Picker
    /// whose selection isn't among the tags renders blank.
    private var regionOptions: [String] {
        if !region.isEmpty, !Vocabulary.regions.contains(region) {
            return [region] + Vocabulary.regions
        }
        return Vocabulary.regions
    }

    /// Same passthrough for education: profiles created before the picker
    /// existed may hold free text that isn't among the level options.
    private var educationOptions: [String] {
        if !education.isEmpty, !Vocabulary.educationLevels.contains(education) {
            return [education] + Vocabulary.educationLevels
        }
        return Vocabulary.educationLevels
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
                    Picker("Education", selection: $education) {
                        Text("Not set").tag("")
                        ForEach(educationOptions, id: \.self) { Text($0).tag($0) }
                    }
                    Picker("Region", selection: $region) {
                        Text("Not set").tag("")
                        ForEach(regionOptions, id: \.self) { Text($0).tag($0) }
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
                    VStack(alignment: .leading, spacing: 4) {
                        Text(locationStatus ?? "Your location decides who shows up in your feed. Update it after you move or travel.")
                        if locationDenied, let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                            Link("Open Settings", destination: settingsURL)
                        }
                    }
                }
                Section {
                    socialField("Instagram", text: $instagram)
                    socialField("YouTube", text: $youtube)
                    socialField("TikTok", text: $tiktok)
                } header: {
                    Text("Socials")
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
                ProfileQuestionFields(answers: $answers)
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
            locationDenied = false
            locationStatus = "Location updated — save to apply."
        } else if fetcher.isDenied {
            locationDenied = true
            locationStatus = "Location access is off for Drokpo. You can turn it on in Settings — until then your feed uses your saved location."
        } else {
            locationStatus = "Couldn't get your location right now. Try again in a moment."
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
            answers: answers.compactMapValues {
                let trimmed = $0.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            },
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

/// Reorders photos as you drag one over another. Lives inside the ScrollView,
/// where `.onMove` doesn't work; swaps optimistically on `dropEntered` and
/// commits to the backend on drop.
private struct PhotoDropDelegate: DropDelegate {
    let photo: Photo
    @Binding var orderedPhotos: [Photo]
    @Binding var draggedPhoto: Photo?
    let onCommit: () -> Void

    func dropEntered(info: DropInfo) {
        guard let dragged = draggedPhoto, dragged.id != photo.id,
              let from = orderedPhotos.firstIndex(of: dragged),
              let to = orderedPhotos.firstIndex(of: photo) else { return }
        withAnimation {
            orderedPhotos.move(
                fromOffsets: IndexSet(integer: from),
                toOffset: to > from ? to + 1 : to
            )
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedPhoto = nil
        onCommit()
        return true
    }
}
