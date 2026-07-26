import Application
import Contracts
import Darwin
import Foundation

public struct FileRuntimeGuestAddressBootstrapReader:
    RuntimeGuestAddressBootstrapReading,
    @unchecked Sendable
{
    private let url: URL
    private let fileStore: RuntimeFileReading

    public init(
        url: URL,
        fileStore: RuntimeFileReading = SystemRuntimeFileStore()
    ) {
        self.url = url
        self.fileStore = fileStore
    }

    public func readBootstrapGuestAddress() -> RuntimeGuestAddressReadResult {
        switch fileStore.pathState(at: url) {
        case .missing:
            return .missing("VM IP bootstrap evidence is missing path=\(url.path)")
        case .file:
            break
        case .inspectFailed(let reason):
            return .readFailed("VM IP bootstrap evidence inspection failed path=\(url.path) reason=\(reason)")
        case .directory, .other, .unknown:
            return .invalid(
                "VM IP bootstrap evidence path is not a regular file path=\(url.path) state=\(fileStore.pathState(at: url).rawValue)"
            )
        }

        let raw: String
        do {
            raw = try fileStore.readUTF8Text(url)
        } catch {
            return .readFailed(
                "VM IP bootstrap evidence read failed path=\(url.path) reason=\(error.localizedDescription)"
            )
        }
        let address = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty else {
            return .invalid("VM IP bootstrap evidence is empty path=\(url.path)")
        }
        var parsed = in_addr()
        guard address.withCString({ inet_pton(AF_INET, $0, &parsed) }) == 1 else {
            return .invalid("VM IP bootstrap evidence is not an IPv4 address path=\(url.path) value=\(address)")
        }
        return .loaded(address: address, source: .platformAgent)
    }
}
