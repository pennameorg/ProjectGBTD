import SwiftUI

struct SettingsView: View {
    @ObservedObject private var authManager = AuthManager.shared
    @State private var clientId = ""
    @State private var tenantId = ""
    @State private var showSignOutAlert = false

    var body: some View {
        Form {
            Section("Configuration") {
                LabeledContent("Tenant ID") {
                    TextField("Required", text: $tenantId)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 340)
                }
                LabeledContent("Client ID") {
                    TextField("Required", text: $clientId)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 340)
                }
            }

            Section("Authentication") {
                if authManager.isAuthenticated {
                    HStack {
                        Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                        Text("Signed in")
                        Spacer()
                        Button("Sign Out", role: .destructive) { showSignOutAlert = true }
                            .buttonStyle(.bordered)
                    }
                } else {
                    HStack(spacing: 12) {
                        Button("Sign In with Microsoft") {
                            saveConfiguration()
                            Task { await authManager.signIn() }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(clientId.isEmpty || tenantId.isEmpty || authManager.isLoading)
                        if authManager.isLoading { ProgressView().scaleEffect(0.8) }
                    }
                }
                if let error = authManager.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                        .font(.caption)
                }
            }

        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .onAppear {
            clientId = authManager.clientId
            tenantId = authManager.tenantId
        }
        .onChange(of: clientId) { _, _ in saveConfiguration() }
        .onChange(of: tenantId) { _, _ in saveConfiguration() }
        .alert("Sign Out", isPresented: $showSignOutAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Sign Out", role: .destructive) { authManager.signOut() }
        } message: {
            Text("Your authentication tokens will be removed from the Keychain.")
        }
    }

    private func saveConfiguration() {
        authManager.clientId = clientId
        authManager.tenantId = tenantId
    }
}
