import Foundation
import Application
import Contracts
import Errors

public struct JSONFileRuntimeStatusArtifactSink: RuntimeStatusArtifactSink {
    public let url: URL
    public let requiredExistingRoot: URL?
    private let fileStore: RuntimeFileReading & RuntimeFileWriting

    public init(
        url: URL,
        requiredExistingRoot: URL? = nil,
        fileStore: RuntimeFileReading & RuntimeFileWriting = SystemRuntimeFileStore()
    ) {
        self.url = url
        self.requiredExistingRoot = requiredExistingRoot
        self.fileStore = fileStore
    }

    public func save(_ document: RuntimeStatusDocument) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(document)
        try requireExistingRootBeforeSave()
        try fileStore.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileStore.writeData(data, to: url, options: .atomic)
    }

    private func requireExistingRootBeforeSave() throws {
        guard let requiredExistingRoot else {
            return
        }
        let state = fileStore.pathState(at: requiredExistingRoot)
        switch state {
        case .directory:
            return
        case .missing:
            throw RuntimeArtifactSinkError.missingRequiredRoot(path: requiredExistingRoot.path)
        case .inspectFailed(let reason):
            throw RuntimeArtifactSinkError.requiredRootInspectionFailed(
                path: requiredExistingRoot.path,
                reason: reason
            )
        case .file, .other, .unknown:
            throw RuntimeArtifactSinkError.unexpectedRequiredRootState(
                path: requiredExistingRoot.path,
                state: state.rawValue
            )
        }
    }
}
