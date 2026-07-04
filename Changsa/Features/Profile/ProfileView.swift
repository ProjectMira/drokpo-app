import PhotosUI
import SwiftUI

struct ProfileView: View {
    @Environment(SessionStore.self) private var session

    @State private var showEditSheet = false
    @State private var photoSelection: PhotosPickerItem?
    @State private var isWorking = false
    @State private var errorMessage: String?

    private var profile: Profile? { session.myProfile }

    var body: some View {
        NavigationStack {
            List {
                photosSection
                aboutSection
                preferencesSection
                Section {
                    Button("Sign out", role: .destructive) { session.signOut() }
                }
            }
            .navigationTitle("Profile")
            .toolbar {
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
            row("Occupation", profile?.occupation)
            row("Education", profile?.education)
            if let bio = profile?.bio, !bio.isEmpty {
                Text(bio).font(.subheadline)
            }
        }
    }

    private var preferencesSection: some View {
        Section("Discovery preferences") {
            let preferences = profile?.preferences ?? Preferences()
            row("Age range", "\(preferences.ageMin)–\(preferences.ageMax)")
            row("Distance", "\(preferences.distanceKm) km")
            row("Looking for", profile?.seekingGenders?.map(\.capitalized).joined(separator: ", "))
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
                  let image = UIImage(data: data) else { return }
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

struct EditProfileView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var displayName: String
    @State private var bio: String
    @State private var occupation: String
    @State private var education: String
    @State private var region: String
    @State private var languages: Set<String>
    @State private var seekingGenders: Set<String>
    @State private var ageRange: ClosedRange<Double>
    @State private var distanceKm: Double

    @State private var isSaving = false
    @State private var errorMessage: String?

    private let onSaved: () async -> Void

    init(profile: Profile, onSaved: @escaping () async -> Void) {
        _displayName = State(initialValue: profile.displayName ?? "")
        _bio = State(initialValue: profile.bio ?? "")
        _occupation = State(initialValue: profile.occupation ?? "")
        _education = State(initialValue: profile.education ?? "")
        _region = State(initialValue: profile.region ?? "")
        _languages = State(initialValue: Set(profile.languages ?? []))
        _seekingGenders = State(initialValue: Set(profile.seekingGenders ?? []))
        let preferences = profile.preferences ?? Preferences()
        _ageRange = State(initialValue: Double(preferences.ageMin)...Double(preferences.ageMax))
        _distanceKm = State(initialValue: Double(preferences.distanceKm))
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("About") {
                    TextField("Name", text: $displayName)
                    TextField("Bio", text: $bio, axis: .vertical).lineLimit(3...6)
                    TextField("Occupation", text: $occupation)
                    TextField("Education", text: $education)
                    Picker("Region", selection: $region) {
                        ForEach(Vocabulary.regions, id: \.self) { Text($0).tag($0) }
                    }
                }
                Section("Languages") {
                    ForEach(Vocabulary.languages, id: \.self) { language in
                        toggleRow(language, isOn: languages.contains(language)) {
                            toggle(&languages, language)
                        }
                    }
                }
                Section("Looking for") {
                    ForEach(Vocabulary.genders, id: \.self) { gender in
                        toggleRow(gender.capitalized, isOn: seekingGenders.contains(gender)) {
                            toggle(&seekingGenders, gender)
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
                        .disabled(isSaving || displayName.trimmingCharacters(in: .whitespaces).isEmpty)
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

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let body = ProfileUpdate(
            displayName: displayName.trimmingCharacters(in: .whitespaces),
            bio: bio,
            occupation: occupation,
            education: education,
            region: region,
            languages: Array(languages),
            seekingGenders: Array(seekingGenders),
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
