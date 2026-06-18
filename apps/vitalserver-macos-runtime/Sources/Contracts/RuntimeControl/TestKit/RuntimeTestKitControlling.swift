import Foundation
import Errors

@MainActor
public protocol RuntimeTestKitControlling {
    func loadTestKitStatus() async -> RuntimeTestKitStatus
    func createTestKitBeds(_ request: RuntimeTestKitCreateBedsRequest) async throws -> [RuntimeTestKitBed]
    func deleteTestKitBeds(_ request: RuntimeTestKitDeleteBedsRequest) async throws -> [RuntimeTestKitBed]
    func resetTestKitBeds() async throws -> [RuntimeTestKitBed]
    func startVirtualRecorders(_ request: RuntimeTestKitVirtualRecorderStartRequest) async throws -> RuntimeTestKitSession
    func pauseVirtualRecorders(sessionID: String?) async throws -> RuntimeTestKitSession?
    func resumeVirtualRecorders(sessionID: String?) async throws -> RuntimeTestKitSession?
    func stopVirtualRecorders(sessionID: String?) async throws -> RuntimeTestKitSession?
    func restartVirtualRecorders(sessionID: String?, bedRoomNames: [String]) async throws -> RuntimeTestKitSession?
    func deleteVirtualRecorders(sessionID: String?) async throws -> RuntimeTestKitSession?
    func deleteVirtualRecorder(vrcode: String) async throws -> RuntimeTestKitRecorderDeletion
    func resetVirtualRecorders() async throws -> RuntimeTestKitStatus
}

@MainActor
public protocol RuntimeTestKitVitalFileUploading {
    func uploadVitalFiles(
        _ request: RuntimeTestKitVitalFileUploadRequest
    ) async throws -> RuntimeTestKitVitalFileUploadSummary
}
