import Contracts

public protocol RuntimeGuestProductLabGateway {
    func labScenarios() throws -> RuntimeLabScenarioList
    func labVitalFiles() throws -> RuntimeLabVitalFileList
    func labBeds() throws -> RuntimeLabBedList
    func labRecorders() throws -> RuntimeLabRecorderList
    func labSessions() throws -> RuntimeLabSessionList
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
    func startLabRecorder(sessionId: String, recorderId: String) throws -> RuntimeLabRecorderResponse
    func stopLabRecorder(sessionId: String, recorderId: String) throws -> RuntimeLabRecorderResponse
    func replayLabVitalFile(
        _ request: RuntimeLabVitalFileReplayRequest
    ) throws -> RuntimeLabSessionResponse
}

public extension RuntimeGuestProductLabGateway {
    func labSessions() throws -> RuntimeLabSessionList {
        RuntimeLabSessionList.unavailable(
            readError: "Product Lab session collection is unavailable."
        )
    }

    func startLabRecorder(
        sessionId: String,
        recorderId: String
    ) throws -> RuntimeLabRecorderResponse {
        RuntimeLabRecorderResponse.unavailable(
            readError: "Product Lab recorder control is unavailable."
        )
    }

    func stopLabRecorder(
        sessionId: String,
        recorderId: String
    ) throws -> RuntimeLabRecorderResponse {
        RuntimeLabRecorderResponse.unavailable(
            readError: "Product Lab recorder control is unavailable."
        )
    }
}
