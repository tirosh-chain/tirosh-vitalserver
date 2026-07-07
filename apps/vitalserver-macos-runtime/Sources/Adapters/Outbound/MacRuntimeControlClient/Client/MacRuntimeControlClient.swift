import Foundation
import Contracts
import RuntimeControl
import Application
import Errors

@MainActor
public struct MacRuntimeControlClient: RuntimeControlClient, RuntimeHostClient {
    public let capabilities = RuntimeControlCapabilities()

    private let releaseInfo: RuntimeReleaseInfo
    private let statusReader: RuntimeStatusReading
    private let operationStateReader: RuntimeOperationStateReading
    private let observabilityReader: RuntimeObservabilityReading
    private let fileReader: RuntimeHostFileReading
    private let settingsReader: RuntimeSettingsReading
    private let commandWorker: MacRuntimeControlCommandWorker

    public init(
        releaseInfo: RuntimeReleaseInfo
    ) {
        let paths = RuntimePaths()
        self.init(
            releaseInfo: releaseInfo,
            statusReader: SystemRuntimeStatusReader(paths: paths),
            operationStateReader: SystemRuntimeOperationStateReader.live(paths: paths),
            observabilityReader: SystemRuntimeObservabilityReader.live(paths: paths),
            fileReader: SystemRuntimeHostFileReader(),
            settingsReader: SystemRuntimeSettingsReader(),
            commandWorker: MacRuntimeControlCommandWorker()
        )
    }

    public init(
        releaseInfo: RuntimeReleaseInfo,
        commandWorker: MacRuntimeControlCommandWorker
    ) {
        let paths = RuntimePaths()
        self.init(
            releaseInfo: releaseInfo,
            statusReader: SystemRuntimeStatusReader(paths: paths),
            operationStateReader: SystemRuntimeOperationStateReader.live(paths: paths),
            observabilityReader: SystemRuntimeObservabilityReader.live(paths: paths),
            fileReader: SystemRuntimeHostFileReader(),
            settingsReader: SystemRuntimeSettingsReader(),
            commandWorker: commandWorker
        )
    }

    init(
        releaseInfo: RuntimeReleaseInfo,
        statusReader: RuntimeStatusReading = SystemRuntimeStatusReader(paths: RuntimePaths()),
        operationStateReader: RuntimeOperationStateReading = SystemRuntimeOperationStateReader.live(paths: RuntimePaths()),
        observabilityReader: RuntimeObservabilityReading = SystemRuntimeObservabilityReader.live(paths: RuntimePaths()),
        fileReader: RuntimeHostFileReading = SystemRuntimeHostFileReader(),
        settingsReader: RuntimeSettingsReading = SystemRuntimeSettingsReader(),
        commandWorker: MacRuntimeControlCommandWorker = MacRuntimeControlCommandWorker()
    ) {
        self.releaseInfo = releaseInfo
        self.statusReader = statusReader
        self.operationStateReader = operationStateReader
        self.observabilityReader = observabilityReader
        self.fileReader = fileReader
        self.settingsReader = settingsReader
        self.commandWorker = commandWorker
    }

    public func loadSettings() -> RuntimeSettings {
        settingsReader.load()
    }

    public func loadStatus(settings: RuntimeSettings) -> RuntimeStatus {
        statusReader.loadStatus(settings: settings)
    }

    public func loadOperationState(status: RuntimeStatus) -> RuntimeOperationState {
        operationStateReader.loadOperationState(status: status)
    }

    public func loadHealthStatus(settings: RuntimeSettings) async -> RuntimeStatus {
        await statusReader.loadHealthStatus(settings: settings)
    }

    public func loadRuntimeEvents(limit: Int) -> RuntimeEventHistory {
        observabilityReader.loadRuntimeEvents(limit: limit)
    }

    public func loadRuntimeEvents(query: RuntimeEventQuery) -> RuntimeEventHistory {
        observabilityReader.loadRuntimeEvents(query: query)
    }

    public func loadVitalDBObservationSnapshot() -> RuntimeVitalDBObservationSnapshot {
        observabilityReader.loadVitalDBObservationSnapshot()
    }

    public func loadVitalDBRecorders() -> RuntimeVitalRecorderHistory {
        observabilityReader.loadVitalDBRecorders()
    }

    public func loadVitalDBRecorderSummaries() -> RuntimeVitalRecorderHistory {
        observabilityReader.loadVitalDBRecorderSummaries()
    }

    public func loadVitalDBRecorderActivityWindow(
        query: RuntimeVitalRecorderActivityWindowQuery
    ) -> RuntimeVitalRecorderActivityWindow {
        observabilityReader.loadVitalDBRecorderActivityWindow(query: query)
    }

