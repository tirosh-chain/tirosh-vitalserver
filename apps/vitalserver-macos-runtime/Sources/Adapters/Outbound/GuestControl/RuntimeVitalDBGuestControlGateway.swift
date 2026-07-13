import Contracts
import RuntimeControl

protocol RuntimeVitalDBGuestControlGateway {
    func vitalDBRecorders() throws -> RuntimeVitalRecorderHistory
    func hideVitalDBRecorders(
        _ request: RuntimeVitalDBRecorderVisibilityRequest
    ) throws -> RuntimeVitalRecorderHistory
    func unhideVitalDBRecorders(
        _ request: RuntimeVitalDBRecorderVisibilityRequest
    ) throws -> RuntimeVitalRecorderHistory
    func deleteVitalDBRecorders(
        _ request: RuntimeVitalDBRecorderVisibilityRequest
    ) throws -> RuntimeVitalRecorderHistory
    func vitalDBBeds() throws -> RuntimeVitalBedHistory
    func hideVitalDBBeds(
        _ request: RuntimeVitalDBBedVisibilityRequest
    ) throws -> RuntimeVitalBedHistory
    func unhideVitalDBBeds(
        _ request: RuntimeVitalDBBedVisibilityRequest
    ) throws -> RuntimeVitalBedHistory
    func deleteVitalDBBeds(
        _ request: RuntimeVitalDBBedVisibilityRequest
    ) throws -> RuntimeVitalBedHistory
}

enum RuntimeVitalDBGuestControlGatewayCapabilityError: Error {
    case unavailable(String)
}

extension RuntimeVitalDBGuestControlGateway {
    func hideVitalDBRecorders(
        _: RuntimeVitalDBRecorderVisibilityRequest
    ) throws -> RuntimeVitalRecorderHistory {
        throw RuntimeVitalDBGuestControlGatewayCapabilityError.unavailable(
            "vitaldb-recorders-hide"
        )
    }

    func unhideVitalDBRecorders(
        _: RuntimeVitalDBRecorderVisibilityRequest
    ) throws -> RuntimeVitalRecorderHistory {
        throw RuntimeVitalDBGuestControlGatewayCapabilityError.unavailable(
            "vitaldb-recorders-unhide"
        )
    }

    func deleteVitalDBRecorders(
        _: RuntimeVitalDBRecorderVisibilityRequest
    ) throws -> RuntimeVitalRecorderHistory {
        throw RuntimeVitalDBGuestControlGatewayCapabilityError.unavailable(
            "vitaldb-recorders-delete"
        )
    }

    func hideVitalDBBeds(
        _: RuntimeVitalDBBedVisibilityRequest
    ) throws -> RuntimeVitalBedHistory {
        throw RuntimeVitalDBGuestControlGatewayCapabilityError.unavailable(
            "vitaldb-beds-hide"
        )
    }

    func unhideVitalDBBeds(
        _: RuntimeVitalDBBedVisibilityRequest
    ) throws -> RuntimeVitalBedHistory {
        throw RuntimeVitalDBGuestControlGatewayCapabilityError.unavailable(
            "vitaldb-beds-unhide"
        )
    }

    func deleteVitalDBBeds(
        _: RuntimeVitalDBBedVisibilityRequest
    ) throws -> RuntimeVitalBedHistory {
        throw RuntimeVitalDBGuestControlGatewayCapabilityError.unavailable(
            "vitaldb-beds-delete"
        )
    }
}
