import Contracts

/// Delivers Guest-owned maintenance operation state to an inbound boundary.
///
/// The result is intentionally the Guest operation document itself so callers
/// can preserve an accepted or failed Guest operation without translating it
/// into a Host command result.
public protocol RuntimeGuestMaintenanceOperationClient: Sendable {
    func requestDatastoreRepair() async throws -> RuntimeGuestControlServiceOperation
}
