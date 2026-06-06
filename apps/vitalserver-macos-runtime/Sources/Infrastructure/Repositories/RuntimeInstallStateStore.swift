import Application
import Contracts
import Foundation

public struct RuntimeInstallStateStore: @unchecked Sendable {
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
        state: RuntimeInstallState,
        mode: RuntimeInstallMode,
        currentStep: RuntimeWorkflowStep?,
        message: String?,
        blockers: [String]
    ) throws {
        let document = RuntimeInstallStateDocument(
            state: state,
            mode: mode,
            currentStep: currentStep,
            updatedAt: ISO8601DateFormatter().string(from: now()),
            message: message,
            blockers: blockers
        )
        try fileStore.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileStore.writeData(try runtimeStateDocumentEncoder().encode(document), to: url, options: .atomic)
    }
}

private func runtimeStateDocumentEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return encoder
}
