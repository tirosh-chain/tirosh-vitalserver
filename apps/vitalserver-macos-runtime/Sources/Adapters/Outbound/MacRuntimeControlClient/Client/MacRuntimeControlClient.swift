import Foundation
import Contracts
import RuntimeControl
import Application
import Errors

@MainActor
public struct MacRuntimeControlClient: RuntimeControlClient, RuntimeHostClient {
    public let capabilities = RuntimeControlCapabilities()

    private let releaseInfo: RuntimeReleaseInfo
    private let platformStateReader: PlatformStateReading
    private let operationStateReader: PlatformOperationStateReading
    private let observabilityReader: RuntimeObservabilityReading
    private let fileReader: RuntimeHostFileReading
    private let settingsReader: RuntimeSettingsReading
    private let commandWorker: MacRuntimeControlCommandWorker

    public init(
        releaseInfo: RuntimeReleaseInfo,
        operationLeaseReader: any RuntimeOperationLeaseReading,
        guestAddressProvider: any RuntimeGuestAddressProvider,
        vmLifecycleResourceReader: any RuntimeVMLifecycleResourceReading,
        hostSettingsReader: any RuntimeHostSettingsReading,
        commandWorker: MacRuntimeControlCommandWorker
    ) {
        self.init(
            releaseInfo: releaseInfo,
            platformStateReader: SystemPlatformStateReader(
                guestAddressProvider: guestAddressProvider,
                vmLifecycleResourceReader: vmLifecycleResourceReader
            ),
            operationStateReader: SystemPlatformOperationStateReader.live(
                operationLeaseReader: operationLeaseReader
            ),
            observabilityReader: SystemRuntimeObservabilityReader.live(
                paths: RuntimeObservabilityPaths(),
                guestAddressProvider: guestAddressProvider
            ),
            fileReader: SystemRuntimeHostFileReader(),
            settingsReader: SystemRuntimeSettingsReader(
                paths: RuntimeSettingsPaths(),
                fileStore: SystemRuntimeFileStore(),
                runCommand: ProcessRunner.runSync,
                hostSettingsReader: hostSettingsReader
            ),
            commandWorker: commandWorker
        )
    }

    public init(
        releaseInfo: RuntimeReleaseInfo,
        operationLeaseReader: any RuntimeOperationLeaseReading,
        guestAddressProvider: any RuntimeGuestAddressProvider,
        vmLifecycleResourceReader: any RuntimeVMLifecycleResourceReading,
        settingsReader: any RuntimeSettingsReading,
        commandWorker: MacRuntimeControlCommandWorker
    ) {
        self.init(
            releaseInfo: releaseInfo,
            platformStateReader: SystemPlatformStateReader(
                guestAddressProvider: guestAddressProvider,
                vmLifecycleResourceReader: vmLifecycleResourceReader
            ),
            operationStateReader: SystemPlatformOperationStateReader.live(
                operationLeaseReader: operationLeaseReader
            ),
            observabilityReader: SystemRuntimeObservabilityReader.live(
                paths: RuntimeObservabilityPaths(),
                guestAddressProvider: guestAddressProvider
            ),
            fileReader: SystemRuntimeHostFileReader(),
            settingsReader: settingsReader,
            commandWorker: commandWorker
        )
    }

    public init(
        releaseInfo: RuntimeReleaseInfo,
        platformStateReader: any PlatformStateReading,
        operationLeaseReader: any RuntimeOperationLeaseReading,
        guestAddressProvider: any RuntimeGuestAddressProvider,
        settingsReader: any RuntimeSettingsReading,
        commandWorker: MacRuntimeControlCommandWorker
    ) {
        self.init(
            releaseInfo: releaseInfo,
            platformStateReader: platformStateReader,
            operationStateReader: SystemPlatformOperationStateReader.live(
                operationLeaseReader: operationLeaseReader
            ),
            observabilityReader: SystemRuntimeObservabilityReader.live(
                paths: RuntimeObservabilityPaths(),
                guestAddressProvider: guestAddressProvider
            ),
            fileReader: SystemRuntimeHostFileReader(),
            settingsReader: settingsReader,
            commandWorker: commandWorker
        )
    }

    init(
        releaseInfo: RuntimeReleaseInfo,
        platformStateReader: PlatformStateReading = SystemPlatformStateReader(),
        operationStateReader: PlatformOperationStateReading = SystemPlatformOperationStateReader.live(),
        observabilityReader: RuntimeObservabilityReading = SystemRuntimeObservabilityReader.live(paths: RuntimeObservabilityPaths()),
        fileReader: RuntimeHostFileReading = SystemRuntimeHostFileReader(),
        settingsReader: RuntimeSettingsReading,
        commandWorker: MacRuntimeControlCommandWorker = MacRuntimeControlCommandWorker()
    ) {
        self.releaseInfo = releaseInfo
        self.platformStateReader = platformStateReader
        self.operationStateReader = operationStateReader
        self.observabilityReader = observabilityReader
        self.fileReader = fileReader
        self.settingsReader = settingsReader
        self.commandWorker = commandWorker
    }

    private static func livePlatformStateReader() -> PlatformStateReading {
        SystemPlatformStateReader(
            guestAddressProvider: RuntimeControlAPIGuestAddressProvider(),
            vmLifecycleResourceReader: RuntimeControlAPIVMLifecycleResourceReader()
        )
    }

    public func loadSettings() -> RuntimeSettings {
        settingsReader.load()
    }

    public func loadPlatformState(settings: RuntimeSettings) -> PlatformState {
        platformStateReader.loadPlatformState(settings: settings)
    }

    public func loadOperationState() -> PlatformOperationState {
        operationStateReader.loadOperationState()
    }

