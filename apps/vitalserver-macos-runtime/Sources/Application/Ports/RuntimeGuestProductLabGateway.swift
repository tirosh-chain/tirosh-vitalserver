import Contracts

public protocol RuntimeGuestProductLabGateway {
    func labScenarios() throws -> RuntimeLabScenarioList
    func labVitalFiles() throws -> RuntimeLabVitalFileList
    func labBeds() throws -> RuntimeLabBedList
    func labRecorders() throws -> RuntimeLabRecorderList
    func createLabBeds(_ request: RuntimeLabBedCreateRequest) throws -> RuntimeLabBedList
    func deleteLabBeds(_ request: RuntimeLabBedDeleteRequest) throws -> RuntimeLabBedList
    func resetLabBeds() throws -> RuntimeLabBedList
    func createLabRecorders(_ request: RuntimeLabRecorderCreateRequest) throws -> RuntimeLabRecorderList
    func deleteLabRecorders(_ request: RuntimeLabRecorderDeleteRequest) throws -> RuntimeLabRecorderList
    func resetLabRecorders() throws -> RuntimeLabRecorderList
    func createLabSession(
        _ request: RuntimeLabSessionCreateRequest
    ) throws -> RuntimeLabSessionResponse
    func labSession(_ sessionId: String) throws -> RuntimeLabSessionResponse
    func startLabSession(_ sessionId: String) throws -> RuntimeLabSessionResponse
    func stopLabSession(_ sessionId: String) throws -> RuntimeLabSessionResponse
    func replayLabVitalFile(
        _ request: RuntimeLabVitalFileReplayRequest
    ) throws -> RuntimeLabSessionResponse
    func uploadLabVitalFile(
        _ request: RuntimeLabVitalFileUploadRequest
    ) throws -> RuntimeLabVitalFileUploadResponse
}
