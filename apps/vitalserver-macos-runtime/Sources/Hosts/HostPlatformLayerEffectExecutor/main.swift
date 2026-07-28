import Contracts
import CryptoKit
import Domain
import Foundation

private enum HostPlatformLayerEffectExecutorError:
    Error,
    CustomStringConvertible
{
    case invalidArguments(String)
    case correlatedInputInvalid(String)
    case inputUnavailable(path: String, reason: String)
    case inputDigestMismatch(path: String, expected: String, actual: String)
    case managerUnavailable(String)
    case ownerOperationUnavailable(String)
    case existingOutput(String)

    var receiptState: ProductUpdateLayerEffectState {
        switch self {
        case .inputUnavailable, .managerUnavailable:
            return .unavailable
        case .invalidArguments, .correlatedInputInvalid, .inputDigestMismatch,
            .ownerOperationUnavailable, .existingOutput:
            return .failed
        }
    }

    var issueCode: String {
        switch self {
        case .invalidArguments:
            return "host-platform-effect-arguments-invalid"
        case .correlatedInputInvalid:
            return "host-platform-effect-input-invalid"
        case .inputUnavailable:
            return "host-platform-effect-input-unavailable"
        case .inputDigestMismatch:
            return "host-platform-effect-input-digest-invalid"
        case .managerUnavailable:
            return "host-installation-manager-unavailable"
        case .ownerOperationUnavailable:
            return "host-platform-owner-operation-invalid"
        case .existingOutput:
            return "host-platform-effect-output-conflict"
        }
    }

    var retryable: Bool {
        switch self {
        case .inputUnavailable, .managerUnavailable:
            return true
        case .invalidArguments, .correlatedInputInvalid, .inputDigestMismatch,
            .ownerOperationUnavailable, .existingOutput:
            return false
        }
    }

    var dependency: String {
        switch self {
        case .inputUnavailable:
            return "host-filesystem"
        case .managerUnavailable, .ownerOperationUnavailable:
            return "host-installation-manager"
        case .invalidArguments, .correlatedInputInvalid, .inputDigestMismatch:
            return "product-update-bundle"
        case .existingOutput:
            return "layer-effect-receipt-store"
        }
    }

    var description: String {
        switch self {
        case .invalidArguments(let reason):
            return "invalid arguments: \(reason)"
        case .correlatedInputInvalid(let reason):
            return "correlated input invalid: \(reason)"
        case .inputUnavailable(let path, let reason):
            return "input unavailable path=\(path) reason=\(reason)"
        case .inputDigestMismatch(let path, let expected, let actual):
            return
                "input digest mismatch path=\(path) expected=\(expected) actual=\(actual)"
        case .managerUnavailable(let reason):
            return "host installation manager unavailable: \(reason)"
        case .ownerOperationUnavailable(let reason):
            return "owner operation unavailable: \(reason)"
        case .existingOutput(let path):
            return "output already exists path=\(path)"
        }
    }
}

struct HostPlatformLayerEffectExecutorArguments {
    let requestPath: String
    let receiptPath: String

    init(_ arguments: [String]) throws {
        guard arguments.count == 5,
            arguments[0] == "execute",
            arguments[1] == "--request",
            arguments[3] == "--receipt",
            !arguments[2].isEmpty,
            !arguments[4].isEmpty
        else {
            throw HostPlatformLayerEffectExecutorError.invalidArguments(
                "expected execute --request <request.json> --receipt <receipt.json>"
            )
        }
        requestPath = arguments[2]
        receiptPath = arguments[4]
    }
}

enum HostPlatformLayerEffectDocuments {
    static let maximumDocumentBytes = 1_048_576

