import Contracts
import Foundation
import Errors

public struct RuntimeBundleMaterializationContext: Equatable, Sendable {
    public let tarExecutable: String

    public init(tarExecutable: String) {
        self.tarExecutable = tarExecutable
    }
}

public struct RuntimeBundleMaterializationOperations {
    public let pathState: (URL) -> RuntimePathState
    public let temporaryRoot: () -> URL
    public let createDirectory: (URL, Bool) throws -> Void
    public let runProcess: (String, [String]) -> RuntimeProcessResult
    public let runRequired: (String, [String]) throws -> Void
    public let rootDirectory: (String) throws -> String
    public let validateArchiveEntryTypes: (String, String) throws -> Void
    public let missingFileError: (URL) -> Error
    public let invalidArchiveError: (URL) -> Error
    public let pathInspectionError: (URL, String) -> Error
    public let unexpectedPathStateError: (URL, RuntimePathState) -> Error
    public let archiveValidationError: (Error) -> Error
    public let log: (String) -> Void

    public init(
        pathState: @escaping (URL) -> RuntimePathState,
        temporaryRoot: @escaping () -> URL,
        createDirectory: @escaping (URL, Bool) throws -> Void,
        runProcess: @escaping (String, [String]) -> RuntimeProcessResult,
        runRequired: @escaping (String, [String]) throws -> Void,
        rootDirectory: @escaping (String) throws -> String,
        validateArchiveEntryTypes: @escaping (String, String) throws -> Void,
        missingFileError: @escaping (URL) -> Error,
        invalidArchiveError: @escaping (URL) -> Error,
        pathInspectionError: @escaping (URL, String) -> Error,
        unexpectedPathStateError: @escaping (URL, RuntimePathState) -> Error,
        archiveValidationError: @escaping (Error) -> Error,
        log: @escaping (String) -> Void
    ) {
        self.pathState = pathState
        self.temporaryRoot = temporaryRoot
        self.createDirectory = createDirectory
        self.runProcess = runProcess
        self.runRequired = runRequired
        self.rootDirectory = rootDirectory
        self.validateArchiveEntryTypes = validateArchiveEntryTypes
        self.missingFileError = missingFileError
        self.invalidArchiveError = invalidArchiveError
        self.pathInspectionError = pathInspectionError
        self.unexpectedPathStateError = unexpectedPathStateError
        self.archiveValidationError = archiveValidationError
        self.log = log
    }
}

public struct RuntimeBundleMaterializer {
    public let context: RuntimeBundleMaterializationContext
    public let operations: RuntimeBundleMaterializationOperations

    public init(
        context: RuntimeBundleMaterializationContext,
        operations: RuntimeBundleMaterializationOperations
    ) {
        self.context = context
        self.operations = operations
    }

    public func materialize(_ bundleURL: URL) throws -> RuntimeMaterializedBundle {
        let inputState = operations.pathState(bundleURL)
        switch inputState {
        case .directory:
            return RuntimeMaterializedBundle(bundleURL: bundleURL, temporaryRoot: nil)
        case .file:
            guard isUpdateBundleArchive(bundleURL) else {
                throw operations.invalidArchiveError(bundleURL)
            }
        case .missing:
            throw operations.missingFileError(bundleURL)
        case .other:
            throw operations.unexpectedPathStateError(bundleURL, inputState)
        case .inspectFailed(let reason):
            throw operations.pathInspectionError(bundleURL, reason)
        case .unknown:
            throw operations.unexpectedPathStateError(bundleURL, inputState)
        }

        let temporaryRoot = operations.temporaryRoot()
        try operations.createDirectory(temporaryRoot, true)
        let extractedBundle = try extractBundleArchive(bundleURL, to: temporaryRoot)
        return RuntimeMaterializedBundle(bundleURL: extractedBundle, temporaryRoot: temporaryRoot)
    }

    private func extractBundleArchive(_ archiveURL: URL, to temporaryRoot: URL) throws -> URL {
        let listResult = operations.runProcess(context.tarExecutable, ["-tzf", archiveURL.path])
        guard listResult.exitCode == 0 else {
            let stderr = listResult.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if !stderr.isEmpty {
                operations.log("bundle archive list failed stderr=\(stderr)")
            }
            throw operations.invalidArchiveError(archiveURL)
        }

        let rootName = try archiveRootDirectory(listResult.stdout)
        try validateBundleArchiveEntryTypes(archiveURL)
        try operations.runRequired(context.tarExecutable, ["-xzf", archiveURL.path, "-C", temporaryRoot.path])
        let extractedBundle = temporaryRoot.appendingPathComponent(rootName, isDirectory: true)
        let extractedState = operations.pathState(extractedBundle)
        switch extractedState {
        case .directory:
            break
        case .missing:
            throw operations.missingFileError(extractedBundle)
        case .file, .other, .unknown:
            throw operations.unexpectedPathStateError(extractedBundle, extractedState)
        case .inspectFailed(let reason):
            throw operations.pathInspectionError(extractedBundle, reason)
        }
        operations.log("bundle archive extracted source=\(archiveURL.path) destination=\(extractedBundle.path)")
        return extractedBundle
    }

    private func archiveRootDirectory(_ output: String) throws -> String {
        do {
            return try operations.rootDirectory(output)
        } catch {
            throw operations.archiveValidationError(error)
        }
    }

    private func validateBundleArchiveEntryTypes(_ archiveURL: URL) throws {
        let result = operations.runProcess(context.tarExecutable, ["-tvzf", archiveURL.path])
        guard result.exitCode == 0 else {
            throw operations.invalidArchiveError(archiveURL)
        }
        do {
            try operations.validateArchiveEntryTypes(result.stdout, archiveURL.lastPathComponent)
        } catch {
            throw operations.archiveValidationError(error)
        }
    }

    private func isUpdateBundleArchive(_ url: URL) -> Bool {
        url.lastPathComponent.hasSuffix(".tar.gz") || url.lastPathComponent.hasSuffix(".tgz")
    }
}
