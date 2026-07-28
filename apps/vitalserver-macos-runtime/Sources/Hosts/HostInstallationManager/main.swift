import Application
import Contracts
import Domain
import Foundation
import OutboundAdapters
import Workflow

private enum HostInstallationManagerCLIError: Error, CustomStringConvertible {
    case invalidArguments(String)
    case documentUnavailable(path: String, reason: String)
    case operationUnavailable(String)

    var description: String {
        switch self {
        case .invalidArguments(let reason):
            return "invalid arguments: \(reason)"
        case .documentUnavailable(let path, let reason):
            return "document unavailable path=\(path) reason=\(reason)"
        case .operationUnavailable(let reason):
            return "owner operation unavailable: \(reason)"
        }
    }
}

private struct HostInstallationManagerArguments {
    let command: String
    let values: [String: String]

    init(_ arguments: [String]) throws {
        guard let command = arguments.first else {
            throw HostInstallationManagerCLIError.invalidArguments(
                "command is required"
            )
        }
        var values: [String: String] = [:]
        var index = 1
        while index < arguments.count {
            let key = arguments[index]
            guard key.hasPrefix("--"), index + 1 < arguments.count else {
                throw HostInstallationManagerCLIError.invalidArguments(
                    "expected --key value at index \(index)"
                )
            }
            guard values[key] == nil else {
                throw HostInstallationManagerCLIError.invalidArguments(
                    "duplicate argument \(key)"
                )
            }
            values[key] = arguments[index + 1]
            index += 2
        }
        self.command = command
        self.values = values
    }

    func required(_ key: String) throws -> String {
        guard let value = values[key], !value.isEmpty else {
            throw HostInstallationManagerCLIError.invalidArguments(
                "\(key) is required"
            )
        }
        return value
    }

    func requireExactly(_ keys: Set<String>) throws {
        guard Set(values.keys) == keys else {
            throw HostInstallationManagerCLIError.invalidArguments(
                "expected=\(keys.sorted()) actual=\(values.keys.sorted())"
            )
        }
    }
}

private enum HostInstallationManagerDocuments {
    static func read<T: Decodable>(
        _ type: T.Type,
        path: String
    ) throws -> T {
        do {
            return try JSONDecoder().decode(
                type,
                from: Data(contentsOf: URL(fileURLWithPath: path))
            )
        } catch {
            throw HostInstallationManagerCLIError.documentUnavailable(
                path: path,
                reason: String(describing: error)
            )
        }
    }

    static func write<T: Encodable>(
        _ document: T,
        path: String
    ) throws {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(document).write(to: url, options: [.atomic])
    }
}

private enum HostInstallationManagerRepositoryFactory {
    static func make(databasePath: String) -> SQLiteHostPlatformInstallationRepository {
        SQLiteHostPlatformInstallationRepository(
            databaseURL: URL(fileURLWithPath: databasePath),
            validateManifest: HostPlatformInstallationPolicy.validate,
            validateOperation: HostPlatformInstallationPolicy.validate,
            validateTransition:
                HostPlatformInstallationPolicy.validatePersistenceTransition
        )
    }
}

private enum HostInstallationManagerCommands {
    static func initialize(
        _ arguments: HostInstallationManagerArguments
    ) throws {
        let required: Set<String> = ["--manifest", "--database"]
        try arguments.requireExactly(required)
        let manifest: HostPlatformInstallationManifest =
            try HostInstallationManagerDocuments.read(
                HostPlatformInstallationManifest.self,
                path: arguments.required("--manifest")
            )
        try HostPlatformInstallationPolicy.validate(manifest)
        let repository = HostInstallationManagerRepositoryFactory.make(
            databasePath: try arguments.required("--database")
        )
        try repository.initializeInstallation(manifest)
    }

