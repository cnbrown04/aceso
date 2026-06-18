import Foundation
import Observation
import UserNotifications
import WhoopSDK

@Observable
public final class RemoteActionsCoordinator: @unchecked Sendable {
    public static let shared = RemoteActionsCoordinator()

    public private(set) var isConnected = false
    public private(set) var lastError: String?

    private let executor = RemoteCommandExecutor()
    private var whoop: WhoopBLEClient?
    private var webSocket: URLSessionWebSocketTask?
    private var pingTask: Task<Void, Never>?
    private var receiveTask: Task<Void, Never>?
    private let session = URLSession(configuration: .default)

    private var serverURL: URL {
        let stored = UserDefaults.standard.string(forKey: Keys.serverURL)
        return URL(string: stored ?? "http://localhost:8080")!
    }

    private var commandSecret: String {
        UserDefaults.standard.string(forKey: Keys.commandSecret) ?? "dev-api-key"
    }

    public var remoteActionsEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.remoteActionsEnabled) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.remoteActionsEnabled) }
    }

    private init() {}

    public func activate(whoop: WhoopBLEClient) {
        self.whoop = whoop
        guard remoteActionsEnabled else { return }
        Task { await registerAndConnect(whoop: whoop) }
    }

    public func setServerURL(_ url: URL) {
        UserDefaults.standard.set(url.absoluteString, forKey: Keys.serverURL)
    }

    public func setCommandSecret(_ secret: String) {
        UserDefaults.standard.set(secret, forKey: Keys.commandSecret)
    }

    public func setDeviceToken(_ token: String) {
        UserDefaults.standard.set(token, forKey: Keys.deviceToken)
    }

    public func reconnect() {
        guard let whoop else { return }
        Task { await connectWebSocket() }
        _ = whoop
    }

    public func disconnect() {
        pingTask?.cancel()
        receiveTask?.cancel()
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        isConnected = false
    }

    private func registerAndConnect(whoop: WhoopBLEClient) async {
        if UserDefaults.standard.string(forKey: Keys.deviceToken) == nil {
            await registerDevice(whoop: whoop)
        }
        await requestNotificationPermission()
        await connectWebSocket()
    }

    private func registerDevice(whoop: WhoopBLEClient) async {
        let deviceID = UIDeviceBridge.identifier
        let body: [String: Any] = [
            "device_id": deviceID,
            "name": UIDeviceBridge.name,
            "platform": "ios",
            "whoop_device_id": whoop.deviceID ?? "",
            "apns_token": UserDefaults.standard.string(forKey: Keys.apnsToken) ?? "",
        ]
        guard let url = URL(string: "/api/devices/register", relativeTo: serverURL),
              let data = try? JSONSerialization.data(withJSONObject: body) else { return }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        do {
            let (respData, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return }
            if let json = try? JSONSerialization.jsonObject(with: respData) as? [String: Any],
               let token = json["device_token"] as? String {
                UserDefaults.standard.set(token, forKey: Keys.deviceToken)
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    private var apiKey: String {
        UserDefaults.standard.string(forKey: Keys.apiKey) ?? "dev-api-key"
    }

    private func connectWebSocket() async {
        guard let token = UserDefaults.standard.string(forKey: Keys.deviceToken) else { return }

        var components = URLComponents(url: serverURL, resolvingAgainstBaseURL: false)!
        components.scheme = serverURL.scheme == "https" ? "wss" : "ws"
        components.path = "/ws/device"

        var req = URLRequest(url: components.url!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        webSocket?.cancel()
        let task = session.webSocketTask(with: req)
        webSocket = task
        task.resume()
        isConnected = true
        lastError = nil

        pingTask?.cancel()
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                self?.webSocket?.sendPing { _ in }
            }
        }

        receiveTask?.cancel()
        receiveTask = Task { [weak self] in
            await self?.receiveLoop()
        }
    }

    private func receiveLoop() async {
        while !Task.isCancelled {
            guard let webSocket else { return }
            do {
                let message = try await webSocket.receive()
                switch message {
                case .string(let text):
                    await handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        await handleMessage(text)
                    }
                @unknown default:
                    break
                }
            } catch {
                isConnected = false
                lastError = error.localizedDescription
                try? await Task.sleep(for: .seconds(5))
                await connectWebSocket()
                return
            }
        }
    }

    @MainActor
    private func handleMessage(_ text: String) async {
        guard let data = text.data(using: .utf8),
              let envelope = try? JSONDecoder().decode(RemoteCommandEnvelope.self, from: data),
              let command = CommandEnvelopeVerifier.verify(envelope: envelope, secret: commandSecret),
              let whoop else { return }

        await postStatus(commandID: command.commandID, status: "executing", result: nil)

        let outcome = executor.execute(command, whoop: whoop, remoteActionsEnabled: remoteActionsEnabled)
        await postStatus(commandID: command.commandID, status: outcome.status, result: outcome.resultPayload)
        await showLocalNotification(for: command, outcome: outcome)
    }

    private func postStatus(commandID: String, status: String, result: [String: String]?) async {
        guard let token = UserDefaults.standard.string(forKey: Keys.deviceToken),
              let url = URL(string: "/api/commands/\(commandID)", relativeTo: serverURL) else { return }

        var body: [String: Any] = ["status": status]
        if let result { body["result"] = result }
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return }

        var req = URLRequest(url: url)
        req.httpMethod = "PATCH"
        req.httpBody = data
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        var alt = body
        alt["command_id"] = commandID
        if let wsData = try? JSONSerialization.data(withJSONObject: alt) {
            webSocket?.send(.string(String(data: wsData, encoding: .utf8)!)) { _ in }
        }

        _ = try? await session.data(for: req)
    }

    private func requestNotificationPermission() async {
        let center = UNUserNotificationCenter.current()
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
        await MainActor.run {
            UIApplicationBridge.registerForRemoteNotifications()
        }
    }

    @MainActor
    private func showLocalNotification(for command: RemoteCommand, outcome: CommandExecutionResult) async {
        let content = UNMutableNotificationContent()
        content.title = "Dashboard remote action"
        content.body = "Ran \(command.type): \(outcome.status)"
        let request = UNNotificationRequest(
            identifier: command.commandID,
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    public func storeAPNSToken(_ token: Data) {
        let hex = token.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(hex, forKey: Keys.apnsToken)
    }

    private enum Keys {
        static let serverURL = "aceso.remote.serverURL"
        static let apiKey = "aceso.remote.apiKey"
        static let deviceToken = "aceso.remote.deviceToken"
        static let commandSecret = "aceso.remote.commandSecret"
        static let remoteActionsEnabled = "aceso.remote.enabled"
        static let apnsToken = "aceso.remote.apnsToken"
    }
}
