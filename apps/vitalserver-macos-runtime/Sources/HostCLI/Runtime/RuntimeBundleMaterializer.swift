import Contracts
import Core
import Foundation

public struct RuntimeBundleMaterializationContext: Equatable, Sendable {
    public let tarExecutable: String

    public init(tarExecutable: String) {
        self.tarExecutable = tarExecutable
    }
}

public struct RuntimeBundleMaterializationOperations {
    public let directoryExists: (URL) -> Bool
    public let fileExists: (URL) -> Bool
    public let temporaryRoot: () -> URL
    public let createDirectory: (URL, Bool) throws -> Void
    public let runProcess: (String, [String]) -> RuntimeProcessResult
    public let runRequired: (String, [String]) throws -> Void
    public let missingFileError: (URL) -> Error
    public let invalidArchiveError: (URL) -> Error
    public let archiveValidationError: (UpdateBundleArchiveVerificationError) -> Error
    public let log: (String) -> Void

    public init(
        directoryExists: @escaping (URL) -> Bool,
        fileExists: @escaping (URL) -> Bool,
        temporaryRoot: @escaping () -> URL,
        createDirectory: @escaping (URL, Bool) throws -> Void,
        runProcess: @escaping (String, [String]) -> RuntimeProcessResult,
        runRequired: @escaping (String, [String]) throws -> Void,
        missingFileError: @escaping (URL) -> Error,
        invalidArchiveError: @escaping (URL) -> Error,
        archiveValidationError: @escaping (UpdateBundleArchiveVerificationError) -> Error,
        log: @escaping (String) -> Void
    ) {
        self.directoryExists = directoryExists
        self.fileExists = fileExists
        self.temporaryRoot = temporaryRoot
        self.createDirectory = createDirectory
        self.runProcess = runProcess
        self.runRequired = runRequired
        self.missingFileError = missingFileError
        self.invalidArchiveError = invalidArchiveError
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
        if operations.directoryExists(bundleURL) {
            return RuntimeMaterializedBundle(bundleURL: bundleURL, temporaryRoot: nil)
        }
        guard operations.fileExists(bundleURL), isUpdateBundleArchive(bundleURL) else {
            throw operations.missingFileError(bundleURL)
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
        guard operations.directoryExists(extractedBundle) else {
            throw operations.missingFileError(extractedBundle)
        }
        operations.log("bundle archive extracted source=\(archiveURL.path) destination=\(extractedBundle.path)")
        return extractedBundle
    }

    private func archiveRootDirectory(_ output: String) throws -> String {
        do {
            return try UpdateBundleArchiveVerifier.rootDirectory(listOutput: output)
        } catch let error as UpdateBundleArchiveVerificationError {
            throw operations.archiveValidationError(error)
        }
    }

    private func validateBundleArchiveEntryTypes(_ archiveURL: URL) throws {
        let result = operations.runProcess(context.tarExecutable, ["-tvzf", archiveURL.path])
        guard result.exitCode == 0 else {
            throw operations.invalidArchiveError(archiveURL)
        }
        do {
            try UpdateBundleArchiveVerifier.rejectUnsupportedEntryTypes(
                verboseListOutput: result.stdout,
                archiveName: archiveURL.lastPathComponent
            )
        } catch let error as UpdateBundleArchiveVerificationError {
            throw operations.archiveValidationError(error)
        }
    }

    private func isUpdateBundleArchive(_ url: URL) -> Bool {
        url.lastPathComponent.hasSuffix(".tar.gz") || url.lastPathComponent.hasSuffix(".tgz")
    }
}
