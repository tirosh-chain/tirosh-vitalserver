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
                timeout: RuntimeControlClientConstants.Product.guestControlAPIProductReadModelTimeoutSeconds
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
                var labRecorders = RuntimeLabRecorderList(state: .unavailable, recorders: [])
                var labBeds = RuntimeLabBedList(state: .unavailable, beds: [])
                var labReadIssues: [String] = []

                if let labGateway = gateway as? any RuntimeGuestProductLabGateway {
                    do {
                        labRecorders = try labGateway.labRecorders()
                    } catch {
                        labReadIssues.append("guestControl=labRecorders=\(error)")
                    }

                    do {
                        labBeds = try labGateway.labBeds()
                    } catch {
                        labReadIssues.append("guestControl=labBeds=\(error)")
                    }
                }

                return Self.makeCurrentObservation(
                    recorders: recorders,
                    beds: beds,
                    labRecorders: labRecorders,
                    labBeds: labBeds,
                    externalReadIssues: labReadIssues
                )
            } catch {
                return .unavailable(readIssues: ["guestControl=\(error)"])
            }
        }
    }

    static func makeCurrentObservation(
        recorders: RuntimeGuestControlVitalDBRecorderRead,
        beds: RuntimeGuestControlVitalDBBedRead
    ) -> RuntimeVitalDBCurrentObservationRead {
        makeCurrentObservation(
            recorders: recorders,
            beds: beds,
            labRecorders: RuntimeLabRecorderList(state: .loaded, recorders: []),
            labBeds: RuntimeLabBedList(state: .loaded, beds: []),
            externalReadIssues: []
        )
    }

    static func makeCurrentObservation(
        recorders: RuntimeGuestControlVitalDBRecorderRead,
        beds: RuntimeGuestControlVitalDBBedRead,
        labRecorders: RuntimeLabRecorderList,
        labBeds: RuntimeLabBedList,
        externalReadIssues: [String]
    ) -> RuntimeVitalDBCurrentObservationRead {
        let readIssues = readIssues(
            recorders: recorders,
            beds: beds,
            labRecorders: labRecorders,
            labBeds: labBeds,
            externalReadIssues: externalReadIssues
        )
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
                recorders: mergeRecorders(vitalRecorders: recorders.recorders, labRecorders: labRecorders.recorders),
                beds: mergeBeds(vitalBeds: beds.beds, labBeds: labBeds.beds, labRecorders: labRecorders.recorders)
            ),
            source: .guestControlAPI,
            readIssues: readIssues
        )
    }

    private static func readIssues(
        recorders: RuntimeGuestControlVitalDBRecorderRead,
        beds: RuntimeGuestControlVitalDBBedRead,
        labRecorders: RuntimeLabRecorderList,
        labBeds: RuntimeLabBedList,
        externalReadIssues: [String]
    ) -> [String] {
        [
            readIssue(prefix: "recorders", state: recorders.state, readError: recorders.readError),
            readIssue(prefix: "beds", state: beds.state, readError: beds.readError),
            readIssue(prefix: "labRecorders", state: labRecorders.state, readError: labRecorders.readError),
            readIssue(prefix: "labBeds", state: labBeds.state, readError: labBeds.readError),
        ].compactMap { $0 } + externalReadIssues
    }

    private static func mergeRecorders(
        vitalRecorders: [VitalDBRecorderObservation],
        labRecorders: [RuntimeLabRecorder]
    ) -> [VitalDBRecorderObservation] {
        var merged = vitalRecorders
        var recordersByCode = Set(vitalRecorders.map(\.vrcode))

        for recorder in labRecorders where !recordersByCode.contains(recorder.vrcode) {
            merged.append(mapLabRecorder(recorder))
            recordersByCode.insert(recorder.vrcode)
        }

        return merged
    }

    private static func mergeBeds(
        vitalBeds: [VitalDBBedObservation],
        labBeds: [RuntimeLabBed],
        labRecorders: [RuntimeLabRecorder]
    ) -> [VitalDBBedObservation] {
        let bedIDs = Set(vitalBeds.map(\.bedID))
        var merged = vitalBeds

        var recorderByBedID = [String: String]()
        for recorder in labRecorders where recorderByBedID[recorder.bedId] == nil {
            recorderByBedID[recorder.bedId] = recorder.vrcode
        }

        for bed in labBeds where !bedIDs.contains(bed.bedId) {
            merged.append(mapLabBed(bed, vrcode: recorderByBedID[bed.bedId]))
        }

        return merged
    }

    private static func mapLabRecorder(_ recorder: RuntimeLabRecorder) -> VitalDBRecorderObservation {
        let online = isLabEntityOnline(recorder.state)
        return VitalDBRecorderObservation(
            vrcode: recorder.vrcode,
            ip: nil,
            lastSeenAt: recorder.lastSendAt ?? recorder.updatedAt ?? recorder.createdAt,
            online: online,
            stale: !online,
            visibility: nil
        )
    }

    private static func mapLabBed(_ bed: RuntimeLabBed, vrcode: String?) -> VitalDBBedObservation {
        VitalDBBedObservation(
            bedID: bed.bedId,
            name: bed.name,
            vrcode: vrcode,
            lastSeenAt: bed.updatedAt ?? bed.createdAt,
            patientConnected: nil,
            online: isLabEntityOnline(bed.state),
            visibility: nil
        )
    }

    private static func isLabEntityOnline(_ state: RuntimeLabSessionState) -> Bool {
        switch state {
        case .accepted, .running:
            return true
        case .stopping, .stopped, .failed, .unavailable:
            return false
        }
    }

    private static func readIssue(
        prefix: String,
        state: RuntimeLabReadState,
        readError: String?
    ) -> String? {
        if let readError, !readError.isEmpty {
            return "guestControl=\(prefix)=\(readError)"
        }
        return state == .failed ? "guestControl=\(prefix)=\(state.rawValue)" : nil
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

struct RuntimeVitalDBGuestBedReadModelProvider {
    private let loadBedHistory: () -> RuntimeVitalBedHistory

    init(load: @escaping () -> RuntimeVitalBedHistory) {
        self.loadBedHistory = load
    }

    func load() -> RuntimeVitalBedHistory {
        loadBedHistory()
    }

    static func live(
        guestControlBaseURL: @escaping @Sendable () -> String? = {
            RuntimeControlClientConstants.Product.localGuestControlAPIBaseURL
        },
        guestControlGateway: @escaping @Sendable (String) throws -> any RuntimeGuestControlGateway = {
            try HTTPRuntimeGuestControlGateway(
                baseURL: $0,
                timeout: RuntimeControlClientConstants.Product.guestControlAPIProductReadModelTimeoutSeconds
            )
        }
    ) -> RuntimeVitalDBGuestBedReadModelProvider {
        RuntimeVitalDBGuestBedReadModelProvider {
            guard let baseURL = guestControlBaseURL()?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !baseURL.isEmpty else {
                return .failed(readError: "guestControl=baseURLUnavailable")
            }

            do {
                let gateway = try guestControlGateway(baseURL)
                return RuntimeVitalDBBedHistoryAssembler.makeHistory(read: try gateway.vitalDBBeds())
            } catch {
                return .failed(readError: "guestControl=\(error)")
            }
        }
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
                timeout: RuntimeControlClientConstants.Product.guestControlAPIProductReadModelTimeoutSeconds
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
