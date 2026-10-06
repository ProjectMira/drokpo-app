import SwiftUI

@Observable
final class CommunityOnboardingModel {
    enum Step: Int, CaseIterable {
        case basics, contact, contactPerson, address, photos
    }

    var step: Step = .basics

    // Basics
    var name = ""
    var communityDescription = ""

    // Contact
    var website = ""
    var phone = ""
    var email = ""
    var instagram = ""
    var youtube = ""
    var tiktok = ""
    var facebook = ""

    // Contact person
    var contactName = ""
    var contactRole = ""
    var contactPhone = ""
    var contactEmail = ""

    // Address
    var line1 = ""
    var city = ""
    var state = ""
    var country = ""
    var postalCode = ""

    // Photos
    var pickedImages: [UIImage] = []

    var isSubmitting = false
    var errorMessage: String?
    /// True once POST /api/communities/onboarding (and any picked photos)
    /// succeed; the view uses this to hand control back to SessionStore.
    var completed = false

    var canAdvance: Bool {
        switch step {
        case .basics:
            return !name.trimmed.isEmpty && !communityDescription.trimmed.isEmpty
        case .contact:
            // The backend requires a community email (the verification
            // outcome is mailed there); everything else is optional.
            return email.trimmed.contains("@")
        case .contactPerson:
            return !contactName.trimmed.isEmpty
        case .address:
            return !city.trimmed.isEmpty && !country.trimmed.isEmpty
        case .photos:
            return true // no photo is required to finish
        }
    }

    func back() {
        if let previous = Step(rawValue: step.rawValue - 1) { step = previous }
    }

    /// Leaving the address step creates the community on the backend (all
    /// text fields collected so far); leaving the photos step just finishes —
    /// any picked photos upload first. If the user goes Back after the
    /// community was created and comes forward again, the edits are saved
    /// with a PATCH instead of re-POSTing onboarding (which would 409).
    @MainActor
    func advance() async {
        guard canAdvance else { return }
        switch step {
        case .address:
            if communityCreated {
                await updateCommunity()
            } else {
                await createCommunity()
            }
        case .photos:
            await uploadPhotosAndFinish()
        default:
            step = Step(rawValue: step.rawValue + 1) ?? step
        }
    }

    private func nonEmpty(_ text: String) -> String? {
        let trimmed = text.trimmed
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Set once POST /api/communities/onboarding succeeds — the doc now
    /// exists, so going Back and Continuing again must PATCH, never re-POST.
    private var communityCreated = false

    @MainActor
    private func createCommunity() async {
        isSubmitting = true
        defer { isSubmitting = false }
        let socials = Socials(
            instagram: nonEmpty(instagram),
            youtube: nonEmpty(youtube),
            tiktok: nonEmpty(tiktok),
            facebook: nonEmpty(facebook)
        )
        let body = CommunityOnboardingIn(
            name: name.trimmed,
            description: communityDescription.trimmed,
            website: nonEmpty(website),
            phone: nonEmpty(phone),
            email: email.trimmed,
            contactPerson: ContactPerson(
                name: contactName.trimmed,
                role: nonEmpty(contactRole),
                phone: nonEmpty(contactPhone),
                email: nonEmpty(contactEmail)
            ),
            address: CommunityAddress(
                line1: nonEmpty(line1),
                city: city.trimmed,
                state: nonEmpty(state),
                country: country.trimmed,
                postalCode: nonEmpty(postalCode)
            ),
            socials: socials
        )
        do {
            let _: EmptyResponse = try await APIClient.shared.post("/api/communities/onboarding", body: body)
            communityCreated = true
            step = .photos
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Second pass over the address step after the community already exists:
    /// persist whatever the user changed on the earlier steps via PATCH.
    /// Optional fields go up as "" when emptied (the backend clears them).
    @MainActor
    private func updateCommunity() async {
        isSubmitting = true
        defer { isSubmitting = false }
        let body = CommunityUpdate(
            name: name.trimmed,
            description: communityDescription.trimmed,
            website: website.trimmed,
            phone: phone.trimmed,
            email: email.trimmed,
            contactPerson: ContactPerson(
                name: contactName.trimmed,
                role: contactRole.trimmed,
                phone: contactPhone.trimmed,
                email: contactEmail.trimmed
            ),
            address: CommunityAddress(
                line1: line1.trimmed,
                city: city.trimmed,
                state: state.trimmed,
                country: country.trimmed,
                postalCode: postalCode.trimmed
            ),
            socials: Socials(
                instagram: instagram.trimmed,
                youtube: youtube.trimmed,
                tiktok: tiktok.trimmed,
                facebook: facebook.trimmed
            )
        )
        do {
            let _: EmptyResponse = try await APIClient.shared.patch("/api/communities/me", body: body)
            step = .photos
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Images already uploaded+confirmed with the backend, tracked by object
    /// identity — positional counting breaks as soon as the user edits the
    /// grid between a partial failure and the retry.
    private var confirmedImages: Set<ObjectIdentifier> = []

    @MainActor
    private func uploadPhotosAndFinish() async {
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            for (index, image) in pickedImages.enumerated()
            where !confirmedImages.contains(ObjectIdentifier(image)) {
                let storagePath = try await PhotoUploader.uploadCommunityPhoto(image)
                let _: EmptyResponse = try await APIClient.shared.post(
                    "/api/communities/me/photos",
                    body: CommunityPhotoConfirm(storagePath: storagePath, order: index)
                )
                confirmedImages.insert(ObjectIdentifier(image))
            }
            completed = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
