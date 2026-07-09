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
                return RuntimeVitalDBRelationshipHistoryAssembler.makeHistory(
                    read: try gateway.vitalDBRelationships()
                )
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

}
