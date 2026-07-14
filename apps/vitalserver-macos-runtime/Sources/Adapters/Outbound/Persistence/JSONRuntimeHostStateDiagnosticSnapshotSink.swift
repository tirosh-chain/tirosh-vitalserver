import Application
import Foundation

public enum JSONRuntimeHostStateDiagnosticSnapshotSinkError: Error, Equatable, CustomStringConvertible {
    case operationFailed(path: String, reason: String)
    case verificationFailed(path: String)

    public var description: String {
        switch self {
        case .operationFailed(let path, let reason):
            return "Host state diagnostic snapshot operation failed path=\(path) reason=\(reason)"
        case .verificationFailed(let path):
            return "Host state diagnostic snapshot verification failed path=\(path)"
        }
    }
}

public struct JSONRuntimeHostStateDiagnosticSnapshotSink:
    RuntimeHostStateDiagnosticSnapshotWriting,
    @unchecked Sendable
{
    public let url: URL
    private let fileStore: any RuntimeFileStore
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        url: URL,
        fileStore: any RuntimeFileStore = SystemRuntimeFileStore()
    ) {
        self.url = url
        self.fileStore = fileStore
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder
        self.decoder = JSONDecoder()
    }

    public func writeHostStateDiagnosticSnapshot(
        _ snapshot: RuntimeHostStateDiagnosticSnapshot
    ) throws {
        do {
            let data = try encoder.encode(snapshot)
            try fileStore.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileStore.writeData(
                data,
                to: url,
                options: .atomic,
                posixPermissions: 0o600
            )
            let verified = try decoder.decode(
                RuntimeHostStateDiagnosticSnapshot.self,
                from: fileStore.readData(url)
            )
            guard verified == snapshot else {
                throw JSONRuntimeHostStateDiagnosticSnapshotSinkError.verificationFailed(
                    path: url.path
                )
            }
        } catch let error as JSONRuntimeHostStateDiagnosticSnapshotSinkError {
            throw error
        } catch {
            throw JSONRuntimeHostStateDiagnosticSnapshotSinkError.operationFailed(
                path: url.path,
                reason: String(describing: error)
            )
        }
    }
}