    public func loadHealthStatus(settings: RuntimeSettings) async -> PlatformState {
        await platformStateReader.loadHealthStatus(settings: settings)
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

    public func loadVitalDBBeds() -> RuntimeVitalBedHistory {
        observabilityReader.loadVitalDBBeds()
    }

    public func loadVitalDBRecorderSummaries() -> RuntimeVitalRecorderHistory {
        observabilityReader.loadVitalDBRecorderSummaries()
    }

    public func loadVitalDBRecorderActivityWindow(
        query: RuntimeVitalRecorderActivityWindowQuery
    ) -> RuntimeVitalRecorderActivityWindow {
        observabilityReader.loadVitalDBRecorderActivityWindow(query: query)
    }

    public func loadVitalDBRecorderVitalFiles(
        vrcode: String
    ) -> RuntimeVitalRecorderVitalFileHistory {
        observabilityReader.loadVitalDBRecorderVitalFiles(vrcode: vrcode)
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

    public func restartVMRuntime(applying settings: RuntimeSettings) async throws -> RuntimeCommandResult {
        try await commandWorker.restartVMRuntime(applying: settings)
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

    public func controlRuntimeProvider(
        _ action: RuntimeProviderCommandAction
    ) async throws -> RuntimeCommandResult {
        try await commandWorker.controlRuntimeProvider(action)
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

    public func runtimeCapabilities() async throws -> RuntimeCapabilities {
        try await commandWorker.runtimeCapabilities()
    }

    public func loadRuntimeProductSettings() async throws -> RuntimeProductSettingsRead {
        try await commandWorker.loadRuntimeProductSettings()
    }

    public func applyRuntimeProductSettings(
        _ settings: GuestRuntimeSettingsDocument
    ) async throws -> RuntimeGuestControlServiceOperation {
        try await commandWorker.applyRuntimeProductSettings(settings)
    }

    public func applyRuntimeAdminPassword(
        _ password: String
    ) async throws -> RuntimeGuestControlServiceOperation {
        try await commandWorker.applyRuntimeAdminPassword(password)
    }

    public func loadRuntimeRedisRelaySettings() async throws -> RuntimeRedisRelaySettingsRead {
        try await commandWorker.loadRuntimeRedisRelaySettings()
    }

    public func applyRuntimeRedisRelaySettings(
        _ settings: RuntimeRedisRelaySettingsApplyRequest
    ) async throws -> RuntimeGuestControlServiceOperation {
        try await commandWorker.applyRuntimeRedisRelaySettings(settings)
    }

    public func loadRuntimeOperationEvents(
        query: RuntimeOperationEventQuery
    ) async throws -> RuntimeOperationEventHistory {
        try await commandWorker.loadRuntimeOperationEvents(query: query)
    }

    public func guestServiceStatus(_ service: String) async throws -> RuntimeGuestControlServiceStatus {
        try await commandWorker.guestServiceStatus(service)
    }

    public func guestServiceResource(_ service: String) async throws -> RuntimeGuestServiceResource {
        try await commandWorker.guestServiceResource(service)
    }

    public func loadRedisRelayStatus() async throws -> RuntimeRedisRelayStatusReadResult {
        try await commandWorker.loadRedisRelayStatus()
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

    public func loadLabSessions() async throws -> RuntimeLabSessionList {
        try await commandWorker.loadLabSessions()
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

    public func hideVitalDBBeds(_ request: RuntimeVitalDBBedVisibilityRequest) async throws -> RuntimeVitalBedHistory {
        try await commandWorker.hideVitalDBBeds(request)
    }

    public func unhideVitalDBBeds(_ request: RuntimeVitalDBBedVisibilityRequest) async throws -> RuntimeVitalBedHistory {
        try await commandWorker.unhideVitalDBBeds(request)
    }

    public func deleteVitalDBBeds(_ request: RuntimeVitalDBBedVisibilityRequest) async throws -> RuntimeVitalBedHistory {
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

    public func finishLabSession(sessionId: String) async throws -> RuntimeLabSessionResponse {
        try await commandWorker.finishLabSession(sessionId: sessionId)
    }

    public func startLabRecorder(sessionId: String, recorderId: String) async throws -> RuntimeLabRecorderResponse {
        try await commandWorker.startLabRecorder(sessionId: sessionId, recorderId: recorderId)
    }

    public func stopLabRecorder(sessionId: String, recorderId: String) async throws -> RuntimeLabRecorderResponse {
        try await commandWorker.stopLabRecorder(sessionId: sessionId, recorderId: recorderId)
    }

    public func replayLabVitalFile(_ request: RuntimeLabVitalFileReplayRequest) async throws -> RuntimeLabSessionResponse {
        try await commandWorker.replayLabVitalFile(request)
    }

    public func uploadLabVitalFiles(
        _ sources: [RuntimeLabVitalFileUploadSource]
    ) async throws -> RuntimeLabVitalFileLibraryUploadResponse {
        try await commandWorker.uploadLabVitalFiles(sources)
    }

    public func exportLogs(to destination: URL) async throws -> RuntimeLogExportResult {
        try await commandWorker.exportLogs(to: destination)
    }

    public func loadReleaseInfo() async throws -> RuntimeReleaseInfo {
        releaseInfo
    }

    public func loadInstallInfo() -> RuntimeInstallInfo {
        let installed = InstalledRuntimePaths.defaultInstalled
        return RuntimeInstallInfo(
            appBundlePath: Bundle.main.bundlePath,
            packageIdentifier: RuntimeControlClientConstants.Product.packageIdentifier,
            runtimeHomePath: installed.runtimeHome.path,
            backupsPath: installed.backupsDirectory.path,
            redisBackupsPath: installed.redisBackupsDirectory.path,
            runtimeDataBackupsPath: installed.vitalServerHelperBackupsDirectory.path
        )
    }

}
