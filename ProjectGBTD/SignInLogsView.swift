import SwiftUI

struct SignInLogsView: View {
    @ObservedObject private var apiService = GraphAPIService.shared
    @ObservedObject private var authManager = AuthManager.shared

    @State private var selectedLog: SignInLog?
    @State private var selection: Set<String> = []
    @State private var showFilters = false
    @State private var filter = SignInFilter()

    var body: some View {
        VSplitView {
            // Top: log list
            VStack(spacing: 0) {
                if showFilters {
                    FilterBar(filter: $filter) {
                        Task { await apiService.fetchSignInLogs(filter: filter) }
                    }
                    Divider()
                }

                if apiService.signInLogs.isEmpty && !apiService.isLoading {
                    emptyState
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    logTable
                }

                if apiService.isLoading {
                    HStack {
                        ProgressView()
                        Text("Fetching sign-in logs…").font(.caption).foregroundColor(.secondary)
                    }
                    .padding(8)
                }

                if let error = apiService.errorMessage {
                    errorBanner(error)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 200, maxHeight: .infinity)

            // Bottom: detail pane
            Group {
                if let log = selectedLog {
                    SignInDetailView(log: log)
                } else {
                    ContentUnavailableView {
                        Label("No Event Selected", systemImage: "person.crop.rectangle")
                    } description: {
                        Text("Select a sign-in event from the list to view details.")
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 150, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Sign-in Logs")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Toggle(isOn: $showFilters) {
                    Label("Filters", systemImage: "line.3.horizontal.decrease.circle")
                }
                .toggleStyle(.button)
                .help("Show/hide filter bar")

                Button {
                    Task { await apiService.fetchSignInLogs(filter: filter) }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(apiService.isLoading || !authManager.isAuthenticated)
                .keyboardShortcut("r", modifiers: .command)
                .help("Refresh sign-in logs (⌘R)")
            }
        }
        .onChange(of: selection) { _, ids in
            selectedLog = apiService.signInLogs.first { ids.contains($0.id) }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if !authManager.isAuthenticated {
            ContentUnavailableView {
                Label("Sign In Required", systemImage: "person.badge.key")
            } description: {
                Text("Go to Settings and sign in with your Microsoft account to fetch audit logs.")
            }
        } else {
            ContentUnavailableView {
                Label("No Sign-in Logs", systemImage: "doc.text.magnifyingglass")
            } description: {
                Text("Press Refresh to load sign-in logs from Microsoft Graph.")
            } actions: {
                Button("Refresh Now") {
                    Task { await apiService.fetchSignInLogs(filter: filter) }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    @ViewBuilder
    private var logTable: some View {
        Table(apiService.signInLogs, selection: $selection) {
            TableColumn("Date") { log in
                Text(log.formattedDate).font(.caption).monospacedDigit()
            }
            .width(min: 130, ideal: 150)

            TableColumn("User") { log in
                Text(log.userPrincipalName ?? log.userDisplayName ?? "—")
                    .lineLimit(1).truncationMode(.middle)
            }
            .width(min: 140, ideal: 200)

            TableColumn("Application") { log in
                Text(log.appDisplayName ?? "—").lineLimit(1)
            }
            .width(min: 100, ideal: 160)

            TableColumn("IP Address") { log in
                Text(log.ipAddress ?? "—").font(.caption.monospaced())
            }
            .width(min: 90, ideal: 115)

            TableColumn("Location") { log in
                Text(log.locationString).lineLimit(1)
            }
            .width(min: 100, ideal: 160)

            TableColumn("Client") { log in
                Text(log.clientAppUsed ?? "—").lineLimit(1)
            }
            .width(min: 80, ideal: 120)

            TableColumn("Status") { log in
                HStack(spacing: 4) {
                    Image(systemName: log.isSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(log.isSuccess ? .green : .red)
                        .font(.caption)
                    Text(log.isSuccess ? "Success" : "Failure").font(.caption)
                }
            }
            .width(min: 70, ideal: 90)

            TableColumn("Risk") { log in
                Text(log.riskLevelAggregated ?? "none")
                    .font(.caption)
                    .foregroundColor(riskColor(for: log.riskLevelAggregated))
            }
            .width(min: 50, ideal: 70)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .layoutPriority(1)

        if apiService.hasNextPage {
            Button("Load More Logs") {
                Task { await apiService.fetchNextPage() }
            }
            .disabled(apiService.isLoading)
            .padding(8)
            .frame(maxWidth: .infinity)
            .background(Color(NSColor.controlBackgroundColor))
        }
    }

    @ViewBuilder
    private func errorBanner(_ message: String) -> some View {
        Divider()
        HStack {
            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
            Text(message).font(.caption).foregroundColor(.primary)
            Spacer()
            Button("Dismiss") { apiService.errorMessage = nil }.font(.caption)
        }
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private func riskColor(for level: String?) -> Color {
        switch level?.lowercased() {
        case "high": return .red
        case "medium": return .orange
        case "low": return .yellow
        default: return .secondary
        }
    }
}

// MARK: - Filter Bar

struct FilterBar: View {
    @Binding var filter: SignInFilter
    let onApply: () -> Void

    private var startDateBinding: Binding<Date> {
        Binding(
            get: { filter.startDate ?? Date(timeIntervalSinceNow: -7 * 24 * 3600) },
            set: { filter.startDate = $0 }
        )
    }

    private var endDateBinding: Binding<Date> {
        Binding(
            get: { filter.endDate ?? Date() },
            set: { filter.endDate = $0 }
        )
    }

    var body: some View {
        HStack(spacing: 12) {
            DatePicker("From:", selection: startDateBinding, displayedComponents: .date)
                .labelsHidden()
                .overlay(alignment: .leading) {
                    Text("From:").font(.caption).foregroundColor(.secondary)
                        .offset(x: -36)
                }
                .padding(.leading, 36)

            DatePicker("To:", selection: endDateBinding, displayedComponents: .date)
                .labelsHidden()
                .overlay(alignment: .leading) {
                    Text("To:").font(.caption).foregroundColor(.secondary)
                        .offset(x: -20)
                }
                .padding(.leading, 20)

            TextField("User UPN filter…", text: $filter.userPrincipalName)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 160)

            Picker("Status", selection: $filter.statusFilter) {
                ForEach(SignInFilter.StatusFilter.allCases, id: \.self) {
                    Text($0.rawValue).tag($0)
                }
            }
            .labelsHidden()
            .frame(width: 100)

            Stepper("Top \(filter.topCount)", value: $filter.topCount, in: 10...999, step: 10)

            Button("Apply", action: onApply)
                .buttonStyle(.borderedProminent)

            Button("Reset") {
                filter = SignInFilter()
                onApply()
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}
