import Application
import Contracts
import Foundation
import OutboundAdapters
import RuntimeControl

final class RuntimeControlGuestAddressController: RuntimeGuestAddressProvider, @unchecked Sendable {
    private let reader: any RuntimeGuestAddressResourceReading
    private let writer: any RuntimeGuestAddressResourceWriting

    init(
        reader: any RuntimeGuestAddressResourceReading,
        writer: any RuntimeGuestAddressResourceWriting
    ) {
        self.reader = reader
        self.writer = writer
    }

    func readGuestAddress() -> RuntimeGuestAddressReadResult {
        RuntimeGuestAddressResourceReadMapper.readResult(from: reader.loadGuestAddressResource())
    }

    private func loadGuestAddressResourceSync() -> RuntimeGuestAddressResourceState {
        reader.loadGuestAddressResource()
    }

    @discardableResult
    private func putGuestAddressResourceSync(address: String) -> RuntimeGuestAddressResourceState {
        do {
            return try writer.putGuestAddressResource(address: address)
        } catch {
            return .failed(readError: "Runtime endpoint write failed: \(error)")
        }
    }
}

@MainActor
extension RuntimeControlGuestAddressController: RuntimeGuestAddressResourceClient {
    func loadGuestAddressResource() async throws -> RuntimeGuestAddressResourceState {
        loadGuestAddressResourceSync()
    }

    func putGuestAddressResource(address: String) async throws -> RuntimeGuestAddressResourceState {
        putGuestAddressResourceSync(address: address)
    }
}
