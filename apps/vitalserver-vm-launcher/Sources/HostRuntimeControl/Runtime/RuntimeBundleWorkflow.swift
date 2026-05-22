import CryptoKit
import Foundation
import HostRuntimeInfrastructure
import RuntimeCore

struct RuntimeBundleWorkflow {
    let installedPaths: InstalledRuntimePaths
    let bundlesDirectory: URL
    let backupsDirectory: URL
    let logsDirectory: URL
    let rootfsBase: URL
    let vmDisk: URL
    let fileStore: RuntimeFileStore
    let runtimeHealthSnapshot: () -> RuntimeHealthSnapshot
    let rotateRuntimeLogs: () throws -> Void
    let rollback: (URL?) throws -> Void
    let startRuntimeServices: (RuntimeServiceRestartPolicy) throws -> Void
    let stopRuntimeServices: () throws -> Void
    let isLaunchdLoaded: (String) -> Bool
    let createBackup: (String) throws -> URL
    let writeRuntimeStatus: (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void
    let writeRuntimeProgress: (RuntimeStepExecutionEvent) throws -> Void
    let pruneOldRuntimeArtifacts: () throws -> Void
    let reasonText: ([RuntimeFailureReason]) -> String
    let requireFreeSpace: (URL, UInt64, RuntimeOperation) throws -> Void
    let runProcess: (String, [String]) -> RuntimeProcessResult
    let runRequired: (String, [String]) throws -> Void
    let runProcessToFile: (String, [String], URL) throws -> Void
    let replaceFile: (URL, URL) throws -> Void
    let writeRuntimeVersion: (String, URL) throws -> Void
    let refreshCloudInitSeedIfNeeded: (UpdateBundleManifest) throws -> Void
    let activateGuestUpdateIfNeeded: (UpdateBundleManifest) throws -> Void
    let waitForHealth: (RuntimeServiceRestartPolicy) throws -> Void
    let log: (String) -> Void

    func verifyBundle(_ bundleURL: URL) throws {
        log("bundle verification started path=\(bundleURL.path)")
        let materialized = try materializeBundleInput(bundleURL)
        defer { materialized.cleanup?() }
        try verifyBundleDirectory(materialized.bundleURL, sourceURL: bundleURL)
    }

    @discardableResult
    func stageBundle(_ bundleURL: URL) throws -> URL {
        log("bundle stage started source=\(bundleURL.path)")
        let materialized = try materializeBundleInput(bundleURL)
        defer { materialized.cleanup?() }
        try verifyBundleDirectory(materialized.bundleURL, sourceURL: bundleURL)
        let manifest = try loadManifest(materialized.bundleURL.appendingPathComponent(Constants.Bundle.manifest))
        let destination = bundlesDirectory.appendingPathComponent("update-bundle-\(manifest.version)")
        let bundleSize = try directorySize(materialized.bundleURL)

        try fileStore.createDirectory(at: bundlesDirectory, withIntermediateDirectories: true)
        if fileExists(destination) || directoryExists(destination) {
            log("removing existing staged bundle path=\(destination.path)")
            try fileStore.removeItem(at: destination)
        }
        try requireFreeSpace(
            bundlesDirectory,
            bundleSize + compressedBundleSize(bundleURL) + Constants.Runtime.updateFreeSpaceMarginBytes,
            .stageBundle
        )
        log(
            "copying bundle to managed storage source=\(materialized.bundleURL.path) destination=\(destination.path) size=\(formatBytes(bundleSize))"
        )
        try fileStore.copyItem(at: materialized.bundleURL, to: destination)
        log("bundle stage completed destination=\(destination.path)")
        print("bundle staged: \(destination.path)")
        return destination
    }

    func applyBundle(_ bundleURL: URL) throws {
        try runtimeApplyBundleRunner().run(bundleURL: bundleURL)
        log("mutable VM disk preserved path=\(vmDisk.path)")
    }

    private func verifyBundleDirectory(_ bundleURL: URL, sourceURL: URL) throws {
        let manifestURL = bundleURL.appendingPathComponent(Constants.Bundle.manifest)
        let checksumsURL = bundleURL.appendingPathComponent(Constants.Bundle.checksums)
        let signatureURL = bundleURL.appendingPathComponent(Constants.Bundle.signature)

        guard directoryExists(bundleURL) else {
            throw LauncherError.missingFile(bundleURL.path)
        }
        for url in [manifestURL, checksumsURL, signatureURL] {
            guard fileExists(url) else {
                throw LauncherError.missingFile(url.path)
            }
        }

        let manifest = try loadManifest(manifestURL)
        let plan = try makeBundleVerificationPlan(manifest)
        log(
            "bundle manifest loaded version=\(manifest.version) runtimeVersion=\(manifest.runtimeVersion) artifacts=\(manifest.artifacts.count) migrations=\(manifest.migrations.count)"
        )

        let checksumMap = try loadChecksums(checksumsURL)
        for (artifact, fileVerification) in zip(manifest.artifacts, plan.artifactFiles) {
            let artifactURL = bundleURL.appendingPathComponent(fileVerification.name)
            guard fileExists(artifactURL) else {
                throw LauncherError.missingFile(artifactURL.path)
            }

            log(
                "verifying artifact type=\(artifact.type.rawValue) name=\(artifact.name) size=\(formatBytes(bundleItemSize(artifact.size)))"
            )
            try verifyDigestedFile(
                artifactURL,
                fileVerification: fileVerification,
                checksumMap: checksumMap
            )
            try validateUpdateArtifactPayload(artifact, source: artifactURL)
        }

        for (migration, fileVerification) in zip(manifest.migrations, plan.migrationFiles) {
            let migrationURL = bundleURL.appendingPathComponent(fileVerification.checksumKey)
            guard fileExists(migrationURL) else {
                throw LauncherError.missingFile(migrationURL.path)
            }

            log("verifying migration name=\(migration.name) size=\(formatBytes(bundleItemSize(migration.size)))")
            try verifyDigestedFile(
                migrationURL,
                fileVerification: fileVerification,
                checksumMap: checksumMap
            )
        }

        log("bundle verification completed path=\(sourceURL.path)")
        print("bundle verified: \(sourceURL.path)")
    }

    private struct MaterializedBundleInput {
        let bundleURL: URL
        let cleanup: (() -> Void)?
    }

    private func materializeBundleInput(_ bundleURL: URL) throws -> MaterializedBundleInput {
        if directoryExists(bundleURL) {
            return MaterializedBundleInput(bundleURL: bundleURL, cleanup: nil)
        }
        guard fileExists(bundleURL), isUpdateBundleArchive(bundleURL) else {
            throw LauncherError.missingFile(bundleURL.path)
        }

        let temporaryRoot = fileStore.temporaryDirectory
            .appendingPathComponent("tirosh-update-bundle-\(UUID().uuidString)", isDirectory: true)
        try fileStore.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        let extractedBundle = try extractBundleArchive(bundleURL, to: temporaryRoot)
        return MaterializedBundleInput(
            bundleURL: extractedBundle,
            cleanup: { try? fileStore.removeItem(at: temporaryRoot) }
        )
    }

    private func extractBundleArchive(_ archiveURL: URL, to temporaryRoot: URL) throws -> URL {
        let listResult = runProcess(Constants.Commands.tar, ["-tzf", archiveURL.path])
        guard listResult.exitCode == 0 else {
            let stderr = listResult.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if !stderr.isEmpty {
                log("bundle archive list failed stderr=\(stderr)")
            }
            throw LauncherError.bundleVerificationFailed("invalid update bundle archive: \(archiveURL.path)")
        }

        let rootName = try validateBundleArchiveEntries(listResult.stdout)
        try validateBundleArchiveEntryTypes(archiveURL)
        try runRequired(Constants.Commands.tar, ["-xzf", archiveURL.path, "-C", temporaryRoot.path])
        let extractedBundle = temporaryRoot.appendingPathComponent(rootName, isDirectory: true)
        guard directoryExists(extractedBundle) else {
            throw LauncherError.missingFile(extractedBundle.path)
        }
        log("bundle archive extracted source=\(archiveURL.path) destination=\(extractedBundle.path)")
        return extractedBundle
    }

    private func validateBundleArchiveEntries(_ output: String) throws -> String {
        let entries = output.split(whereSeparator: \.isNewline).map(String.init)
        guard !entries.isEmpty else {
            throw LauncherError.bundleVerificationFailed("empty update bundle archive")
        }

        var rootName: String?
        for entry in entries {
            guard !entry.hasPrefix("/"), !entry.contains("\\") else {
                throw LauncherError.bundleVerificationFailed("unsafe update bundle archive path: \(entry)")
            }
            let components = entry
                .split(separator: "/", omittingEmptySubsequences: true)
                .map(String.init)
            guard !components.isEmpty,
                  !components.contains("."),
                  !components.contains("..") else {
                throw LauncherError.bundleVerificationFailed("unsafe update bundle archive path: \(entry)")
            }
            if let existingRoot = rootName {
                guard existingRoot == components[0] else {
                    throw LauncherError.bundleVerificationFailed("update bundle archive must contain a single root directory")
                }
            } else {
                rootName = components[0]
            }
        }

        guard let rootName else {
            throw LauncherError.bundleVerificationFailed("empty update bundle archive")
        }
        return rootName
    }

    private func validateBundleArchiveEntryTypes(_ archiveURL: URL) throws {
        let result = runProcess(Constants.Commands.tar, ["-tvzf", archiveURL.path])
        guard result.exitCode == 0 else {
            throw LauncherError.bundleVerificationFailed("invalid update bundle archive: \(archiveURL.path)")
        }
        for line in result.stdout.split(whereSeparator: \.isNewline) {
            guard let entryType = line.first else {
                continue
            }
            if entryType == "l" || entryType == "h" {
                throw LauncherError.bundleVerificationFailed(
                    "update bundle archive must not contain links: \(archiveURL.lastPathComponent)"
                )
            }
        }
    }

    private func isUpdateBundleArchive(_ url: URL) -> Bool {
        url.lastPathComponent.hasSuffix(".tar.gz") || url.lastPathComponent.hasSuffix(".tgz")
    }

    private func compressedBundleSize(_ url: URL) throws -> UInt64 {
        fileExists(url) ? try fileSize(url) : 0
    }

    private func runtimeApplyBundleRunner() -> RuntimeApplyBundleRunner {
        RuntimeApplyBundleRunner(
            prepareLogs: {
                try? fileStore.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
                try? rotateRuntimeLogs()
            },
            initialHealthSnapshot: runtimeHealthSnapshot,
            preparePreflight: prepareApplyBundlePreflight,
            executeStep: executeApplyBundleStep,
            rollback: { backup in
                try rollback(backup)
            },
            startRuntimeServices: startRuntimeServices,
            writeStatus: writeRuntimeStatus,
            writeProgress: writeRuntimeProgress,
            pruneOldRuntimeArtifacts: pruneOldRuntimeArtifacts,
            reasonText: reasonText,
            log: log
        )
    }

    private func prepareApplyBundlePreflight(_ bundleURL: URL) throws -> ApplyBundlePreflightContext {
        try RuntimeApplyBundlePreflightRunner(
            stageBundle: stageBundle,
            loadManifest: loadManifest,
            fileExists: fileExists,
            createDirectory: { url, withIntermediateDirectories in
                try fileStore.createDirectory(at: url, withIntermediateDirectories: withIntermediateDirectories)
            },
            fileSize: fileSize,
            requireFreeSpace: requireFreeSpace,
            checkCompatibility: { manifest in
                try RuntimeUpdateCompatibilityChecker.check(
                    manifest: manifest,
                    currentUpdaterVersion: Constants.launcherVersion,
                    currentPlatform: Constants.Platform.current
                )
            },
            serviceRestartPolicy: {
                RuntimeServiceRestartPolicy(
                    restartVM: isLaunchdLoaded(Constants.Launchd.vmService),
                    restartProxy: isLaunchdLoaded(Constants.Launchd.proxyService),
                    restartWatchdog: isLaunchdLoaded(Constants.Launchd.watchdogService)
                )
            },
            createBackup: createBackup,
            directorySize: directorySize,
            log: log
        ).prepare(
            bundleURL: bundleURL,
            backupsDirectory: backupsDirectory,
            rootfsBase: rootfsBase
        )
    }

    private func executeApplyBundleStep(
        _ step: RuntimeWorkflowStep,
        preflight: ApplyBundlePreflightContext
    ) throws {
        try RuntimeApplyBundleStepExecutor(
            stopRuntimeServices: stopRuntimeServices,
            createDirectory: { url, withIntermediateDirectories in
                try fileStore.createDirectory(at: url, withIntermediateDirectories: withIntermediateDirectories)
            },
            fileSize: fileSize,
            replaceFile: replaceFile,
            replaceUpdateArtifacts: { artifacts, stagedBundle in
                try replaceUpdateArtifacts(artifacts, stagedBundle: stagedBundle)
            },
            runMigrations: { migrations, stagedBundle in
                try runMigrations(migrations, stagedBundle: stagedBundle)
            },
            refreshCloudInitSeedIfNeeded: refreshCloudInitSeedIfNeeded,
            writeRuntimeVersion: writeRuntimeVersion,
            startRuntimeServices: startRuntimeServices,
            activateGuestUpdateIfNeeded: activateGuestUpdateIfNeeded,
            waitForHealth: waitForHealth,
            log: log
        ).execute(step, preflight: preflight, rootfsBase: rootfsBase)
    }

    private func loadManifest(_ url: URL) throws -> UpdateBundleManifest {
        let data = try fileStore.readData(url)
        return try JSONDecoder().decode(UpdateBundleManifest.self, from: data)
    }

    private func loadChecksums(_ url: URL) throws -> [String: String] {
        let text = try fileStore.readUTF8Text(url)
        var checksums: [String: String] = [:]
        for line in text.split(separator: "\n") {
            let parts = line.split(maxSplits: 1, whereSeparator: { $0 == " " || $0 == "\t" })
            guard parts.count == 2 else {
                continue
            }
            checksums[String(parts[1]).trimmingCharacters(in: .whitespaces)] = String(parts[0])
        }
        return checksums
    }

    private func makeBundleVerificationPlan(_ manifest: UpdateBundleManifest) throws -> UpdateBundleVerificationPlan {
        do {
            return try UpdateBundleVerifier.makePlan(
                manifest: manifest,
                expectedProduct: Constants.Product.identifier
            )
        } catch let error as UpdateBundleVerificationError {
            throw launcherError(error)
        }
    }

    private func sha256(_ url: URL) throws -> String {
        let data = try fileStore.readData(url)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func verifyDigestedFile(
        _ url: URL,
        fileVerification: UpdateBundleFileVerification,
        checksumMap: [String: String]
    ) throws {
        log(
            "checksum started key=\(fileVerification.checksumKey) path=\(url.path) expectedSize=\(formatBytes(bundleItemSize(fileVerification.expectedSize)))"
        )
        let actualDigest = try sha256(url)
        let size = Int(try fileSize(url))
        do {
            try UpdateBundleVerifier.verifyDigest(
                checksumKey: fileVerification.checksumKey,
                expectedSHA256: fileVerification.expectedSHA256,
                expectedSize: fileVerification.expectedSize,
                checksumMap: checksumMap,
                actualSHA256: actualDigest,
                actualSize: size
            )
        } catch let error as UpdateBundleVerificationError {
            throw launcherError(error)
        }
        log("checksum completed key=\(fileVerification.checksumKey) actualSize=\(formatBytes(bundleItemSize(size)))")
    }

    private func launcherError(_ error: UpdateBundleVerificationError) -> LauncherError {
        switch error {
        case .unsupportedSchema(let schemaVersion):
            return .missingArgument("unsupported bundle schema: \(schemaVersion)")
        case .unsupportedProduct(let product):
            return .missingArgument("unsupported bundle product: \(product)")
        case .invalidArtifactName(let name):
            return .missingArgument("invalid artifact name: \(name)")
        case .invalidMigrationName(let name):
            return .missingArgument("invalid migration name: \(name)")
        case .unsupportedArtifactType(let type):
            return .bundleVerificationFailed("unsupported artifact type: \(type)")
        case .manifestChecksumMismatch(let checksumKey):
            return .bundleVerificationFailed("manifest checksum mismatch for \(checksumKey)")
        case .checksumFileMismatch(let checksumKey):
            return .bundleVerificationFailed("checksums.txt mismatch for \(checksumKey)")
        case .sizeMismatch(let checksumKey):
            return .bundleVerificationFailed("size mismatch for \(checksumKey)")
        }
    }

    private func runMigrations(_ migrations: [UpdateBundleMigration], stagedBundle: URL) throws {
        try RuntimeMigrationRunner(
            isExecutableFile: { path in fileStore.isExecutableFile(atPath: path) },
            runRequired: runRequired,
            log: log
        ).run(migrations, stagedBundle: stagedBundle)
    }

    private func replaceUpdateArtifacts(_ artifacts: [UpdateBundleArtifact], stagedBundle: URL) throws {
        try makeArtifactReplacer().replace(artifacts, stagedBundle: stagedBundle)
    }

    private func validateUpdateArtifactPayload(_ artifact: UpdateBundleArtifact, source: URL) throws {
        try makeArtifactReplacer().validatePayload(artifact, source: source)
    }

    private func makeArtifactReplacer() -> RuntimeArtifactReplacer {
        RuntimeArtifactReplacer(
            destinations: RuntimeArtifactReplacementDestinations(
                managerApp: URL(fileURLWithPath: Constants.Product.managerAppPath),
                nginxBundle: installedPaths.nginxDirectory,
                guestDeploy: installedPaths.deployDirectory,
                runtimeTools: URL(fileURLWithPath: "/usr/local/bin")
            ),
            temporaryDirectory: fileStore.temporaryDirectory,
            fileExists: fileExists,
            directoryExists: directoryExists,
            fileSize: fileSize,
            createDirectory: { url, withIntermediateDirectories in
                try fileStore.createDirectory(at: url, withIntermediateDirectories: withIntermediateDirectories)
            },
            removeItem: { url in try fileStore.removeItem(at: url) },
            moveItem: { source, destination in try fileStore.moveItem(at: source, to: destination) },
            readUTF8Text: { url in try fileStore.readUTF8Text(url) },
            runRequired: runRequired,
            runProcessToFile: runProcessToFile,
            log: log
        )
    }

    private func fileExists(_ url: URL) -> Bool {
        fileStore.fileExists(url)
    }

    private func directoryExists(_ url: URL) -> Bool {
        fileStore.directoryExists(url)
    }

    private func fileSize(_ url: URL) throws -> UInt64 {
        try fileStore.fileSize(url)
    }

    private func directorySize(_ url: URL) throws -> UInt64 {
        try fileStore.recursiveRegularFileSize(at: url, skipsHiddenFiles: true)
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        let gib = Double(bytes) / 1_073_741_824
        if gib >= 1 {
            return String(format: "%.1f GiB", gib)
        }
        let mib = Double(bytes) / 1_048_576
        return String(format: "%.1f MiB", max(mib, 0))
    }

    private func bundleItemSize(_ bytes: Int) -> UInt64 {
        UInt64(max(bytes, 0))
    }
}
