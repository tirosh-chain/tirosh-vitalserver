import Application
import Contracts
import Foundation
import Errors

public struct RuntimeGuestRuntimeStateObservationReader {
    public let guestGateway: any RuntimeGuestGateway
    public let fileStore: any RuntimeFileReading
    public let runtimeStateURL: URL
    public let staleAfterSeconds: TimeInterval
    public let now: () -> Date

    public init(
        guestGateway: any RuntimeGuestGateway,
        fileStore: any RuntimeFileReading,
        runtimeStateURL: URL,
        staleAfterSeconds: TimeInterval,
        now: @escaping () -> Date
    ) {
        self.guestGateway = guestGateway
        self.fileStore = fileStore
        self.runtimeStateURL = runtimeStateURL
        self.staleAfterSeconds = staleAfterSeconds
        self.now = now
    }

    public func read() -> RuntimeGuestRuntimeStateObservation {
        switch guestGateway.loadRuntimeStateDocument() {
        case .loaded(let document):
            return observation(for: document)
        case .missing:
            return RuntimeGuestRuntimeStateObservationAssembler.missing()
        case .failed(let message):
            return RuntimeGuestRuntimeStateObservationAssembler.loadFailed(message)
        }
    }

    private func observation(for document: GuestRuntimeStateDocument) -> RuntimeGuestRuntimeStateObservation {
        do {
            let modifiedAt = try fileStore.modificationDate(runtimeStateURL)
            return RuntimeGuestRuntimeStateObservationAssembler.loaded(
                document,
                modifiedAt: modifiedAt,
                observedAt: now(),
                staleAfterSeconds: staleAfterSeconds
            )
        } catch {
            return RuntimeGuestRuntimeStateObservationAssembler.metadataReadFailed(
                document,
                message: error.localizedDescription
            )
        }
    }
}
