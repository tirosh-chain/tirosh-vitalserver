import Application
import Contracts
import Foundation
import RuntimeControl

struct RuntimeVitalDBGuestReadModelProvider {
    private let loadRecorderHistory: () -> RuntimeVitalRecorderHistory

    init(load: @escaping () -> RuntimeVitalRecorderHistory) {
        self.loadRecorderHistory = load
    }

    func load() -> RuntimeVitalRecorderHistory {
        loadRecorderHistory()
    }

    static func live(
        guestControlBaseURL: @escaping @Sendable () -> String?,
        guestControlGateway: @escaping @Sendable (String) throws -> any RuntimeVitalDBGuestControlGateway = {
            try HTTPRuntimeGuestControlGateway(
                baseURL: $0,
                timeout: RuntimeControlClientConstants.Product.guestControlAPIProductReadModelTimeoutSeconds
            )
        }
    ) -> RuntimeVitalDBGuestReadModelProvider {
        RuntimeVitalDBGuestReadModelProvider {
            guard let baseURL = guestControlBaseURL()?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !baseURL.isEmpty else {
                return .failed(readError: "guestControl=baseURLUnavailable")
            }

            do {
                let gateway = try guestControlGateway(baseURL)
                return try gateway.vitalDBRecorders()
            } catch {
                return .failed(readError: "guestControl=\(error)")
            }
        }
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
        guestControlBaseURL: @escaping @Sendable () -> String?,
        guestControlGateway: @escaping @Sendable (String) throws -> any RuntimeVitalDBGuestControlGateway = {
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
                return try gateway.vitalDBBeds()
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
        guestControlBaseURL: @escaping @Sendable () -> String?,
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