    public func loadVitalDBRelationships() -> RuntimeVitalRelationshipHistory {
        observabilityReader.loadVitalDBRelationships()
    }

    public func loadBackups(latestBackupPath: String?) throws -> [RuntimeBackup] {
        try fileReader.backups(latestBackupPath: latestBackupPath)
    }

    public func loadRedisBackups() throws -> [RuntimeBackup] {
        try fileReader.redisBackups()
    }

    public func loadRuntimeDataBackups() throws -> [RuntimeBackup] {
        try fileReader.runtimeDataBackups()
    }

    public func updateBundleSummaryResult(url: URL) -> RuntimeHostTextReadResult {
        fileReader.updateBundleSummaryResult(url: url)
    }

    public func logTextResult(sourceID: RuntimeLogSource, lineLimit: Int) -> RuntimeHostTextReadResult {
        fileReader.logTextResult(sourceID: sourceID, lineLimit: lineLimit)
    }

    public func loadLogTextResult(sourceID: RuntimeLogSource, lineLimit: Int) async -> RuntimeHostTextReadResult {
        let fileReader = fileReader
        return await Task.detached(priority: .utility) {
            fileReader.logTextResult(
                sourceID: sourceID,
                lineLimit: lineLimit
            )
        }.value
    }

    public func preferredLogsPath() -> String {
        fileReader.preferredLogsPath()
    }

    public func vitalFileFolders(root: String) throws -> [VitalFilesFolder] {
        try fileReader.vitalFileFolders(root: root)
    }

    public func verifyUpdateBundle(url: URL) async throws -> RuntimeCommandResult {
        try await commandWorker.verifyUpdateBundle(url: url)
    }

    public func uninstallRuntime(mode: RuntimeUninstallMode) async throws -> RuntimeCommandResult {
        try await commandWorker.uninstallRuntime(mode: mode)
    }

    public func applySettings(_ settings: RuntimeSettings) async throws -> RuntimeCommandResult {
        try await commandWorker.applySettings(settings)
    }

    public func applyUpdateBundle(url: URL) async throws -> RuntimeCommandResult {
        try await commandWorker.applyUpdateBundle(url: url)
    }

    public func rollbackRuntime(backupURL: URL) async throws -> RuntimeCommandResult {
        try await commandWorker.rollbackRuntime(backupURL: backupURL)
    }

    public func restoreRedisBackup(backupURL: URL) async throws -> RuntimeCommandResult {
        try await commandWorker.restoreRedisBackup(backupURL: backupURL)
    }

    public func restoreRuntimeDataBackup(backupURL: URL) async throws -> RuntimeCommandResult {
        try await commandWorker.restoreRuntimeDataBackup(backupURL: backupURL)
    }

    public func deleteBackup(url: URL) async throws -> RuntimeCommandResult {
        try await commandWorker.deleteBackup(url: url)
    }

    public func repairProxy() async throws -> RuntimeCommandResult {
        try await commandWorker.repairProxy()
    }

    public func repairDatastore() async throws -> RuntimeCommandResult {
        try await commandWorker.repairDatastore()
    }

    public func repairVMDisk() async throws -> RuntimeCommandResult {
        try await commandWorker.repairVMDisk()
    }

    public func repairRuntimeServices() async throws -> RuntimeCommandResult {
        try await commandWorker.repairRuntimeServices()
    }

    public func createRedisBackup() async throws -> RuntimeCommandResult {
        try await commandWorker.createRedisBackup()
    }

    public func createRuntimeDataBackup() async throws -> RuntimeCommandResult {
        try await commandWorker.createRuntimeDataBackup()
    }

    public func listGuestServices() async throws -> RuntimeGuestControlServiceList {
        try await commandWorker.listGuestServices()
    }

    public func guestStackStatus() async throws -> RuntimeGuestControlStackStatus {
        try await commandWorker.guestStackStatus()
    }

    public func guestServiceStatus(_ service: String) async throws -> RuntimeGuestControlServiceStatus {
        try await commandWorker.guestServiceStatus(service)
    }

    public func startGuestService(_ request: RuntimeGuestServiceControlRequest) async throws -> RuntimeGuestControlServiceOperation {
        try await commandWorker.startGuestService(request)
    }

    public func stopGuestService(_ request: RuntimeGuestServiceControlRequest) async throws -> RuntimeGuestControlServiceOperation {
        try await commandWorker.stopGuestService(request)
    }

    public func restartGuestService(_ request: RuntimeGuestServiceRestartRequest) async throws -> RuntimeGuestControlServiceOperation {
        try await commandWorker.restartGuestService(request)
    }

    public func loadLabScenarios() async throws -> RuntimeLabScenarioList {
        try await commandWorker.loadLabScenarios()
    }

