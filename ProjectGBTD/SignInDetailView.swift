import SwiftUI

struct SignInDetailView: View {
    let log: SignInLog

    var body: some View {
        ScrollView {
            Form {
                Section("Sign-in") {
                    DetailRow("Date & Time", log.formattedDate)
                    DetailRow("User", log.userDisplayName ?? "—")
                    DetailRow("UPN", log.userPrincipalName ?? "—", copyable: true)
                    DetailRow("User ID", log.userId ?? "—")
                    LabeledContent("Status") {
                        HStack(spacing: 6) {
                            Image(systemName: log.isSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(log.isSuccess ? .green : .red)
                            Text(log.isSuccess ? "Success" : "Failure")
                        }
                    }
                    if let code = log.status?.errorCode, code != 0 {
                        DetailRow("Error Code", String(code))
                    }
                    if let reason = log.status?.failureReason {
                        DetailRow("Failure Reason", reason)
                    }
                    if let extra = log.status?.additionalDetails {
                        DetailRow("Additional Details", extra)
                    }
                }

                Section("Application") {
                    DetailRow("App Name", log.appDisplayName ?? "—")
                    DetailRow("App ID", log.appId ?? "—", copyable: true)
                    DetailRow("Resource", log.resourceDisplayName ?? "—")
                    DetailRow("Resource ID", log.resourceId ?? "—")
                    DetailRow("Client App", log.clientAppUsed ?? "—")
                    DetailRow("Interactive", log.isInteractive.map { $0 ? "Yes" : "No" } ?? "—")
                    DetailRow("Conditional Access", log.conditionalAccessStatus ?? "—")
                }

                Section("Network & Location") {
                    DetailRow("IP Address", log.ipAddress ?? "—", copyable: true)
                    DetailRow("City", log.location?.city ?? "—")
                    DetailRow("State / Region", log.location?.state ?? "—")
                    DetailRow("Country", log.location?.countryOrRegion ?? "—")
                }

                Section("Device") {
                    DetailRow("Device Name", log.deviceDetail?.displayName ?? "—")
                    DetailRow("Device ID", log.deviceDetail?.deviceId ?? "—")
                    DetailRow("OS", log.deviceDetail?.operatingSystem ?? "—")
                    DetailRow("Browser", log.deviceDetail?.browser ?? "—")
                    DetailRow("Compliant", log.deviceDetail?.isCompliant.map { $0 ? "Yes" : "No" } ?? "—")
                    DetailRow("Managed", log.deviceDetail?.isManaged.map { $0 ? "Yes" : "No" } ?? "—")
                    DetailRow("Trust Type", log.deviceDetail?.trustType ?? "—")
                }

                Section("Risk") {
                    LabeledContent("Risk Level") { riskBadge(log.riskLevelAggregated) }
                    DetailRow("Risk During Sign-in", log.riskLevelDuringSignIn ?? "none")
                    DetailRow("Risk State", log.riskState ?? "—")
                    DetailRow("Risk Detail", log.riskDetail ?? "—")
                }

                Section("Identifiers") {
                    DetailRow("Sign-in ID", log.id, copyable: true)
                }
            }
            .formStyle(.grouped)
        }
        .navigationTitle("Event Detail")
    }

    @ViewBuilder
    private func riskBadge(_ level: String?) -> some View {
        let color: Color = {
            switch level?.lowercased() {
            case "high": return .red
            case "medium": return .orange
            case "low": return .yellow
            default: return .secondary
            }
        }()
        Text(level ?? "none")
            .font(.caption.bold())
            .foregroundColor(color)
    }
}

private struct DetailRow: View {
    let label: String
    let value: String
    var copyable: Bool = false

    init(_ label: String, _ value: String, copyable: Bool = false) {
        self.label = label
        self.value = value
        self.copyable = copyable
    }

    var body: some View {
        LabeledContent(label) {
            HStack(spacing: 6) {
                Text(value)
                    .textSelection(.enabled)
                    .foregroundColor(value == "—" ? .secondary : .primary)
                if copyable && value != "—" {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(value, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .help("Copy to clipboard")
                }
            }
        }
    }
}
