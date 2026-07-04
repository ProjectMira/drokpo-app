import Foundation
import FirebaseAuth

enum APIError: LocalizedError {
    case notAuthenticated
    case http(status: Int, message: String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You need to sign in again."
        case .http(let status, let message):
            return message.isEmpty ? "Server error (\(status))." : message
        case .invalidResponse:
            return "Unexpected response from the server."
        }
    }
}

/// Decodes successfully from any JSON object; used when the response body doesn't matter.
struct EmptyResponse: Decodable {}

final class APIClient {
    static let shared = APIClient()

    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        try await request(method: "GET", path: path, query: query, bodyData: nil)
    }

    func post<T: Decodable>(_ path: String) async throws -> T {
        try await request(method: "POST", path: path, query: [], bodyData: nil)
    }

    func post<T: Decodable, Body: Encodable>(_ path: String, body: Body) async throws -> T {
        try await request(method: "POST", path: path, query: [], bodyData: try encoder.encode(body))
    }

    func patch<T: Decodable, Body: Encodable>(_ path: String, body: Body) async throws -> T {
        try await request(method: "PATCH", path: path, query: [], bodyData: try encoder.encode(body))
    }

    func delete<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        try await request(method: "DELETE", path: path, query: query, bodyData: nil)
    }

    private func request<T: Decodable>(
        method: String,
        path: String,
        query: [URLQueryItem],
        bodyData: Data?
    ) async throws -> T {
        guard let user = Auth.auth().currentUser else { throw APIError.notAuthenticated }
        let token = try await user.getIDToken()
        #if DEBUG
        print("CHANGSA_DEBUG_TOKEN: \(token)")
        #endif

        var components = URLComponents(
            url: AppConfig.apiBaseURL.appending(path: path),
            resolvingAgainstBaseURL: false
        )!
        if !query.isEmpty { components.queryItems = query }

        var urlRequest = URLRequest(url: components.url!)
        urlRequest.httpMethod = method
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let bodyData {
            urlRequest.httpBody = bodyData
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.http(status: http.statusCode, message: Self.errorMessage(from: data))
        }
        return try decoder.decode(T.self, from: data)
    }

    private static func errorMessage(from data: Data) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return "" }
        if let detail = json["detail"] as? String { return detail }
        if let details = json["detail"] as? [[String: Any]] {
            return details.compactMap { $0["msg"] as? String }.joined(separator: "\n")
        }
        return ""
    }
}
