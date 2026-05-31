import Foundation
import Core
import Contracts

struct RuntimeGuestRuntimeStateObservation {
    let loadedState: GuestRuntimeStateDocument?
    let freshState: GuestRuntimeStateDocument?
    let isFresh: Bool
    let failureReasons: [RuntimeFailureReason]

    var isPresent: Bool {
        loadedState != nil
    }
}

struct RuntimeGuestRuntimeStateObservationReader {
    let guestGateway: any RuntimeGuestGateway
    let fileStore: any RuntimeFileReading
    let runtimeStateURL: URL
    let staleAfterSeconds: TimeInterval
    let now: () -> Date

    init(
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

    func read() -> RuntimeGuestRuntimeStateObservation {
        switch guestGateway.loadRuntimeStateDocument() {
        case .loaded(let document):
            return observation(for: document)
        case .missing:
            return RuntimeGuestRuntimeStateObservation(
                loadedState: nil,
                freshState: nil,
                isFresh: true,
                failureReasons: []
            )
        case .failed:
            return RuntimeGuestRuntimeStateObservation(
                loadedState: nil,
                freshState: nil,
                isFresh: true,
                failureReasons: [.guestRuntimeStateInvalid]
            )
        }
    }

    private func observation(for document: GuestRuntimeStateDocument) -> RuntimeGuestRuntimeStateObservation {
        do {
            let modifiedAt = try fileStore.modificationDate(runtimeStateURL)
            let isFresh = now().timeIntervalSince(modifiedAt) <= staleAfterSeconds
            return RuntimeGuestRuntimeStateObservation(
                loadedState: document,
                freshState: isFresh ? document : nil,
                isFresh: isFresh,
                failureReasons: []
            )
        } catch {
            return RuntimeGuestRuntimeStateObservation(
                loadedState: document,
                freshState: nil,
                isFresh: false,
                failureReasons: [.guestRuntimeStateInvalid]
            )
        }
    }
}
