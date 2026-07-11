import Application
import CryptoKit
import Foundation
import RuntimeControl

public enum RuntimeControlAPIAutomationCredentialsError: Error, CustomStringConvertible {
    case tokenMissing(path: String)
    case tokenPathInvalid(path: String, state: String)
    case tokenReadFailed(path: String, reason: String)
    case tokenInvalid(path: String)
    case tokenDirectoryCreateFailed(path: String, reason: String)
    case tokenWriteFailed(path: String, reason: String)
    case endpointReadFailed(path: String, reason: String)
    case endpointInvalidPort(path: String, port: Int)

    public var description: String {
        switch self {
        case .tokenMissing(let path):
            "runtime control API automation token is missing path=\(path)"
        case .tokenPathInvalid(let path, let state):
            "runtime control API automation token path is invalid path=\(path) state=\(state)"
        case .tokenReadFailed(let path, let reason):
            "runtime control API automation token read failed path=\(path) reason=\(reason)"
        case .tokenInvalid(let path):
            "runtime control API automation token is invalid path=\(path)"
        case .tokenDirectoryCreateFailed(let path, let reason):
            "runtime control API automation token directory create failed path=\(path) reason=\(reason)"
        case .tokenWriteFailed(let path, let reason):
            "runtime control API automation token write failed path=\(path) reason=\(reason)"
        case .endpointReadFailed(let path, let reason):
            "runtime control API endpoint settings read failed path=\(path) reason=\(reason)"
        case .endpointInvalidPort(let path, let port):
            "runtime control API endpoint port is invalid path=\(path) port=\(port)"
        }
    }
}

public struct RuntimeControlAPIAutomationTokenStore {
    private let tokenURL: URL
    private let fileStore: RuntimeFileStore

    public init(
        tokenURL: URL = InstalledRuntimePaths.defaultInstalled.runtimeControlAPIToken,
        fileStore: RuntimeFileStore = SystemRuntimeFileStore()
    ) {
        self.tokenURL = tokenURL
        self.fileStore = fileStore
    }

    public func load() throws -> String {
        switch fileStore.pathState(at: tokenURL) {
        case .file:
            break
        case .missing:
            throw RuntimeControlAPIAutomationCredentialsError.tokenMissing(path: tokenURL.path)
        case .directory, .other, .unknown, .inspectFailed:
            throw RuntimeControlAPIAutomationCredentialsError.tokenPathInvalid(
                path: tokenURL.path,
                state: fileStore.pathState(at: tokenURL).rawValue
            )
        }
        let raw: String
        do {
            raw = try fileStore.readUTF8Text(tokenURL)
        } catch {
            throw RuntimeControlAPIAutomationCredentialsError.tokenReadFailed(
                path: tokenURL.path,
                reason: error.localizedDescription
            )
        }
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty, token == raw.trimmingCharacters(in: .newlines) else {
            throw RuntimeControlAPIAutomationCredentialsError.tokenInvalid(path: tokenURL.path)
        }
        return token
    }

    public func loadOrCreate() throws -> String {
        switch fileStore.pathState(at: tokenURL) {
        case .file:
            return try load()
        case .missing:
            break
        case .directory, .other, .unknown, .inspectFailed:
            throw RuntimeControlAPIAutomationCredentialsError.tokenPathInvalid(
                path: tokenURL.path,
                state: fileStore.pathState(at: tokenURL).rawValue
            )
        }

        let directory = tokenURL.deletingLastPathComponent()
        do {
            try fileStore.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw RuntimeControlAPIAutomationCredentialsError.tokenDirectoryCreateFailed(
                path: directory.path,
                reason: error.localizedDescription
            )
        }

        let token = Self.generatedToken()
        do {
            try fileStore.writeData(
                Data(token.utf8),
                to: tokenURL,
                options: .atomic,
                posixPermissions: 0o600
            )
        } catch {
            throw RuntimeControlAPIAutomationCredentialsError.tokenWriteFailed(
                path: tokenURL.path,
                reason: error.localizedDescription
            )
        }
        return try load()
    }

    private static func generatedToken() -> String {
        let key = SymmetricKey(size: .bits256)
        let encoded = key.withUnsafeBytes { Data($0).base64EncodedString() }
        return encoded
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

public struct RuntimeControlAPIAutomationEndpoint {
    private let settingsURL: URL
    private let fileStore: RuntimeFileReading

    public init(
        settingsURL: URL = InstalledRuntimePaths.defaultInstalled.runtimeControlSettings,
        fileStore: RuntimeFileReading = SystemRuntimeFileStore()
    ) {
        self.settingsURL = settingsURL
        self.fileStore = fileStore
    }

    public func baseURL() throws -> String {
        let port: Int
        switch RuntimeControlSettingsDocument.loadResult(path: settingsURL.path, fileStore: fileStore) {
        case .missing:
            port = RuntimeSettingsInitialValues.runtimeControlPort
        case .loaded(let settings):
            port = settings.runtimeControlPort
        case .failed(let reason):
            throw RuntimeControlAPIAutomationCredentialsError.endpointReadFailed(
                path: settingsURL.path,
                reason: reason
            )
        }
        guard RuntimeSettingsReadPolicy.validRuntimeControlPort(port) else {
            throw RuntimeControlAPIAutomationCredentialsError.endpointInvalidPort(
                path: settingsURL.path,
                port: port
            )
        }
        return RuntimeControlLocalAPIConnectionDefaults.baseURL(runtimeControlPort: port)
    }
}

public struct RuntimeControlAPIAutomationCredentials {
    public let baseURL: String
    public let token: String

    public init(
        baseURL: String? = nil,
        token: String? = nil,
        endpoint: RuntimeControlAPIAutomationEndpoint = RuntimeControlAPIAutomationEndpoint(),
        tokenStore: RuntimeControlAPIAutomationTokenStore = RuntimeControlAPIAutomationTokenStore()
    ) throws {
        if let baseURL {
            self.baseURL = baseURL
        } else {
            self.baseURL = try endpoint.baseURL()
        }
        if let token {
            self.token = token
        } else {
            self.token = try tokenStore.load()
        }
    }
}
