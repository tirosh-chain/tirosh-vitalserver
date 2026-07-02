import Application
import Contracts
import Foundation
import RuntimeControl

struct RuntimeVitalDBCurrentObservationProvider {
    private let loadCurrentObservation: () -> RuntimeVitalDBCurrentObservationRead

    init(load: @escaping () -> RuntimeVitalDBCurrentObservationRead) {
        self.loadCurrentObservation = load
    }

    func load() -> RuntimeVitalDBCurrentObservationRead {
        loadCurrentObservation()
    }

    static func live(
        paths _: RuntimePaths,
        fileStore _: RuntimeFileReading & RuntimeFileWriting = SystemRuntimeFileStore(),
        guestControlBaseURL: @escaping @Sendable () -> String? = {
            RuntimeControlClientConstants.Product.localGuestControlAPIBaseURL
        },
        guestControlGateway: @escaping @Sendable (String) throws -> any RuntimeGuestControlGateway = {
            try HTTPRuntimeGuestControlGateway(
                baseURL: $0,
                timeout: RuntimeControlClientConstants.Product.guestControlAPIStatusReadTimeoutSeconds
            )
        }
    ) -> RuntimeVitalDBCurrentObservationProvider {
        return RuntimeVitalDBCurrentObservationProvider {
            guard let baseURL = guestControlBaseURL()?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !baseURL.isEmpty else {
                return .unavailable(readIssues: ["guestControl=baseURLUnavailable"])
            }

            do {
                let read = try guestControlGateway(baseURL).latestVitalDBObservation()
                return read.asCurrentObservationRead()
            } catch {
                return .unavailable(readIssues: ["guestControl=\(error)"])
            }
        }
    }
}

private extension RuntimeGuestControlVitalDBObservationRead {
    func asCurrentObservationRead() -> RuntimeVitalDBCurrentObservationRead {
        switch state {
        case .loaded:
            guard let observation else {
                return .unavailable(readIssues: ["guestControl=loadedObservationMissing"])
            }
            return .loaded(
                observation,
                source: .guestControlAPI,
                readIssues: readError.map { ["guestControl=\($0)"] } ?? []
            )
        case .unavailable, .failed:
            return .unavailable(
                readIssues: [readError.map { "guestControl=\($0)" } ?? "guestControl=\(state.rawValue)"]
            )
        }
    }
}
