import Application
import Contracts
import Foundation
import Errors

public struct RuntimeUninstallWorkflowStateArtifactStore: @unchecked Sendable {
    public let url: URL
    public let fileStore: RuntimeFileWriting
    public let now: () -> Date

    public init(
        url: URL,
        fileStore: RuntimeFileWriting,
        now: @escaping () -> Date = Date.init
    ) {
        self.url = url
        self.fileStore = fileStore
        self.now = now
    }

    public func write(
        state: RuntimeUninstallState,
        clean: Bool,
        message: String?,
        blockers: [String]
    ) throws {
        let document = RuntimeUninstallStateDocument(
            state: state,
            clean: clean,
            updatedAt: ISO8601DateFormatter().string(from: now()),
            message: message,
            blockers: blockers
        )
        try fileStore.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileStore.writeData(try runtimeWorkflowStateArtifactDocumentEncoder().encode(document), to: url, options: .atomic)
    }
}

private func runtimeWorkflowStateArtifactDocumentEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return encoder
}