    static func execute(
        _ arguments: HostInstallationManagerArguments
    ) throws {
        let required: Set<String> = [
            "--request",
            "--operation",
            "--database",
            "--installation-root",
            "--launchctl",
        ]
        try arguments.requireExactly(required)
        let requestPath = try arguments.required("--request")
        let requestData: Data
        do {
            requestData = try Data(
                contentsOf: URL(fileURLWithPath: requestPath)
            )
            try validateCommandDocument(requestData)
        } catch {
            throw HostInstallationManagerCLIError.documentUnavailable(
                path: requestPath,
                reason: String(describing: error)
            )
        }
        let command: HostPlatformInstallationCommand
        do {
            command = try JSONDecoder().decode(
                HostPlatformInstallationCommand.self,
                from: requestData
            )
        } catch {
            throw HostInstallationManagerCLIError.documentUnavailable(
                path: requestPath,
                reason: "decode failed: \(error)"
            )
        }
        let repository = HostInstallationManagerRepositoryFactory.make(
            databasePath: try arguments.required("--database")
        )
        let installationRoot = URL(
            fileURLWithPath: try arguments.required("--installation-root"),
            isDirectory: true
        )
        let workflow = ManageHostPlatformInstallationWorkflow(
            repository: repository,
            candidateStager: HostPlatformReleaseArchiveCandidateStager(
                installationRoot: installationRoot
            ),
            serviceReconciler: MacOSHostPlatformReleaseServiceReconciler(
                installationRoot: installationRoot,
                launchctlURL: URL(
                    fileURLWithPath: try arguments.required("--launchctl")
                )
            ),
            failureObservedAt: currentTimestamp
        )
        do {
            let operation = try workflow.execute(command: command)
            try HostInstallationManagerDocuments.write(
                operation,
                path: arguments.required("--operation")
            )
        } catch {
            switch repository.loadOperation(id: command.operationId) {
            case .loaded(let operation) where operation.state == .failed:
                try HostInstallationManagerDocuments.write(
                    operation,
                    path: arguments.required("--operation")
                )
            case .loaded(let operation):
                throw HostInstallationManagerCLIError.operationUnavailable(
                    "state=\(operation.state.rawValue) reason=\(error)"
                )
            case .missing:
                throw HostInstallationManagerCLIError.operationUnavailable(
                    "operation missing reason=\(error)"
                )
            case .failed(let reason):
                throw HostInstallationManagerCLIError.operationUnavailable(
                    "operation read failed reason=\(reason) execution=\(error)"
                )
            }
            throw error
        }
    }

    private static func validateCommandDocument(_ data: Data) throws {
        guard
            let root = try JSONSerialization.jsonObject(with: data)
                as? [String: Any],
            let release = root["targetRelease"] as? [String: Any]
        else {
            throw HostInstallationManagerCLIError.invalidArguments(
                "manager request must be an object with targetRelease"
            )
        }
        let expected: Set<String> = [
            "operationId", "kind", "installationId",
            "expectedInstallationRevision", "targetRelease",
            "sourceArtifactPath", "sourceArtifactSizeBytes",
            "sourceArtifactMediaType", "stagingAttemptId", "requestedAt",
        ]
        let releaseExpected: Set<String> = [
            "id", "version", "sha256", "slotRelativePath",
        ]
        guard Set(root.keys) == expected,
            Set(release.keys) == releaseExpected
        else {
            throw HostInstallationManagerCLIError.invalidArguments(
                "manager request fields differ from contract"
            )
        }
    }

}

private func currentTimestamp() -> String {
    ISO8601DateFormatter().string(from: Date())
}

@main
private enum HostInstallationManagerMain {
    static func main() {
        do {
            let arguments = try HostInstallationManagerArguments(
                Array(CommandLine.arguments.dropFirst())
            )
            switch arguments.command {
            case "initialize":
                try HostInstallationManagerCommands.initialize(arguments)
            case "execute":
                try HostInstallationManagerCommands.execute(arguments)
            default:
                throw HostInstallationManagerCLIError.invalidArguments(
                    "unsupported command \(arguments.command)"
                )
            }
        } catch {
            FileHandle.standardError.write(
                Data("host installation manager failed: \(error)\n".utf8)
            )
            Foundation.exit(EXIT_FAILURE)
        }
    }
}
