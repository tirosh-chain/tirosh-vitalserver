import Contracts

public protocol RuntimeGuestProductServiceCommandControlling: Sendable {
    func startService(
        _ service: String,
        gateway: RuntimeGuestControlGateway
    ) throws -> RuntimeGuestControlServiceOperation

    func stopService(
        _ service: String,
        gateway: RuntimeGuestControlGateway
    ) throws -> RuntimeGuestControlServiceOperation

    func restartService(
        _ service: String,
        gateway: RuntimeGuestControlGateway
    ) throws -> RuntimeGuestControlServiceOperation
}
