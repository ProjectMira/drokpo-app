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
                    case .seeking: SeekingStep(model: model)
                    case .details: DetailsStep(model: model)
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

private struct SeekingStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        Form {
            Section("I'm looking for") {
                ForEach(Vocabulary.genders, id: \.self) { gender in
                    MultiSelectRow(
                        title: gender.capitalized,
                        isSelected: model.seekingGenders.contains(gender)
                    ) {
                        model.seekingGenders.toggle(gender)
                    }
                }
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
            Section("About me") {
                TextField("A few words about yourself…", text: $model.bio, axis: .vertical)
                    .lineLimit(3...6)
            }
        }
    }
}

private struct LocationStep: View {
    @Bindable var model: OnboardingModel
    @State private var fetcher = LocationFetcher()
    @State private var isFetching = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: model.location == nil ? "location.circle" : "location.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            Text("Share your location")
                .font(.title2.bold())
            Text("We use it to show you people nearby. If you skip this, we'll use the center of your region instead.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            if model.location != nil {
                Label("Location saved", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button {
                    isFetching = true
                    Task {
                        model.location = await fetcher.requestLocation()
                        isFetching = false
                    }
                } label: {
                    if isFetching {
                        ProgressView()
                    } else {
                        Text("Allow location access")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isFetching)
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
