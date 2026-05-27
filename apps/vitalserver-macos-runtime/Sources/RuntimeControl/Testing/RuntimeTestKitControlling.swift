import Foundation

@MainActor
public protocol RuntimeTestKitControlling {
    func loadTestKitStatus() async -> RuntimeTestKitStatus
    func startVirtualRecorders(_ request: RuntimeTestKitVirtualRecorderStartRequest) async throws -> RuntimeTestKitSession
    func stopVirtualRecorders(sessionID: String?) async throws -> RuntimeTestKitSession?
    func deleteVirtualRecorders(sessionID: String?) async throws -> RuntimeTestKitSession?
    func resetVirtualRecorders() async throws -> RuntimeTestKitStatus
}
