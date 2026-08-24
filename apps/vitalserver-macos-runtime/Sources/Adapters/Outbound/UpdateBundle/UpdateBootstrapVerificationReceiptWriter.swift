import Contracts
import Foundation

public enum UpdateBootstrapVerificationReceiptWriteError: Error, Equatable {
    case invalidReceipt(reason: String)
    case destinationIdentityMismatch(expected: String, actual: String)
    case destinationIsDirectory(path: String)
    case destinationInspectionFailed(path: String, reason: String)
    case encodeFailed(reason: String)
    case writeFailed(path: String, reason: String)
    case writePermissionDenied(path: String, reason: String)
}

public struct UpdateBootstrapVerificationReceiptWriteOperations {
    public let pathState: (URL) -> RuntimePathState
    public let createDirectory: (URL, Bool) throws -> Void
    public let writeData: (Data, URL, Data.WritingOptions) throws -> Void
    public let validate: (UpdateBootstrapVerificationReceipt) throws -> Void

    public init(
        pathState: @escaping (URL) -> RuntimePathState,
        createDirectory: @escaping (URL, Bool) throws -> Void,
        writeData: @escaping (Data, URL, Data.WritingOptions) throws -> Void,
        validate: @escaping (UpdateBootstrapVerificationReceipt) throws -> Void
    ) {
        self.pathState = pathState
        self.createDirectory = createDirectory
        self.writeData = writeData
        self.validate = validate
    }
}

public struct UpdateBootstrapVerificationReceiptWriter {
    public let operations: UpdateBootstrapVerificationReceiptWriteOperations

    public init(operations: UpdateBootstrapVerificationReceiptWriteOperations) {
        self.operations = operations
    }

    public func write(
        _ receipt: UpdateBootstrapVerificationReceipt,
        to destination: URL
    ) throws {
        do {
            try operations.validate(receipt)
        } catch {
            throw UpdateBootstrapVerificationReceiptWriteError.invalidReceipt(
                reason: String(describing: error)
            )
        }
        let expectedName = UpdateBootstrapVerificationReceiptContract.fileName(
            updateId: receipt.updateId
        )
        guard destination.lastPathComponent == expectedName else {
            throw UpdateBootstrapVerificationReceiptWriteError
                .destinationIdentityMismatch(
                    expected: expectedName,
                    actual: destination.lastPathComponent
                )
        }
        try requireWritableDestination(destination)

        let data: Data
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            data = try encoder.encode(receipt)
        } catch {
            throw UpdateBootstrapVerificationReceiptWriteError.encodeFailed(
                reason: String(describing: error)
            )
        }

        do {
            try operations.createDirectory(
                destination.deletingLastPathComponent(),
                true
            )
            try operations.writeData(data, destination, [.atomic])
        } catch {
            if POSIXFileAccessFailure.isPermissionDenied(error) {
                throw UpdateBootstrapVerificationReceiptWriteError
                    .writePermissionDenied(
                        path: destination.path,
                        reason: String(describing: error)
                    )
            }
            throw UpdateBootstrapVerificationReceiptWriteError.writeFailed(
                path: destination.path,
                reason: String(describing: error)
            )
        }
    }

    private func requireWritableDestination(_ destination: URL) throws {
        switch operations.pathState(destination) {
        case .missing, .file:
            return
        case .directory:
            throw UpdateBootstrapVerificationReceiptWriteError
                .destinationIsDirectory(path: destination.path)
        case .other(let value):
            throw UpdateBootstrapVerificationReceiptWriteError
                .destinationInspectionFailed(
                    path: destination.path,
                    reason: "unexpected path state: \(value)"
                )
        case .inspectFailed(let reason):
            throw UpdateBootstrapVerificationReceiptWriteError
                .destinationInspectionFailed(
                    path: destination.path,
                    reason: reason
                )
        case .unknown(let value):
            throw UpdateBootstrapVerificationReceiptWriteError
                .destinationInspectionFailed(
                    path: destination.path,
                    reason: "unknown path state: \(value)"
                )
        }
    }
}
