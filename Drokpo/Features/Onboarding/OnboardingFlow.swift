import PhotosUI
import SwiftUI

struct OnboardingFlow: View {
    @Environment(SessionStore.self) private var session
    @State private var model = OnboardingModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ProgressView(
                    value: Double(model.step.rawValue + 1),
                    total: Double(OnboardingModel.Step.allCases.count)
                )
                .padding(.horizontal)

                Group {
                    switch model.step {
                    case .basics: BasicsStep(model: model)
                    case .details: DetailsStep(model: model)
                    case .aboutYou: AboutYouStep(model: model)
                    case .socials: SocialsStep(model: model)
                    case .location: LocationStep(model: model)
                    case .photos: PhotosStep(model: model)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Button {
                    Task {
                        await model.advance()
                        // Refresh so RootView routes into the main app once
                        // onboarding has fully completed.
                        if model.completed {
                            await session.refreshProfile()
                        }
                    }
                } label: {
                    Group {
                        if model.isSubmitting {
                            ProgressView().tint(.white)
                        } else {
                            Text(model.step == .photos ? "Finish" : "Continue")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canAdvance || model.isSubmitting)
                .padding()
            }
            .navigationTitle("Create profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if model.step != .basics {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Back") { model.back() }
                            .disabled(model.isSubmitting)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Sign out") { session.signOut() }
                }
            }
            .alert("Something went wrong", isPresented: .init(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "")
            }
        }
    }
}

// MARK: - Steps

private struct BasicsStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        Form {
            Section("About you") {
                TextField("Your name", text: $model.displayName)
                    .textContentType(.givenName)
                DatePicker(
                    "Date of birth",
                    selection: $model.dob,
                    in: ...model.latestAllowedDOB,
                    displayedComponents: .date
                )
                Picker("I am", selection: $model.gender) {
                    Text("Select").tag("")
                    ForEach(Vocabulary.genders, id: \.self) {
                        Text($0.capitalized).tag($0)
                    }
                }
            }
        }
    }
}

/// Optional get-to-know-you step: work, study, and the friendship prompts.
/// Everything here can be skipped and filled in later from Edit profile.
private struct AboutYouStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        Form {
            Section {
                TextField("Occupation or current job", text: $model.occupation)
                Picker("Education", selection: $model.education) {
                    Text("Select").tag("")
                    ForEach(Vocabulary.educationLevels, id: \.self) { Text($0).tag($0) }
                }
            } header: {
                Text("Work & study")
            } footer: {
                Text("All of this is optional — answer what you like. It helps people find things in common with you.")
            }
            ProfileQuestionFields(answers: $model.answers)
        }
    }
}

private struct SocialsStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("@").foregroundStyle(.secondary)
                    TextField("your_handle", text: $model.instagram)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            } header: {
                Text("Instagram")
            } footer: {
                Text("Required — your Instagram is how new friends verify you're a real person.")
            }
            Section {
                Toggle(isOn: $model.acceptedTerms) {
                    Text("I confirm I am 18 or older and agree to treat other members with respect. Abusive or fake profiles are removed.")
                        .font(.footnote)
                }
            }
        }
    }
}

private struct DetailsStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        Form {
            Section("Where are you from?") {
                Picker("Region", selection: $model.region) {
                    Text("Select").tag("")
                    ForEach(Vocabulary.regions, id: \.self) { Text($0).tag($0) }
                }
            }
            Section("Languages you speak") {
                ForEach(Vocabulary.languages, id: \.self) { language in
                    MultiSelectRow(
                        title: language,
                        isSelected: model.languages.contains(language)
                    ) {
                        model.languages.toggle(language)
                    }
                }
            }
            Section("Interests") {
                ForEach(Vocabulary.interests, id: \.self) { interest in
                    MultiSelectRow(
                        title: interest,
                        isSelected: model.interests.contains(interest)
                    ) {
                        model.interests.toggle(interest)
                    }
                }
            }
            Section("About me") {
                TextField("A few words about yourself…", text: $model.bio, axis: .vertical)
                    .lineLimit(3...6)
            }
        }
    }
}

private struct LocationStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: model.location == nil ? "location.circle" : "location.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            Text("Share your location")
                .font(.title2.bold())
            Text("Drokpo uses your location to show you people nearby. When you tap Continue, iOS will ask whether to share it. If you don't, we'll use the center of your region instead.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            if model.location != nil {
                Label("Location saved", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.tint)
            }
        }
    }
}

private struct PhotosStep: View {
    @Bindable var model: OnboardingModel
    @State private var selection: [PhotosPickerItem] = []

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 8)]

    var body: some View {
        VStack(spacing: 16) {
            Text("Add photos")
                .font(.title2.bold())
            Text("Add 1–6 photos. The first one is your main photo.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ScrollView {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(Array(model.pickedImages.enumerated()), id: \.offset) { index, image in
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 100, height: 133)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(alignment: .topTrailing) {
                                Button {
                                    model.pickedImages.remove(at: index)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.white, .black.opacity(0.6))
                                }
                                .padding(4)
                            }
                    }
                    if model.pickedImages.count < 6 {
                        PhotosPicker(
                            selection: $selection,
                            maxSelectionCount: 6 - model.pickedImages.count,
                            matching: .images
                        ) {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(.quaternary)
                                .frame(width: 100, height: 133)
                                .overlay { Image(systemName: "plus").font(.title2) }
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
        .onChange(of: selection) {
            let items = selection
            selection = []
            Task {
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        model.pickedImages.append(image)
                    }
                }
            }
        }
    }
}

// MARK: - Shared bits

private struct MultiSelectRow: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title).foregroundStyle(.primary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark").foregroundStyle(.tint)
                }
            }
        }
    }
}

private extension Set where Element == String {
    mutating func toggle(_ value: String) {
        if contains(value) { remove(value) } else { insert(value) }
    }
}
