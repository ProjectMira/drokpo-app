import FirebaseAuth
import FirebaseStorage
import UIKit

enum PhotoUploaderError: LocalizedError {
    case notAuthenticated
    case invalidImage

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "You need to sign in again."
        case .invalidImage: return "That photo couldn't be processed. Try a different one."
        }
    }
}

enum PhotoUploader {
    static let maxDimension: CGFloat = 1600
    static let jpegQuality: CGFloat = 0.8

    /// Uploads a profile photo to Firebase Storage and returns its storage path
    /// for the backend confirm endpoints.
    static func upload(_ image: UIImage) async throws -> String {
        guard let uid = Auth.auth().currentUser?.uid else { throw PhotoUploaderError.notAuthenticated }
        guard let data = downscaledJPEG(from: image) else { throw PhotoUploaderError.invalidImage }

        let path = "users/\(uid)/photos/\(UUID().uuidString).jpg"
        let ref = Storage.storage().reference(withPath: path)
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        _ = try await ref.putDataAsync(data, metadata: metadata)
        return path
    }

    static func downloadURL(for storagePath: String) async throws -> URL {
        try await Storage.storage().reference(withPath: storagePath).downloadURL()
    }

    private static func downscaledJPEG(from image: UIImage) -> Data? {
        let largestSide = max(image.size.width, image.size.height)
        guard largestSide > maxDimension else { return image.jpegData(compressionQuality: jpegQuality) }

        let scale = maxDimension / largestSide
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        return resized.jpegData(compressionQuality: jpegQuality)
    }
}
