import Application
import Contracts
import Foundation
import OutboundAdapters
import RuntimeControl

final class RuntimeControlGuestAddressController: RuntimeGuestAddressProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var resource: RuntimeGuestAddressResourceState

    init() {
        self.resource = .missing(readError: "Guest address resource missing")
    }

    func readGuestAddress() -> RuntimeGuestAddressReadResult {
        RuntimeGuestAddressResourceReadMapper.readResult(from: loadGuestAddressResourceSync())
    }

    private func loadGuestAddressResourceSync() -> RuntimeGuestAddressResourceState {
        withLock {
            resource
        }
    }

    @discardableResult
    private func putGuestAddressResourceSync(address: String) -> RuntimeGuestAddressResourceState {
        withLock {
            let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                resource = .failed(readError: "Guest address is empty")
                return resource
            }
            let read = RuntimeGuestAddressReadResult.loaded(
                address: trimmed,
                source: .runtimeControlAPI
            )
            resource = .loaded(read)
            return resource
        }
    }

    private func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
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