    static func readData(path: String) throws -> Data {
        let url = URL(fileURLWithPath: path)
        do {
            let attributes = try FileManager.default.attributesOfItem(
                atPath: path
            )
            guard let size = attributes[.size] as? NSNumber,
                size.uint64Value <= maximumDocumentBytes
            else {
                throw HostPlatformLayerEffectExecutorError.inputUnavailable(
                    path: path,
                    reason: "document exceeds \(maximumDocumentBytes) bytes"
                )
            }
            return try Data(contentsOf: url)
        } catch let error as HostPlatformLayerEffectExecutorError {
            throw error
        } catch {
            throw HostPlatformLayerEffectExecutorError.inputUnavailable(
                path: path,
                reason: String(describing: error)
            )
        }
    }

    static func decode<T: Decodable>(
        _ type: T.Type,
        data: Data,
        path: String
    ) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw HostPlatformLayerEffectExecutorError.inputUnavailable(
                path: path,
                reason: "decode failed: \(error)"
            )
        }
    }

    static func write<T: Encodable>(
        _ document: T,
        path: String
    ) throws {
        let url = URL(fileURLWithPath: path)
        guard !FileManager.default.fileExists(atPath: path) else {
            throw HostPlatformLayerEffectExecutorError.existingOutput(path)
        }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(document).write(to: url, options: [.atomic])
    }
}

enum HostPlatformLayerEffectExecutor {
    static func execute(
        arguments: HostPlatformLayerEffectExecutorArguments
    ) throws {
        let invocationData = try HostPlatformLayerEffectDocuments.readData(
            path: arguments.requestPath
        )
        let invocation = try HostPlatformLayerEffectDocuments.decode(
            ProductUpdateLayerEffectInvocation.self,
            data: invocationData,
            path: arguments.requestPath
        )
        do {
            try executeCorrelated(
                invocation: invocation,
                receiptPath: arguments.receiptPath
            )
        } catch {
            let receipt = failureReceipt(
                invocation: invocation,
                error: error
            )
            try HostPlatformLayerEffectDocuments.write(
                receipt,
                path: arguments.receiptPath
            )
        }
    }

    private static func executeCorrelated(
        invocation: ProductUpdateLayerEffectInvocation,
        receiptPath: String
    ) throws {
        let configurationData: Data
        do {
            configurationData =
                try HostPlatformLayerEffectDocuments.readData(
                path: invocation.configurationPath
            )
            try requireDigest(
                data: configurationData,
                expected: invocation.configurationSHA256,
                path: invocation.configurationPath
            )
            try validateConfigurationDocument(configurationData)
        } catch {
            throw HostPlatformLayerEffectExecutorError.correlatedInputInvalid(
                "configuration path=\(invocation.configurationPath) reason=\(error)"
            )
        }
        let configuration: HostPlatformLayerEffectConfiguration
        do {
            configuration = try HostPlatformLayerEffectDocuments.decode(
                HostPlatformLayerEffectConfiguration.self,
                data: configurationData,
                path: invocation.configurationPath
            )
            try HostPlatformLayerEffectPolicy.validate(
                invocation: invocation,
                configuration: configuration
            )
        } catch {
            throw HostPlatformLayerEffectExecutorError.correlatedInputInvalid(
                "configuration contract reason=\(error)"
            )
        }
        try requireFileDigest(
            path: invocation.artifactPath,
            expected: invocation.artifactSHA256,
            expectedSizeBytes: UInt64(invocation.artifactSizeBytes)
        )
        let command = try HostPlatformLayerEffectPolicy.makeManagerCommand(
            invocation: invocation,
            configuration: configuration,
            requestedAt: timestamp()
        )
        let operationRoot = URL(
            fileURLWithPath: configuration.manager.exchangeRootPath,
            isDirectory: true
        ).appendingPathComponent(command.operationId, isDirectory: true)
        let managerRequestURL = operationRoot.appendingPathComponent(
            "manager-request.json"
        )
        let managerOperationURL = operationRoot.appendingPathComponent(
            "manager-operation.json"
        )
        try HostPlatformLayerEffectDocuments.write(
            command,
            path: managerRequestURL.path
        )

        let process = Process()
        process.executableURL = URL(
            fileURLWithPath: configuration.manager.executablePath
        )
        process.arguments = [
            "execute",
            "--request", managerRequestURL.path,
            "--operation", managerOperationURL.path,
            "--database", configuration.manager.databasePath,
            "--installation-root",
            configuration.manager.installationRootPath,
            "--launchctl",
            configuration.manager.launchctlExecutablePath,
        ]
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw HostPlatformLayerEffectExecutorError.managerUnavailable(
                String(describing: error)
            )
        }

