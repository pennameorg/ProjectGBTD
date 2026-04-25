import Foundation
import Combine

enum GraphAPIError: LocalizedError {
    case unauthorized
    case forbidden
    case networkError(String)
    case decodingError(String)
    case apiError(Int, String)

    var errorDescription: String? {
        switch self {
        case .unauthorized: return "Not authenticated. Please sign in again."
        case .forbidden: return "Access denied. Ensure AuditLog.Read.All permission is granted in Azure AD."
        case .networkError(let m): return "Network error: \(m)"
        case .decodingError(let m): return "Response parsing error: \(m)"
        case .apiError(let code, let m): return "API error \(code): \(m)"
        }
    }
}

struct SignInFilter {
    var startDate: Date?
    var endDate: Date?
    var userPrincipalName: String = ""
    var statusFilter: StatusFilter = .all
    var topCount: Int = 50

    enum StatusFilter: String, CaseIterable {
        case all = "All"
        case success = "Success"
        case failure = "Failure"
    }

    func buildODataFilter() -> String {
        var clauses: [String] = []
        // Date.ISO8601Format() is Sendable-safe (no actor isolation)
        if let start = startDate {
            clauses.append("createdDateTime ge \(start.ISO8601Format())")
        }
        if let end = endDate {
            clauses.append("createdDateTime le \(end.ISO8601Format())")
        }
        if !userPrincipalName.isEmpty {
            // Escape single quotes per OData spec to prevent injection
            let safe = userPrincipalName.replacingOccurrences(of: "'", with: "''")
            clauses.append("userPrincipalName eq '\(safe)'")
        }
        switch statusFilter {
        case .success: clauses.append("status/errorCode eq 0")
        case .failure: clauses.append("status/errorCode ne 0")
        case .all: break
        }
        return clauses.joined(separator: " and ")
    }
}

@MainActor
final class GraphAPIService: ObservableObject {
    static let shared = GraphAPIService()

    nonisolated init() {}

    @Published var signInLogs: [SignInLog] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var hasNextPage = false

    private let baseURL = "https://graph.microsoft.com/v1.0"
    private var nextLink: String?
    private let urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        return URLSession(configuration: config)
    }()

    func fetchSignInLogs(filter: SignInFilter) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        nextLink = nil
        do {
            let token = try await AuthManager.shared.getValidToken()
            let urlString = try buildURL(filter: filter)
            let (logs, next) = try await fetchPage(token: token, urlString: urlString)
            signInLogs = logs
            nextLink = next
            hasNextPage = next != nil
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func fetchNextPage() async {
        guard !isLoading, let link = nextLink else { return }
        isLoading = true
        do {
            let token = try await AuthManager.shared.getValidToken()
            let (logs, next) = try await fetchPage(token: token, urlString: link)
            signInLogs.append(contentsOf: logs)
            nextLink = next
            hasNextPage = next != nil
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func buildURL(filter: SignInFilter) throws -> String {
        guard var components = URLComponents(string: "\(baseURL)/auditLogs/signIns") else {
            throw GraphAPIError.networkError("Invalid base URL.")
        }
        var items = [URLQueryItem(name: "$top", value: String(filter.topCount))]
        let filterString = filter.buildODataFilter()
        if !filterString.isEmpty {
            items.append(URLQueryItem(name: "$filter", value: filterString))
        }
        components.queryItems = items
        guard let url = components.url else {
            throw GraphAPIError.networkError("Could not construct request URL.")
        }
        return url.absoluteString
    }

    private func parseGraphErrorMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any],
              let message = error["message"] as? String
        else { return nil }
        return message
    }

    private func fetchPage(token: String, urlString: String) async throws -> ([SignInLog], String?) {
        guard let url = URL(string: urlString) else {
            throw GraphAPIError.networkError("Invalid URL.")
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GraphAPIError.networkError("Invalid server response.")
        }
        switch http.statusCode {
        case 200: break
        case 401: throw GraphAPIError.unauthorized
        case 403: throw GraphAPIError.forbidden
        default:
            let message = parseGraphErrorMessage(from: data) ?? "Unexpected server response."
            throw GraphAPIError.apiError(http.statusCode, message)
        }
        do {
            let decoded = try JSONDecoder().decode(GraphResponse<SignInLog>.self, from: data)
            return (decoded.value, decoded.nextLink)
        } catch {
            throw GraphAPIError.decodingError(error.localizedDescription)
        }
    }
}
