import Application
import Contracts
import Foundation

public struct RuntimeHostTimeContractWriter {
    private let destination: URL
    private let fileStore: RuntimeFileStore
    private let now: () -> Date
    private let log: (String) -> Void

    public init(
        destination: URL,
        fileStore: RuntimeFileStore,
        now: @escaping () -> Date,
        log: @escaping (String) -> Void
    ) {
        self.destination = destination
        self.fileStore = fileStore
        self.now = now
        self.log = log
    }

    public func write() throws {
        let currentTime = now()
        let document = RuntimeHostTimeDocument(
            epochSeconds: Int64(currentTime.timeIntervalSince1970.rounded(.down)),
            updatedAt: ISO8601DateFormatter().string(from: currentTime)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try fileStore.writeData(
            try encoder.encode(document),
            to: destination,
            options: .atomic
        )
        log("host time contract written path=\(destination.path) epochSeconds=\(document.epochSeconds)")
    }
}
