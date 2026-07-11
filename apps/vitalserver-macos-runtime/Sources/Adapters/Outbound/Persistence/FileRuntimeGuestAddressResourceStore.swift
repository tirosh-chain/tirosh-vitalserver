import Application
import Contracts
import Foundation
import RuntimeControl

public struct FileRuntimeGuestAddressResourceStore: RuntimeGuestAddressProvider,
    RuntimeGuestAddressResourceReading, RuntimeGuestAddressResourceWriting, @unchecked Sendable
{
    private let documentURL: URL
    private let fileStore: any RuntimeFileStore
    private let fileLock: any RuntimeFileLocking
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        documentURL: URL,
        fileStore: any RuntimeFileStore = SystemRuntimeFileStore(),
        fileLock: any RuntimeFileLocking = POSIXRuntimeFileLock(),
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.documentURL = documentURL
        self.fileStore = fileStore
        self.fileLock = fileLock
        self.encoder = encoder
        self.decoder = decoder
    }

    public func readGuestAddress() -> RuntimeGuestAddressReadResult {
        RuntimeGuestAddressResourceReadMapper.readResult(from: loadGuestAddressResource())
    }

    public func loadGuestAddressResource() -> RuntimeGuestAddressResourceState {
        switch fileStore.pathState(at: documentURL) {
        case .missing:
            return .missing(readError: "Runtime endpoint document missing path=\(documentURL.path)")
        case .file:
            do {
                let read = try decoder.decode(
                    RuntimeGuestAddressReadResult.self,
                    from: fileStore.readData(documentURL)
                )
                guard read.state == .loaded,
                      let address = read.address?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !address.isEmpty,
                      read.source == .platformAgent
                else {
                    return .failed(
                        readError: "Runtime endpoint document is invalid path=\(documentURL.path)"
                    )
                }
                return .loaded(.loaded(address: address, source: .platformAgent))
            } catch {
                return .failed(
                    readError: "Runtime endpoint document read failed path=\(documentURL.path) reason=\(error)"
                )
            }
        case .directory:
            return .failed(readError: "Runtime endpoint path is a directory path=\(documentURL.path)")
        case .other(let value):
            return .failed(
                readError: "Runtime endpoint path has unsupported type path=\(documentURL.path) type=\(value)"
            )
        case .inspectFailed(let reason):
            return .failed(
                readError: "Runtime endpoint path inspection failed path=\(documentURL.path) reason=\(reason)"
            )
        case .unknown(let value):
            return .failed(
                readError: "Runtime endpoint path state is unknown path=\(documentURL.path) state=\(value)"
            )
        }
    }

    @discardableResult
    public func putGuestAddressResource(address: String) throws -> RuntimeGuestAddressResourceState {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .failed(readError: "Runtime endpoint address is empty")
        }
        return try fileLock.withExclusiveLock(for: documentURL) {
            let read = RuntimeGuestAddressReadResult.loaded(
                address: trimmed,
                source: .platformAgent
            )
            try fileStore.createDirectory(
                at: documentURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileStore.writeData(
                encoder.encode(read),
                to: documentURL,
                options: .atomic
            )
            return .loaded(read)
        }
    }
}
