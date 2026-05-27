import Foundation

@MainActor
public protocol RuntimeTestKitControlling {
    func loadTestKitStatus() async -> RuntimeTestKitStatus
    func startVirtualRecorders(_ request: RuntimeTestKitVirtualRecorderStartRequest) async throws -> RuntimeTestKitSession
    func stopVirtualRecorders(sessionID: String?) async throws -> RuntimeTestKitSession?
}
