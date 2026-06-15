import Foundation

public enum RuntimeGuestRuntimeStateObservationAssembler {
    public static func missing() -> RuntimeGuestRuntimeStateObservation {
        RuntimeGuestRuntimeStateObservation(
            loadedState: nil,
            freshState: nil,
            isFresh: false
        )
    }

    public static func loadFailed(_ message: String) -> RuntimeGuestRuntimeStateObservation {
        RuntimeGuestRuntimeStateObservation(
            loadedState: nil,
            freshState: nil,
            isFresh: false,
            readIssue: .loadFailed(message)
        )
    }

    public static func loaded(
        _ document: GuestRuntimeStateDocument,
        modifiedAt: Date,
        observedAt: Date,
        staleAfterSeconds: TimeInterval
    ) -> RuntimeGuestRuntimeStateObservation {
        let isFresh = observedAt.timeIntervalSince(modifiedAt) <= staleAfterSeconds
        return RuntimeGuestRuntimeStateObservation(
            loadedState: document,
            freshState: isFresh ? document : nil,
            isFresh: isFresh
        )
    }

    public static func metadataReadFailed(
        _ document: GuestRuntimeStateDocument,
        message: String
    ) -> RuntimeGuestRuntimeStateObservation {
        RuntimeGuestRuntimeStateObservation(
            loadedState: document,
            freshState: nil,
            isFresh: false,
            readIssue: .metadataReadFailed(message)
        )
    }
}
