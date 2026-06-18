import SwiftUI
import RemoteActionsAddon

public struct RemoteActionsSettingsView: View {
    @State private var coordinator = RemoteActionsCoordinator.shared
    @State private var serverURLText = UserDefaults.standard.string(forKey: "aceso.remote.serverURL") ?? "http://localhost:8080"
    @State private var apiKeyText = UserDefaults.standard.string(forKey: "aceso.remote.apiKey") ?? "dev-api-key"

    public init() {}

    public var body: some View {
        Form {
            Section {
                Toggle("Allow remote actions from dashboard", isOn: Binding(
                    get: { coordinator.remoteActionsEnabled },
                    set: { enabled in
                        coordinator.remoteActionsEnabled = enabled
                        if enabled {
                            coordinator.reconnect()
                        } else {
                            coordinator.disconnect()
                        }
                    }
                ))
            } footer: {
                Text("When enabled, your self-hosted dashboard can trigger WHOOP haptics and alarms through this iPhone. Off by default.")
            }

            Section("Server") {
                TextField("Server URL", text: $serverURLText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("API key", text: $apiKeyText)
                Button("Save & reconnect") {
                    if let url = URL(string: serverURLText) {
                        coordinator.setServerURL(url)
                    }
                    UserDefaults.standard.set(apiKeyText, forKey: "aceso.remote.apiKey")
                    coordinator.setCommandSecret(apiKeyText)
                    coordinator.reconnect()
                }
            }

            Section("Status") {
                LabeledContent("WebSocket", value: coordinator.isConnected ? "Connected" : "Offline")
                if let error = coordinator.lastError {
                    Text(error).font(.caption).foregroundStyle(.orange)
                }
            }
        }
        .navigationTitle("Remote Actions")
    }
}
