import Application
import Contracts
import Foundation
import Errors

public struct RuntimeGuestRuntimeStateObservation {
    public let loadedState: GuestRuntimeStateDocument?
    public let freshState: GuestRuntimeStateDocument?
    public let isFresh: Bool
    public let failureReasons: [RuntimeFailureReason]

    public var isPresent: Bool {
        loadedState != nil
    }

    public init(
        loadedState: GuestRuntimeStateDocument?,
        freshState: GuestRuntimeStateDocument?,
        isFresh: Bool,
        failureReasons: [RuntimeFailureReason]
    ) {
        self.loadedState = loadedState
        self.freshState = freshState
        self.isFresh = isFresh
        self.failureReasons = failureReasons
    }
}

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
