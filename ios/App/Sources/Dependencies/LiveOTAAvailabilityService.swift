import Foundation
import MauryaOTA
import Observation

@MainActor
@Observable
final class LiveOTAAvailabilityService: OTAAvailabilityService {
    typealias ContextProvider = @MainActor () -> DeviceOTAContext?

    private(set) var preflight: OTAPreflightState = .checking
    private(set) var workflowSnapshot = OTAWorkflowSnapshot(
        stage: .idle,
        confirmedBytes: 0,
        totalBytes: 0,
        installedVersion: nil,
        targetVersion: nil
    )
    private(set) var errorMessage: String?
    private let environment: [String: String]
    private let contextProvider: ContextProvider
    private var activeWorkflow: OTAWorkflow?

    var canStart: Bool {
        preflight == .ready && contextProvider() != nil && isTerminalOrIdle(workflowSnapshot.stage)
    }

    init(
        environment: [String: String]? = nil,
        contextProvider: @escaping ContextProvider = { nil }
    ) {
        self.contextProvider = contextProvider
        if let environment {
            self.environment = environment
        } else {
            let configuredPublicKey =
                Bundle.main.object(forInfoDictionaryKey: "MauryaOTAProductionPublicKey") as? String ?? ""
            self.environment = [
                "baseURL": Bundle.main.object(forInfoDictionaryKey: "MauryaOTABaseURL") as? String ?? "",
                "publicKey": configuredPublicKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? Self.bundledPublicKey()
                    : configuredPublicKey,
                "keyID": Bundle.main.object(forInfoDictionaryKey: "MauryaOTAProductionKeyID") as? String ?? "production-1",
                "allowedHosts": Bundle.main.object(forInfoDictionaryKey: "MauryaOTAAllowedHosts") as? String ?? "",
                "appVersion": Bundle.main.object(forInfoDictionaryKey: "MauryaOTAClientVersion") as? String ?? "",
            ]
        }
        refresh()
    }

    func refresh() {
        var blockers: [String] = []
        if let baseURL = validBaseURL() {
            if allowedHosts(baseURL: baseURL).isEmpty { blockers.append("ota.preflight.network") }
        } else {
            blockers.append("ota.preflight.network")
        }
        if decodedPublicKey() == nil { blockers.append("ota.preflight.production-key") }
        if (environment["keyID"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            blockers.append("ota.preflight.production-key")
        }
        preflight = blockers.isEmpty ? .ready : .unavailable(blockers)
    }

    func start() async {
        refresh()
        guard preflight == .ready,
            let context = contextProvider(),
            let baseURL = validBaseURL(),
            let publicKey = decodedPublicKey()
        else {
            errorMessage = "ota.start.device-disabled"
            return
        }
        do {
            let keyID = environment["keyID"] ?? "production-1"
            let hosts = allowedHosts(baseURL: baseURL)
            let configuration = URLSessionConfiguration.ephemeral
            configuration.urlCache = nil
            configuration.httpCookieStorage = nil
            configuration.httpShouldSetCookies = false
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            let network = try URLSessionOTAClient(
                baseURL: baseURL,
                allowedHosts: hosts,
                keyID: keyID,
                session: URLSession(configuration: configuration)
            )
            let checkpointDirectory = URL.applicationSupportDirectory
                .appending(path: "Maurya/OTA", directoryHint: .isDirectory)
            let workflow = OTAWorkflow(
                transport: context.transport,
                network: network,
                signatureVerifier: MauryaManifestVerifier(publicKeys: [keyID: publicKey]),
                checkpointStore: FileOTACheckpointStore(directory: checkpointDirectory),
                appVersion: appVersion(),
                allowedArtifactHosts: hosts
            )
            activeWorkflow = workflow
            errorMessage = nil
            let updates = AsyncStream.makeStream(
                of: OTAWorkflowSnapshot.self,
                bufferingPolicy: .bufferingNewest(32)
            )
            let consumer = Task { @MainActor in
                for await snapshot in updates.stream { self.workflowSnapshot = snapshot }
            }
            do {
                let final = try await workflow.run(
                    deviceID: context.deviceID,
                    unitID: context.unitID,
                    observer: { updates.continuation.yield($0) }
                )
                updates.continuation.finish()
                await consumer.value
                workflowSnapshot = final
            } catch {
                updates.continuation.finish()
                await consumer.value
                errorMessage = Self.describe(error)
            }
            activeWorkflow = nil
        } catch is CancellationError {
            await activeWorkflow?.cancel()
            activeWorkflow = nil
        } catch {
            errorMessage = Self.describe(error)
            activeWorkflow = nil
        }
    }

    func cancel() async {
        await activeWorkflow?.cancel()
        activeWorkflow = nil
    }

    private func validBaseURL() -> URL? {
        guard let url = URL(string: environment["baseURL"] ?? ""),
            url.scheme?.lowercased() == "https",
            let host = url.host?.lowercased(),
            host.hasSuffix(".invalid") == false,
            url.user == nil,
            url.password == nil
        else { return nil }
        return url
    }

    private func decodedPublicKey() -> Data? {
        let text = (environment["publicKey"] ?? "")
            .replacingOccurrences(of: "-----BEGIN PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "-----END PUBLIC KEY-----", with: "")
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
        return Data(base64Encoded: text).flatMap { $0.isEmpty ? nil : $0 }
    }

    private func allowedHosts(baseURL: URL) -> Set<String> {
        var result = Set(
            (environment["allowedHosts"] ?? "").split(separator: ",").map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            }.filter { $0.isEmpty == false })
        if let host = baseURL.host?.lowercased() { result.insert(host) }
        return result
    }

    private func appVersion() -> Int {
        if let configured = Int(environment["appVersion"] ?? ""), configured > 0 {
            return configured
        }
        return Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1") ?? 1
    }

    private static func bundledPublicKey() -> String {
        guard let URL = Bundle.main.url(forResource: "MauryaOTAPublicKey", withExtension: "pem"),
            let text = try? String(contentsOf: URL, encoding: .utf8)
        else { return "" }
        return text
    }

    private func isTerminalOrIdle(_ stage: OTAWorkflowStage) -> Bool {
        [.idle, .cancelled, .failed, .succeeded, .upToDate].contains(stage)
    }

    private static func describe(_ error: any Error) -> String {
        String(describing: error)
    }
}
