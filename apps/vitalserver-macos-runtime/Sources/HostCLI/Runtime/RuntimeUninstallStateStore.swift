import Foundation
import Contracts
import Core

struct RuntimeUninstallStateStore: @unchecked Sendable {
    let url: URL
    let fileStore: RuntimeFileWriting
    let now: () -> Date

    init(
        url: URL,
        fileStore: RuntimeFileWriting,
        now: @escaping () -> Date = Date.init
    ) {
        self.url = url
        self.fileStore = fileStore
        self.now = now
    }

    func write(
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
        try fileStore.writeData(try JSONEncoder.pretty.encode(document), to: url, options: .atomic)
    }
}