        let operationData: Data
        do {
            operationData = try HostPlatformLayerEffectDocuments.readData(
                path: managerOperationURL.path
            )
        } catch {
            throw
                HostPlatformLayerEffectExecutorError
                .ownerOperationUnavailable(
                    "manager produced no readable operation; terminationStatus=\(process.terminationStatus) reason=\(error)"
                )
        }
        let operation = try HostPlatformLayerEffectDocuments.decode(
            HostPlatformInstallationOperation.self,
            data: operationData,
            path: managerOperationURL.path
        )
        let receipt: ProductUpdateLayerEffectReceipt
        if operation.state == .succeeded {
            receipt = try HostPlatformLayerEffectPolicy.makeLayerReceipt(
                invocation: invocation,
                operation: operation
            )
        } else {
            receipt = try makeFailedReceipt(
                invocation: invocation,
                operation: operation
            )
        }
        try HostPlatformLayerEffectDocuments.write(
            receipt,
            path: receiptPath
        )
    }

    private static func failureReceipt(
        invocation: ProductUpdateLayerEffectInvocation,
        error: Error
    ) -> ProductUpdateLayerEffectReceipt {
        let classified =
            error as? HostPlatformLayerEffectExecutorError
            ?? .inputUnavailable(
                path: "host-platform-layer-effect-executor",
                reason: String(describing: error)
            )
        return ProductUpdateLayerEffectReceipt(
            schemaVersion: ProductUpdateExecutionContract.schemaVersion,
            updateId: invocation.updateId,
            layer: invocation.layer,
            effectExecutorId: invocation.effectExecutorId,
            operation: invocation.operation,
            artifactSHA256: invocation.artifactSHA256,
            state: classified.receiptState,
            observedAt: timestamp(),
            evidence: ProductUpdateEvidenceReference(
                kind: "host-platform-layer-effect-attempt",
                id:
                    "\(invocation.updateId).host-platform.\(invocation.operation.rawValue)"
            ),
            issue: ProductUpdateIssue(
                code: classified.issueCode,
                message: classified.description,
                retryable: classified.retryable,
                dependency: classified.dependency
            )
        )
    }

    private static func makeFailedReceipt(
        invocation: ProductUpdateLayerEffectInvocation,
        operation: HostPlatformInstallationOperation
    ) throws -> ProductUpdateLayerEffectReceipt {
        let expectedOperationId =
            "\(invocation.updateId).host-platform.\(invocation.operation.rawValue)"
        guard operation.id == expectedOperationId,
            operation.targetRelease.sha256 == invocation.artifactSHA256,
            operation.state == .failed,
            let failureReason = operation.failureReason,
            !failureReason.isEmpty
        else {
            throw HostPlatformLayerEffectExecutorError
                .ownerOperationUnavailable(
                    "terminal failed operation correlation is invalid"
                )
        }
        return ProductUpdateLayerEffectReceipt(
            schemaVersion: ProductUpdateExecutionContract.schemaVersion,
            updateId: invocation.updateId,
            layer: .hostPlatform,
            effectExecutorId: invocation.effectExecutorId,
            operation: invocation.operation,
            artifactSHA256: invocation.artifactSHA256,
            state: .failed,
            observedAt: operation.updatedAt,
            evidence: ProductUpdateEvidenceReference(
                kind: "host-platform-installation-operation",
                id: operation.id
            ),
            issue: ProductUpdateIssue(
                code: "host-platform-installation-failed",
                message: failureReason,
                retryable: false,
                dependency: "host-installation-manager"
            )
        )
    }

    private static func requireDigest(
        data: Data,
        expected: String,
        path: String
    ) throws {
        let actual = digest(data)
        guard actual == expected else {
            throw HostPlatformLayerEffectExecutorError.inputDigestMismatch(
                path: path,
                expected: expected,
                actual: actual
            )
        }
    }

    private static func validateConfigurationDocument(_ data: Data) throws {
        guard
            let root = try JSONSerialization.jsonObject(with: data)
                as? [String: Any]
        else {
            throw HostPlatformLayerEffectExecutorError.inputUnavailable(
                path: "configuration",
                reason: "JSON root must be an object"
            )
        }
        try requireKeys(
            root,
            expected: [
                "schemaVersion", "effectExecutorId", "manager", "apply",
                "rollback",
            ],
            location: "configuration"
        )
        guard let manager = root["manager"] as? [String: Any],
            let apply = root["apply"] as? [String: Any],
            let rollback = root["rollback"] as? [String: Any]
        else {
            throw HostPlatformLayerEffectExecutorError.inputUnavailable(
                path: "configuration",
                reason: "manager/apply/rollback must be objects"
            )
        }
        try requireKeys(
            manager,
            expected: [
                "executablePath", "databasePath", "installationRootPath",
                "launchctlExecutablePath", "exchangeRootPath",
            ],
            location: "configuration.manager"
        )
        let transitionKeys: Set<String> = [
            "installationId", "expectedInstallationRevision",
            "targetReleaseId", "targetReleaseVersion",
            "targetSlotRelativePath",
        ]
        try requireKeys(
            apply,
            expected: transitionKeys,
            location: "configuration.apply"
        )
        try requireKeys(
            rollback,
            expected: transitionKeys,
            location: "configuration.rollback"
        )
    }

    private static func requireKeys(
        _ object: [String: Any],
        expected: Set<String>,
        location: String
    ) throws {
        let actual = Set(object.keys)
        guard actual == expected else {
            throw HostPlatformLayerEffectExecutorError.inputUnavailable(
                path: location,
                reason:
                    "fields differ missing=\(expected.subtracting(actual).sorted()) unknown=\(actual.subtracting(expected).sorted())"
            )
        }
    }

    private static func requireFileDigest(
        path: String,
        expected: String,
        expectedSizeBytes: UInt64
    ) throws {
        do {
            let attributes = try FileManager.default.attributesOfItem(
                atPath: path
            )
            guard let size = attributes[.size] as? NSNumber,
                size.uint64Value == expectedSizeBytes
            else {
                throw HostPlatformLayerEffectExecutorError.inputUnavailable(
                    path: path,
                    reason:
                        "size differs from declared \(expectedSizeBytes) bytes"
                )
            }
            let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
            defer { try? handle.close() }
            var sha256 = SHA256()
            while true {
                let data = try handle.read(upToCount: 1_048_576) ?? Data()
                if data.isEmpty {
                    break
                }
                sha256.update(data: data)
            }
            let actual = sha256.finalize().map {
                String(format: "%02x", $0)
            }.joined()
            guard actual == expected else {
                throw HostPlatformLayerEffectExecutorError.inputDigestMismatch(
                    path: path,
                    expected: expected,
                    actual: actual
                )
            }
        } catch let error as HostPlatformLayerEffectExecutorError {
            throw error
        } catch {
            throw HostPlatformLayerEffectExecutorError.inputUnavailable(
                path: path,
                reason: String(describing: error)
            )
        }
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map {
            String(format: "%02x", $0)
        }.joined()
    }

    private static func timestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}

@main
private enum HostPlatformLayerEffectExecutorMain {
    static func main() {
        do {
            let arguments = try HostPlatformLayerEffectExecutorArguments(
                Array(CommandLine.arguments.dropFirst())
            )
            try HostPlatformLayerEffectExecutor.execute(arguments: arguments)
        } catch {
            FileHandle.standardError.write(
                Data("host platform layer effect failed: \(error)\n".utf8)
            )
            Foundation.exit(EXIT_FAILURE)
        }
    }
}
