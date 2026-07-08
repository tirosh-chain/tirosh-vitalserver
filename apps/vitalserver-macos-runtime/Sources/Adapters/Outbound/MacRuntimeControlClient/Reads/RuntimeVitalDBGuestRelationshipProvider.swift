import Application
import Contracts
import RuntimeControl

struct RuntimeVitalDBGuestRelationshipProvider {
    private let loadRelationships: () -> RuntimeVitalRelationshipHistory

    init(load: @escaping () -> RuntimeVitalRelationshipHistory) {
        self.loadRelationships = load
    }

    func load() -> RuntimeVitalRelationshipHistory {
        loadRelationships()
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
    ) -> RuntimeVitalDBGuestRelationshipProvider {
        RuntimeVitalDBGuestRelationshipProvider {
            guard let baseURL = guestControlBaseURL()?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !baseURL.isEmpty else {
                return .failed(readError: "guestControl=baseURLUnavailable")
            }

            do {
                let gateway = try guestControlGateway(baseURL)
                return Self.makeHistory(try gateway.vitalDBRelationships())
            } catch {
                return .failed(readError: "guestControl=\(error)")
            }
        }
    }

    static func unavailable() -> RuntimeVitalDBGuestRelationshipProvider {
        RuntimeVitalDBGuestRelationshipProvider {
            RuntimeVitalRelationshipHistory.failed(
                readError: "Guest VitalDB relationship read model is unavailable."
            )
        }
    }

    private static func makeHistory(
        _ read: RuntimeGuestControlVitalDBRelationshipRead
    ) -> RuntimeVitalRelationshipHistory {
        switch read.state {
        case .loaded:
            return RuntimeVitalRelationshipHistory(
                assignments: read.assignments,
                events: read.events,
                state: .loaded,
                readError: read.readError
            )
        case .partiallyLoaded:
            return RuntimeVitalRelationshipHistory(
                assignments: read.assignments,
                events: read.events,
                state: .partiallyLoaded,
                readError: read.readError
            )
        case .readFailed:
            return RuntimeVitalRelationshipHistory(
                assignments: read.assignments,
                events: read.events,
                state: .readFailed,
                readError: read.readError ?? "Guest VitalDB relationship read model failed."
            )
        case .unavailable, .failed:
            return .failed(
                readError: read.readError ?? "Guest VitalDB relationship read model is \(read.state.rawValue)."
            )
        }
    }
}
