import Application
import Contracts
import Foundation
import RuntimeControl

struct RuntimeVitalDBGuestReadModelProvider {
    private let loadCurrentObservation: () -> RuntimeVitalDBCurrentObservationRead

    init(load: @escaping () -> RuntimeVitalDBCurrentObservationRead) {
        self.loadCurrentObservation = load
    }

    func load() -> RuntimeVitalDBCurrentObservationRead {
        loadCurrentObservation()
    }

    static func live(
        guestControlBaseURL: @escaping @Sendable () -> String? = {
            RuntimeControlClientConstants.Product.localGuestControlAPIBaseURL
        },
        guestControlGateway: @escaping @Sendable (String) throws -> any RuntimeGuestControlGateway = {
            try HTTPRuntimeGuestControlGateway(
                baseURL: $0,
                timeout: RuntimeControlClientConstants.Product.guestControlAPIStatusReadTimeoutSeconds
            )
        }
    ) -> RuntimeVitalDBGuestReadModelProvider {
        RuntimeVitalDBGuestReadModelProvider {
            guard let baseURL = guestControlBaseURL()?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !baseURL.isEmpty else {
                return .unavailable(readIssues: ["guestControl=baseURLUnavailable"])
            }

            do {
                let gateway = try guestControlGateway(baseURL)
                let recorders = try gateway.vitalDBRecorders()
                let beds = try gateway.vitalDBBeds()
                return Self.makeCurrentObservation(recorders: recorders, beds: beds)
            } catch {
                return .unavailable(readIssues: ["guestControl=\(error)"])
            }
        }
    }

    static func makeCurrentObservation(
        recorders: RuntimeGuestControlVitalDBRecorderRead,
        beds: RuntimeGuestControlVitalDBBedRead
    ) -> RuntimeVitalDBCurrentObservationRead {
        let readIssues = readIssues(recorders: recorders, beds: beds)
        guard recorders.state == .loaded, beds.state == .loaded else {
            return .unavailable(readIssues: readIssues)
        }
        guard let observedAt = recorders.observedAt, !observedAt.isEmpty else {
            return .unavailable(readIssues: readIssues + ["guestControl=recordersObservedAtMissing"])
        }
        guard beds.observedAt == observedAt else {
            return .unavailable(readIssues: readIssues + [
                "guestControl=observedAtMismatch(recorders=\(observedAt),beds=\(beds.observedAt ?? "missing"))"
            ])
        }
        guard let ready = recorders.ready, beds.ready == ready else {
            return .unavailable(readIssues: readIssues + ["guestControl=readyMismatchOrMissing"])
        }
        guard let threshold = recorders.recorderOnlineThresholdSeconds,
              beds.recorderOnlineThresholdSeconds == threshold else {
            return .unavailable(readIssues: readIssues + ["guestControl=recorderOnlineThresholdMismatchOrMissing"])
        }

        return .loaded(
            VitalDBObservationDocument(
                source: "guest-control-api",
                observedAt: observedAt,
                ready: ready,
                recorderOnlineThresholdSeconds: threshold,
                recorders: recorders.recorders,
                beds: beds.beds
            ),
            source: .guestControlAPI,
            readIssues: readIssues
        )
    }

    private static func readIssues(
        recorders: RuntimeGuestControlVitalDBRecorderRead,
        beds: RuntimeGuestControlVitalDBBedRead
    ) -> [String] {
        [
            readIssue(prefix: "recorders", state: recorders.state, readError: recorders.readError),
            readIssue(prefix: "beds", state: beds.state, readError: beds.readError),
        ].compactMap { $0 }
    }

    private static func readIssue(
        prefix: String,
        state: RuntimeGuestControlReadState,
        readError: String?
    ) -> String? {
        if let readError, !readError.isEmpty {
            return "guestControl.\(prefix)=\(readError)"
        }
        return state == .loaded ? nil : "guestControl.\(prefix)=\(state.rawValue)"
    }
}

struct RuntimeVitalDBGuestActivityProvider {
    private let loadActivity: (String) -> RuntimeGuestControlVitalDBRecorderActivityRead

    init(load: @escaping (String) -> RuntimeGuestControlVitalDBRecorderActivityRead) {
        self.loadActivity = load
    }

    func load(vrcode: String) -> RuntimeGuestControlVitalDBRecorderActivityRead {
        loadActivity(vrcode)
    }

    static func live(
        guestControlBaseURL: @escaping @Sendable () -> String? = {
            RuntimeControlClientConstants.Product.localGuestControlAPIBaseURL
        },
        guestControlGateway: @escaping @Sendable (String) throws -> any RuntimeGuestControlGateway = {
            try HTTPRuntimeGuestControlGateway(
                baseURL: $0,
                timeout: RuntimeControlClientConstants.Product.guestControlAPIStatusReadTimeoutSeconds
            )
        }
    ) -> RuntimeVitalDBGuestActivityProvider {
        RuntimeVitalDBGuestActivityProvider { vrcode in
            guard let baseURL = guestControlBaseURL()?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !baseURL.isEmpty else {
                return RuntimeGuestControlVitalDBRecorderActivityRead(
                    state: .unavailable,
                    vrcode: vrcode,
                    readError: "guestControl=baseURLUnavailable"
                )
            }

            do {
                let gateway = try guestControlGateway(baseURL)
                return try gateway.vitalDBRecorderActivity(vrcode)
            } catch {
                return RuntimeGuestControlVitalDBRecorderActivityRead(
                    state: .unavailable,
                    vrcode: vrcode,
                    readError: "guestControl=\(error)"
                )
            }
        }
    }
}
