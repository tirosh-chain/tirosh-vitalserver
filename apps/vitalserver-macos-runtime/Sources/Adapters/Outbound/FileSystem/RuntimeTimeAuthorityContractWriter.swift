import Contracts
import Foundation

public struct RuntimeTimeAuthorityContractWriter: Sendable {
    private let destination: URL

    public init(destination: URL) {
        self.destination = destination
    }

    public func write(_ document: RuntimeTimeAuthorityDocument) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(document)
        try data.write(to: destination, options: .atomic)
    }
}