    public func loadLabVitalFiles() async throws -> RuntimeLabVitalFileList {
        try await commandWorker.loadLabVitalFiles()
    }

    public func loadLabBeds() async throws -> RuntimeLabBedList {
        try await commandWorker.loadLabBeds()
    }

    public func loadLabRecorders() async throws -> RuntimeLabRecorderList {
        try await commandWorker.loadLabRecorders()
    }

    public func createLabBeds(_ request: RuntimeLabBedCreateRequest) async throws -> RuntimeLabBedList {
        try await commandWorker.createLabBeds(request)
    }

    public func deleteLabBeds(_ request: RuntimeLabBedDeleteRequest) async throws -> RuntimeLabBedList {
        try await commandWorker.deleteLabBeds(request)
    }

    public func resetLabBeds() async throws -> RuntimeLabBedList {
        try await commandWorker.resetLabBeds()
    }

    public func createLabRecorders(_ request: RuntimeLabRecorderCreateRequest) async throws -> RuntimeLabRecorderList {
        try await commandWorker.createLabRecorders(request)
    }

    public func deleteLabRecorders(_ request: RuntimeLabRecorderDeleteRequest) async throws -> RuntimeLabRecorderList {
        try await commandWorker.deleteLabRecorders(request)
    }

    public func resetLabRecorders() async throws -> RuntimeLabRecorderList {
        try await commandWorker.resetLabRecorders()
    }

    public func hideVitalDBRecorders(_ request: RuntimeVitalDBRecorderVisibilityRequest) async throws -> RuntimeVitalRecorderHistory {
        try await commandWorker.hideVitalDBRecorders(request)
    }

    public func unhideVitalDBRecorders(_ request: RuntimeVitalDBRecorderVisibilityRequest) async throws -> RuntimeVitalRecorderHistory {
        try await commandWorker.unhideVitalDBRecorders(request)
    }

    public func deleteVitalDBRecorders(_ request: RuntimeVitalDBRecorderVisibilityRequest) async throws -> RuntimeVitalRecorderHistory {
        try await commandWorker.deleteVitalDBRecorders(request)
    }

    public func hideVitalDBBeds(_ request: RuntimeVitalDBBedVisibilityRequest) async throws -> RuntimeVitalRecorderHistory {
        try await commandWorker.hideVitalDBBeds(request)
    }

    public func unhideVitalDBBeds(_ request: RuntimeVitalDBBedVisibilityRequest) async throws -> RuntimeVitalRecorderHistory {
        try await commandWorker.unhideVitalDBBeds(request)
    }

    public func deleteVitalDBBeds(_ request: RuntimeVitalDBBedVisibilityRequest) async throws -> RuntimeVitalRecorderHistory {
        try await commandWorker.deleteVitalDBBeds(request)
    }

    public func createLabSession(_ request: RuntimeLabSessionCreateRequest) async throws -> RuntimeLabSessionResponse {
        try await commandWorker.createLabSession(request)
    }

    public func loadLabSession(sessionId: String) async throws -> RuntimeLabSessionResponse {
        try await commandWorker.loadLabSession(sessionId: sessionId)
    }

    public func startLabSession(sessionId: String) async throws -> RuntimeLabSessionResponse {
        try await commandWorker.startLabSession(sessionId: sessionId)
    }

    public func stopLabSession(sessionId: String) async throws -> RuntimeLabSessionResponse {
        try await commandWorker.stopLabSession(sessionId: sessionId)
    }

    public func replayLabVitalFile(_ request: RuntimeLabVitalFileReplayRequest) async throws -> RuntimeLabSessionResponse {
        try await commandWorker.replayLabVitalFile(request)
    }

    public func uploadLabVitalFile(_ request: RuntimeLabVitalFileUploadRequest) async throws -> RuntimeLabVitalFileUploadResponse {
        try await commandWorker.uploadLabVitalFile(request)
    }

    public func exportLogs(to destination: URL) async throws -> RuntimeLogExportResult {
        try await commandWorker.exportLogs(to: destination)
    }

    public func loadReleaseInfo() async throws -> RuntimeReleaseInfo {
        releaseInfo
    }

    public func loadInstallInfo() -> RuntimeInstallInfo {
        RuntimeInstallInfo(
            appBundlePath: Bundle.main.bundlePath,
            packageIdentifier: RuntimeControlClientConstants.Product.packageIdentifier,
            runtimeHomePath: RuntimeControlClientConstants.Paths.vmHome,
            backupsPath: RuntimeControlClientConstants.Paths.backups,
            redisBackupsPath: RuntimeControlClientConstants.Paths.redisBackups,
            runtimeDataBackupsPath: RuntimeControlClientConstants.Paths.runtimeDataBackups
        )
    }

}
