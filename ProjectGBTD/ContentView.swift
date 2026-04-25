import SwiftUI

enum AppSection: Hashable {
    case signInLogs
    case settings
}

struct ContentView: View {
    @State private var selectedSection: AppSection? = .signInLogs

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedSection) {
                Label("Sign-in Logs", systemImage: "list.bullet.rectangle.portrait")
                    .tag(AppSection.signInLogs)
                Label("Settings", systemImage: "gear")
                    .tag(AppSection.settings)
            }
            .navigationTitle("GBTD Audit")
            .navigationSplitViewColumnWidth(min: 160, ideal: 180)
        } detail: {
            switch selectedSection {
            case .signInLogs:
                SignInLogsView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .settings:
                SettingsView()
            case nil:
                ContentUnavailableView("Select a Section", systemImage: "sidebar.left")
            }
        }
        .navigationSplitViewStyle(.prominentDetail)
    }
}

#Preview {
    ContentView()
}
