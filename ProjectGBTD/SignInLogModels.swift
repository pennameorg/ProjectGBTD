import Foundation

struct GraphResponse<T: Codable>: Codable {
    let value: [T]
    let nextLink: String?

    enum CodingKeys: String, CodingKey {
        case value
        case nextLink = "@odata.nextLink"
    }
}

struct SignInLog: Codable, Identifiable, Sendable {
    let id: String
    let createdDateTime: String
    let userDisplayName: String?
    let userPrincipalName: String?
    let userId: String?
    let appId: String?
    let appDisplayName: String?
    let ipAddress: String?
    let clientAppUsed: String?
    let conditionalAccessStatus: String?
    let isInteractive: Bool?
    let riskDetail: String?
    let riskLevelAggregated: String?
    let riskLevelDuringSignIn: String?
    let riskState: String?
    let status: SignInStatus?
    let location: SignInLocation?
    let deviceDetail: DeviceDetail?
    let resourceDisplayName: String?
    let resourceId: String?

    var formattedDate: String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: createdDateTime) {
            return DateFormatter.localizedString(from: date, dateStyle: .short, timeStyle: .medium)
        }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: createdDateTime) {
            return DateFormatter.localizedString(from: date, dateStyle: .short, timeStyle: .medium)
        }
        return createdDateTime
    }

    var isSuccess: Bool { status?.errorCode == 0 }

    var locationString: String {
        [location?.city, location?.countryOrRegion].compactMap { $0 }.joined(separator: ", ")
    }
}

struct SignInStatus: Codable, Sendable {
    let errorCode: Int?
    let failureReason: String?
    let additionalDetails: String?
}

struct SignInLocation: Codable, Sendable {
    let city: String?
    let state: String?
    let countryOrRegion: String?
}

struct DeviceDetail: Codable, Sendable {
    let deviceId: String?
    let displayName: String?
    let operatingSystem: String?
    let browser: String?
    let isCompliant: Bool?
    let isManaged: Bool?
    let trustType: String?
}
