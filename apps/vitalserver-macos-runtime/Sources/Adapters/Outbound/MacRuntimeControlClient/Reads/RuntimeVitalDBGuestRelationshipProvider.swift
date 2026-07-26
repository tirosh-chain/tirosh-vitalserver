import Application
import Contracts
import RuntimeControl

struct RuntimeVitalDBGuestRelationshipProvider {
    private let loadRelationships: () -> RuntimeVitalRelationshipHistory
    private let loadRelationshipsAsync: () async -> RuntimeVitalRelationshipHistory

    init(load: @escaping () -> RuntimeVitalRelationshipHistory) {
        self.loadRelationships = load
        self.loadRelationshipsAsync = { load() }
    }

    init(
        load: @escaping () -> RuntimeVitalRelationshipHistory,
        loadAsync: @escaping () async -> RuntimeVitalRelationshipHistory
    ) {
        self.loadRelationships = load
        self.loadRelationshipsAsync = loadAsync
    }

    func load() -> RuntimeVitalRelationshipHistory {
        loadRelationships()
    }

    func loadAsync() async -> RuntimeVitalRelationshipHistory {
        await loadRelationshipsAsync()
    }

    static func live(
        guestControlBaseURL: @escaping @Sendable () -> String?,
        guestControlGateway: @escaping @Sendable (String) throws -> any RuntimeGuestControlGateway = {
            try HTTPRuntimeGuestControlGateway(
                baseURL: $0,
                timeout: RuntimeControlClientConstants.Product.guestControlAPIProductReadModelTimeoutSeconds
            )
        }
    ) -> RuntimeVitalDBGuestRelationshipProvider {
        let load: () -> RuntimeVitalRelationshipHistory = {
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
        let loadAsync: () async -> RuntimeVitalRelationshipHistory = {
            guard let baseURL = guestControlBaseURL()?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !baseURL.isEmpty else {
                return .failed(readError: "guestControl=baseURLUnavailable")
            }

            do {
                let gateway = try guestControlGateway(baseURL)
                return RuntimeVitalDBRelationshipHistoryAssembler.makeHistory(
                    read: try await gateway.vitalDBRelationshipsAsync()
                )
            } catch is CancellationError {
                return .failed(readError: "guestControl=requestCancelled")
            } catch {
                return .failed(readError: "guestControl=\(error)")
            }
        }
        return RuntimeVitalDBGuestRelationshipProvider(
            load: load,
            loadAsync: loadAsync
        )
    }

    static func unavailable() -> RuntimeVitalDBGuestRelationshipProvider {
        RuntimeVitalDBGuestRelationshipProvider {
            RuntimeVitalRelationshipHistory.failed(
                readError: "Guest VitalDB relationship read model is unavailable."
            )
        }
    }

}
