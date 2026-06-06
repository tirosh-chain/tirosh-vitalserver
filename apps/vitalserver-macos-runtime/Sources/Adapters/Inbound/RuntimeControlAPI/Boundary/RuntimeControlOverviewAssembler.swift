import Contracts
import RuntimeControl
import Errors

@MainActor
struct RuntimeControlOverviewAssembler {
    let handler: any RuntimeControlAPIReadHandler

    func load() async throws -> RuntimeControlOverview {
        var status = try await handler.loadStatus()
        let vitalDBObservationSnapshot = try await handler.loadVitalDBObservationSnapshot()
        let vitalDBObservation = vitalDBObservationSnapshot.observation
        status.vitalDBObservation = vitalDBObservation ?? status.vitalDBObservation
        return try await RuntimeControlOverview(
            status: status,
            settings: handler.loadSettings(),
            release: handler.loadReleaseInfo(),
            install: handler.loadInstallInfo(),
            vitalDBObservation: vitalDBObservation,
            vitalDBObservationSnapshot: vitalDBObservationSnapshot
        )
    }
}
