import Application
import Contracts
import Foundation

public struct RuntimeVMIPFileGuestAddressProvider: RuntimeGuestAddressProvider {
    private let url: URL
    private let fileStore: RuntimeFileReading

    public init(
        url: URL,
        fileStore: RuntimeFileReading
    ) {
        self.url = url
        self.fileStore = fileStore
    }

    public func readGuestAddress() -> RuntimeGuestAddressReadResult {
        switch fileStore.pathState(at: url) {
        case .file:
            return readFile()
        case .missing:
            return .missing("vm-ip file missing path=\(url.path)")
        case .directory:
            return .invalid("vm-ip path is directory path=\(url.path)")
        case .other(let type):
            return .invalid("vm-ip path is \(type) path=\(url.path)")
        case .inspectFailed(let reason):
            return .readFailed("vm-ip path inspection failed path=\(url.path) reason=\(reason)")
        case .unknown(let value):
            return .readFailed("vm-ip path state unknown path=\(url.path) value=\(value)")
        }
    }

    private func readFile() -> RuntimeGuestAddressReadResult {
        do {
            let value = String(decoding: try fileStore.readData(url), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else {
                return .invalid("vm-ip file empty path=\(url.path)")
            }
            return .loaded(address: value, source: .vmIPFile)
        } catch {
            return .readFailed("vm-ip file read failed path=\(url.path) error=\(error)")
        }
    }
}
