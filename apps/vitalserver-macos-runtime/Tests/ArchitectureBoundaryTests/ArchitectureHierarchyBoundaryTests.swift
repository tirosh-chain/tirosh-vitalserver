import XCTest
import Errors

final class ArchitectureHierarchyBoundaryTests: XCTestCase {
    func testSourceRootUsesIdealTopLevelHierarchy() throws {
        let sources = packageRoot().appendingPathComponent("Sources")
        let expected = Set([
            "Errors",
            "Contracts",
            "Domain",
            "Application",
            "Workflow",
            "Adapters",
            "Bootstrap",
            "Hosts",
        ])

        XCTAssertEqual(try childDirectoryNames(of: sources), expected)
    }

    func testRoleFoldersExistAtTheirOwnedLayer() throws {
        let sources = packageRoot().appendingPathComponent("Sources")
        let required = [
            "Errors/Failure",
            "Errors/Boundary",
            "Errors/Recovery",
            "Errors/Context",
            "Errors/Definitions",
            "Contracts/Shared",
            "Contracts/RuntimeControl",
            "Domain/Models",
            "Domain/Policies",
            "Domain/StateMachines",
            "Domain/Invariants",
            "Application/Ports",
            "Application/UseCases",
            "Workflow/RuntimeConfigureLifecycle",
            "Workflow/RuntimeHealth",
            "Workflow/RuntimeInstallLifecycle",
            "Workflow/RuntimeRepairLifecycle",
            "Workflow/RuntimeServiceLifecycle",
            "Workflow/RuntimeShared",
            "Workflow/RuntimeUninstallLifecycle",
            "Workflow/RuntimeUpdateLifecycle",
            "Workflow/RuntimeWatchdog",
            "Adapters/Inbound/CLI/Commands",
            "Adapters/Inbound/CLI/Parsing",
            "Adapters/Inbound/CLI/Presentation",
            "Adapters/Inbound/RuntimeControlAPI/Boundary",
            "Adapters/Inbound/RuntimeControlAPI/Transport",
            "Adapters/Inbound/RuntimeControlAPI/Testing",
            "Adapters/Inbound/MacControlPanel/Composition",
            "Adapters/Inbound/MacControlPanel/Presentation",
            "Adapters/Outbound/FileSystem",
            "Adapters/Outbound/Persistence",
            "Adapters/Outbound/ObservabilityStore",
            "Adapters/Outbound/PackageReceipts",
            "Adapters/Outbound/Health",
            "Adapters/Outbound/Launchd",
            "Adapters/Outbound/Process",
            "Adapters/Outbound/DiskImages",
            "Adapters/Outbound/Packages",
            "Adapters/Outbound/VirtualMachine",
            "Adapters/Outbound/Virtualization",
            "Adapters/Outbound/CloudInit",
            "Adapters/Outbound/MacRuntimeControlClient",
            "Bootstrap/DI",
            "Bootstrap/Composition",
            "Hosts/CLI/Entrypoint",
            "Hosts/CLI/ProcessBoundary",
            "Hosts/MacControlPanel/Entrypoint",
            "Hosts/MacControlPanel/Composition",
            "Hosts/MacControlPanel/NativeShell",
        ]

        for path in required {
            assertDirectoryExists(sources.appendingPathComponent(path), "\(path) must exist")
        }
    }

    func testLegacyLayerFoldersAndGitkeepFilesDoNotRemain() throws {
        let root = packageRoot()
        let forbidden = [
            "Sources/Core",
            "Sources/Interfaces",
            "Sources/HostCLI",
            "Sources/Infrastructure",
            "Sources/HostAdapters",
            "Sources/MacHostRuntimeAdapter",
            "Sources/MacRuntimeControlApp",
            "Sources/RuntimeControlAPI",
            "Sources/Adapters/Inbound/HostCLI",
            "Sources/Adapters/Outbound/Infrastructure",
            "Sources/Adapters/Outbound/HostAdapters",
            "Sources/Adapters/Outbound/MacHostRuntimeAdapter",
            "Sources/Hosts/MacControlPanelHost",
        ]

        for path in forbidden {
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path),
                "\(path) must not remain in the ideal hierarchy"
            )
        }

        let gitkeepFiles = try swiftPackageFiles(root: root).filter { $0.lastPathComponent == ".gitkeep" }
        XCTAssertTrue(gitkeepFiles.isEmpty, ".gitkeep files must not remain")
    }

    func testSwiftPMTargetsUseIdealModuleNames() throws {
        let manifest = try String(
            contentsOf: packageRoot().appendingPathComponent("Package.swift"),
            encoding: .utf8
        )

        for target in [
            "Errors",
            "Contracts",
            "RuntimeControl",
            "Domain",
            "Application",
            "Workflow",
            "InboundAdapters",
            "OutboundAdapters",
            "Bootstrap",
            "CLIHost",
            "MacControlPanelHost",
        ] {
            XCTAssertTrue(manifest.contains("name: \"\(target)\""), "\(target) target must be declared")
        }

        for legacyTarget in ["Adapters", "Infrastructure", "HostAdapters", "HostCLI", "MacHostRuntimeAdapter"] {
            XCTAssertFalse(manifest.contains("name: \"\(legacyTarget)\""), "\(legacyTarget) target must not remain")
        }
    }

    func testLegacyLayerVocabularyDoesNotLeakIntoRuntimeSourcesTestsOrSupportFiles() throws {
        let root = packageRoot()
        let forbidden = [
            "HostCLI",
            "MacHostRuntime",
            "MacHostRuntimeAdapter",
            "MacRuntimeControlApp",
            "InfrastructureLayerMarker",
            "HostAdaptersLayerMarker",
            "RuntimeAdapterConstants",
        ]
        let scannedRoots = [
            root.appendingPathComponent("Sources"),
            root.appendingPathComponent("Tests"),
            root.appendingPathComponent("Support"),
            root.appendingPathComponent("README.md"),
        ]

        let files = try scannedRoots.flatMap { try sourceLikeFiles(root: $0) }
            .filter { !$0.path.contains("/Tests/ArchitectureBoundaryTests/") }

        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for token in forbidden {
                XCTAssertFalse(
                    text.contains(token),
                    "\(token) must not remain in \(file.path)"
                )
            }
        }
    }

    func testLayerImportDirectionStaysInward() throws {
        let root = packageRoot().appendingPathComponent("Sources")
        let checks: [(String, Set<String>)] = [
            (
                "Contracts/Shared",
                ["Errors", "Domain", "Application", "Workflow", "InboundAdapters", "OutboundAdapters", "Bootstrap", "RuntimeControl", "CLIHost", "MacControlPanelHost"]
            ),
            (
                "Contracts/RuntimeControl",
                ["Domain", "Application", "Workflow", "InboundAdapters", "OutboundAdapters", "Bootstrap", "CLIHost", "MacControlPanelHost"]
            ),
            (
                "Errors",
                ["Domain", "Application", "Workflow", "InboundAdapters", "OutboundAdapters", "Bootstrap", "RuntimeControl", "CLIHost", "MacControlPanelHost"]
            ),
            (
                "Domain",
                ["Application", "Workflow", "InboundAdapters", "OutboundAdapters", "Bootstrap", "RuntimeControl", "CLIHost", "MacControlPanelHost"]
            ),
            (
                "Application",
                ["Workflow", "InboundAdapters", "OutboundAdapters", "Bootstrap", "RuntimeControl", "CLIHost", "MacControlPanelHost"]
            ),
            (
                "Workflow",
                ["InboundAdapters", "OutboundAdapters", "Bootstrap", "CLIHost", "MacControlPanelHost"]
            ),
        ]

        for (layerPath, forbiddenImports) in checks {
            let layerRoot = root.appendingPathComponent(layerPath)
            for file in try swiftFiles(root: layerRoot) {
                let imports = try importedModules(in: file)
                let forbidden = imports.intersection(forbiddenImports)
                XCTAssertTrue(
                    forbidden.isEmpty,
                    "\(layerPath) must not import outward modules \(forbidden.sorted()) in \(file.path)"
                )
            }
        }
    }

    func testApplicationUseCasesAreStatelessStructsWithoutOwnedPorts() throws {
        let useCaseRoot = packageRoot().appendingPathComponent("Sources/Application/UseCases")
        let useCaseFiles = try swiftFiles(root: useCaseRoot)
            .filter { $0.lastPathComponent.hasSuffix("UseCase.swift") }
        XCTAssertFalse(useCaseFiles.isEmpty, "Application/UseCases must contain explicit usecase files")

        for file in useCaseFiles {
            let text = try String(contentsOf: file, encoding: .utf8)
            XCTAssertFalse(
                text.contains("class ") && text.contains("UseCase"),
                "Usecases must not be class declarations: \(file.path)"
            )

            let body = try useCaseStructBody(in: text, file: file)
            XCTAssertFalse(body.contains("ports."), "Usecases must not own or call ports directly: \(file.path)")
            XCTAssertFalse(body.contains("Ports"), "Usecases must not own port bundles: \(file.path)")

            for token in [
                "FileManager",
                "Process(",
                "URLSession",
                "Data(contentsOf",
                "String(contentsOf",
            ] {
                XCTAssertFalse(body.contains(token), "Usecases must not perform direct IO/effects via \(token): \(file.path)")
            }

            for line in topLevelLines(in: body) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                XCTAssertFalse(
                    storedPropertyPatternMatches(trimmed),
                    "Usecase structs must remain stateless and not declare stored properties: \(file.path) line=\(trimmed)"
                )
            }
        }
    }

    func testWorkflowDoesNotOwnConcreteHostEffects() throws {
        let workflowRoot = packageRoot().appendingPathComponent("Sources/Workflow")
        for file in try swiftFiles(root: workflowRoot) {
            let text = try String(contentsOf: file, encoding: .utf8)
            for token in [
                "FileManager.default",
                "URLSession",
                "import Virtualization",
                "import SQLite3",
                "VZVirtual",
            ] {
                XCTAssertFalse(text.contains(token), "Workflow must use ports/operations instead of concrete host effect \(token): \(file.path)")
            }
            XCTAssertFalse(
                containsConcreteProcessInvocation(text),
                "Workflow must use ports/operations instead of constructing Process directly: \(file.path)"
            )
        }
    }

    func testWorkflowDoesNotCallDomainPolicyOrReasonFormatterDirectly() throws {
        let workflowRoot = packageRoot().appendingPathComponent("Sources/Workflow")
        for file in try swiftFiles(root: workflowRoot) {
            let text = try String(contentsOf: file, encoding: .utf8)
            XCTAssertFalse(
                containsRegex(#"Runtime[A-Za-z0-9]+Policy\."#, in: text),
                "Workflow must call Application usecases instead of Domain policy static methods directly: \(file.path)"
            )
            XCTAssertFalse(
                text.contains("RuntimeFailureReasonText.describe"),
                "Workflow must call Application usecases instead of formatting failure reasons directly: \(file.path)"
            )
        }
    }

    func testWorkflowDoesNotDescribeErrorsDirectly() throws {
        let workflowRoot = packageRoot().appendingPathComponent("Sources/Workflow")
        for file in try swiftFiles(root: workflowRoot) {
            let text = try String(contentsOf: file, encoding: .utf8)
            let forbiddenTokens = [
                "String(describing:",
                #"\(error)"#,
            ]
            for token in forbiddenTokens {
                XCTAssertFalse(
                    text.contains(token),
                    "Workflow must use Errors/Application contracts instead of formatting Error directly with \(token): \(file.path)"
                )
            }
        }
    }

    func testWorkflowDoesNotInterpretOperationStepsDirectly() throws {
        let workflowRoot = packageRoot().appendingPathComponent("Sources/Workflow")
        for file in try swiftFiles(root: workflowRoot) {
            let text = try String(contentsOf: file, encoding: .utf8)
            XCTAssertFalse(
                text.contains("switch step"),
                "Workflow must ask UseCase for step execution plans instead of interpreting RuntimeWorkflowStep directly: \(file.path)"
            )
        }
    }

    func testRuntimeUpdateWorkflowDoesNotInterpretOperationStepsDirectly() throws {
        let updateWorkflowRoot = packageRoot().appendingPathComponent("Sources/Workflow/RuntimeUpdateLifecycle")
        for file in try swiftFiles(root: updateWorkflowRoot) {
            let text = try String(contentsOf: file, encoding: .utf8)
            XCTAssertFalse(
                text.contains("switch step"),
                "RuntimeUpdateLifecycle Workflow must ask UseCase for step execution plans instead of interpreting RuntimeWorkflowStep directly: \(file.path)"
            )
        }
    }

    func testRuntimeUpdateWorkflowDoesNotInterpretRollbackBackupSelectionDirectly() throws {
        let updateWorkflowRoot = packageRoot().appendingPathComponent("Sources/Workflow/RuntimeUpdateLifecycle")
        let forbiddenTokens = [
            "backupURL(for:",
            "case .latestBackup",
            "case .specificBackup",
        ]

        for file in try swiftFiles(root: updateWorkflowRoot) {
            let text = try String(contentsOf: file, encoding: .utf8)
            for token in forbiddenTokens {
                XCTAssertFalse(
                    text.contains(token),
                    "RuntimeUpdateLifecycle Workflow must pass rollback backup selections to a port instead of interpreting \(token) directly: \(file.path)"
                )
            }
        }
    }

    func testRuntimeGuestActivationWorkflowDoesNotInterpretActivationStateDirectly() throws {
        let file = packageRoot().appendingPathComponent(
            "Sources/Workflow/RuntimeUpdateLifecycle/RuntimeGuestActivationRunner.swift"
        )
        let text = try String(contentsOf: file, encoding: .utf8)
        let forbiddenTokens = [
            "requiresActivation",
            "skippedLogMessage",
            "requestedLogMessage",
            "completedLogMessage",
            "guard let request",
            "!isVMServiceLoaded",
            "ceil(",
            "GuestActivationWaitConfiguration(",
        ]

        for token in forbiddenTokens {
            XCTAssertFalse(
                text.contains(token),
                "RuntimeGuestActivationRunner must execute UseCase activation plans instead of interpreting \(token) directly"
            )
        }
    }

    func testRuntimeGuestShutdownWorkflowDoesNotInterpretShutdownStateDirectly() throws {
        let file = packageRoot().appendingPathComponent(
            "Sources/Workflow/RuntimeUpdateLifecycle/RuntimeGuestShutdownRunner.swift"
        )
        let text = try String(contentsOf: file, encoding: .utf8)
        let forbiddenTokens = [
            "guestShutdownPlan",
            "requestedLogMessage",
            "readyLogMessage",
            "ceil(",
            "GuestShutdownWaitConfiguration(",
        ]

        for token in forbiddenTokens {
            XCTAssertFalse(
                text.contains(token),
                "RuntimeGuestShutdownRunner must execute UseCase shutdown plans instead of interpreting \(token) directly"
            )
        }
    }

    func testRuntimeUpdateWorkflowDoesNotInterpretPreflightFileObservationsDirectly() throws {
        let updateWorkflowRoot = packageRoot().appendingPathComponent("Sources/Workflow/RuntimeUpdateLifecycle")
        let forbiddenTokens = [
            "missingFileFailureMessage",
            "replacingRootfsStoragePreflightPlan",
            "unchangedRootfsStoragePreflightPlan",
            "guard fileExists",
            "guard directoryExists",
            "!fileExists",
            "!directoryExists",
            "RuntimeFileNames.updateBundleManifest",
            "shouldReplace",
            "guard let stagedRootfs",
            "stagedRootfs == nil",
            "stagedRootfs != nil",
            "preparesGuestShutdown",
            "String(describing:",
            "requiresRuntimeDiskHealthCheck",
            "requiredGuestCapabilities",
        ]

        for file in try swiftFiles(root: updateWorkflowRoot) {
            let text = try String(contentsOf: file, encoding: .utf8)
            for token in forbiddenTokens {
                XCTAssertFalse(
                    text.contains(token),
                    "RuntimeUpdateLifecycle Workflow must pass explicit file observations to UseCase/Adapters instead of interpreting \(token) directly: \(file.path)"
                )
            }
        }
    }

    func testRuntimeApplyBundlePreflightRunnerDoesNotOwnRootfsFileObservation() throws {
        let file = packageRoot().appendingPathComponent(
            "Sources/Workflow/RuntimeUpdateLifecycle/RuntimeApplyBundlePreflightRunner.swift"
        )
        let text = try String(contentsOf: file, encoding: .utf8)
        let forbiddenTokens = [
            "fileExists",
            "fileSize",
            "ApplyRuntimeBundleRootfsStorageObservation(",
            "case .unchanged",
            "case .replacing",
            "rootfsStorageDecision(",
            "runtimeHealthSnapshot()",
            "diskHealthDecision(",
            "case .requireRuntimeDiskHealthAllowsUpdate",
            "case .requireGuestCapability",
        ]

        for token in forbiddenTokens {
            XCTAssertFalse(
                text.contains(token),
                "RuntimeApplyBundlePreflightRunner must receive explicit rootfs storage observations from a port instead of using \(token)"
            )
        }
    }

    func testRuntimeApplyBundleStepExecutorDoesNotOwnApplyBundleEffects() throws {
        let file = packageRoot().appendingPathComponent(
            "Sources/Workflow/RuntimeUpdateLifecycle/RuntimeApplyBundleStepExecutor.swift"
        )
        let text = try String(contentsOf: file, encoding: .utf8)
        let forbiddenTokens = [
            "fileSize",
            "stagedRootfsBytes: try",
            "rootfsReplacementExecutionPlan(stagedRootfs:",
            "switch executionPlan",
            "switch stopPlan",
            "switch rootfsPlan",
            "case .stopRuntimeServices",
            "case .replaceRootfsBase",
            "case .replaceUpdateArtifacts",
            "case .runMigrations",
            "case .refreshCloudInitSeed",
            "case .writeRuntimeVersion",
            "case .startRuntimeServices",
            "case .activateGuestUpdate",
            "case .waitRuntimeHealth",
            "runningVMProcessID",
            "stopRuntimeServicesAfterGuestPoweroff",
            "prepareGuestShutdownForUpdate",
            "clearGuestShutdownPreparation",
            "observeRootfsReplacement",
            "replaceFile",
            "replaceUpdateArtifacts",
            "runMigrations",
            "refreshCloudInitSeedIfNeeded",
            "writeRuntimeVersion",
            "activateGuestUpdateIfNeeded",
            "waitForHealth",
        ]

        for token in forbiddenTokens {
            XCTAssertFalse(
                text.contains(token),
                "RuntimeApplyBundleStepExecutor must create a UseCase plan and pass it to an execution port instead of owning \(token)"
            )
        }
    }

    func testRuntimeBundlePreparationWorkflowDoesNotInterpretTemporaryRootDirectly() throws {
        let file = packageRoot().appendingPathComponent(
            "Sources/Workflow/RuntimeUpdateLifecycle/RuntimeBundlePreparationWorkflow.swift"
        )
        let text = try String(contentsOf: file, encoding: .utf8)
        let forbiddenTokens = [
            "guard let temporaryRoot",
            "materialized.temporaryRoot",
        ]

        for token in forbiddenTokens {
            XCTAssertFalse(
                text.contains(token),
                "RuntimeBundlePreparationWorkflow must execute UseCase cleanup plans instead of interpreting \(token) directly"
            )
        }
    }

    func testRuntimeGuestCapabilityCheckerDoesNotInterpretCapabilityDecisionDirectly() throws {
        let file = packageRoot().appendingPathComponent(
            "Sources/Workflow/RuntimeUpdateLifecycle/RuntimeGuestCapabilityChecker.swift"
        )
        let text = try String(contentsOf: file, encoding: .utf8)
        let forbiddenTokens = [
            "guestCapabilityDecision",
            "decision.failure",
            "if let failure",
        ]

        for token in forbiddenTokens {
            XCTAssertFalse(
                text.contains(token),
                "RuntimeGuestCapabilityChecker must execute UseCase capability plans instead of interpreting \(token) directly"
            )
        }
    }

    func testRuntimeRollbackPreflightRunnerDoesNotOwnBackupFileObservation() throws {
        let file = packageRoot().appendingPathComponent(
            "Sources/Workflow/RuntimeUpdateLifecycle/RuntimeRollbackPreflightRunner.swift"
        )
        let text = try String(contentsOf: file, encoding: .utf8)
        let forbiddenTokens = [
            "fileExists",
            "directoryExists",
            "rollbackBackupRootfsObservationRequirement",
            "rollbackBackupDirectoryDecision",
            "rollbackBackupRootfsDecision",
            "RollbackRuntimeBackupDirectoryObservation",
            "RollbackRuntimeBackupRootfsObservation",
        ]

        for token in forbiddenTokens {
            XCTAssertFalse(
                text.contains(token),
                "RuntimeRollbackPreflightRunner must receive explicit backup observations from a port instead of using \(token)"
            )
        }
    }

    func testRuntimeRollbackStepExecutorDoesNotOwnRequiredInputObservation() throws {
        let file = packageRoot().appendingPathComponent(
            "Sources/Workflow/RuntimeUpdateLifecycle/RuntimeRollbackStepExecutor.swift"
        )
        let text = try String(contentsOf: file, encoding: .utf8)
        let forbiddenTokens = [
            "fileExists",
            "case .backupVersionExists",
            "switch useCase.rollbackStepRequiredInput",
            "rollbackStepRequiredInput",
            "rollbackStepExecutionPlan(",
            "RollbackRuntimeStepRequiredInputObservation",
            "switch executionPlan",
            "case .stopRuntimeServices",
            "case .restoreRootfsBase",
            "case .restoreRuntimeVersion",
            "case .restoreUpdateArtifacts",
            "case .startRuntimeServices",
            "case .waitRuntimeHealth",
            "replaceFile",
            "restoreBackupPathIfExists",
            "restoreRuntimeToolsIfExists",
            "writeRuntimeVersion",
        ]

        for token in forbiddenTokens {
            XCTAssertFalse(
                text.contains(token),
                "RuntimeRollbackStepExecutor must receive explicit required-input observations from a port instead of using \(token)"
            )
        }
    }

    private func packageRoot() -> URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }

    private func childDirectoryNames(of url: URL) throws -> Set<String> {
        let urls = try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        return Set(try urls.compactMap { child in
            let values = try child.resourceValues(forKeys: [.isDirectoryKey])
            return values.isDirectory == true ? child.lastPathComponent : nil
        })
    }

    private func assertDirectoryExists(_ url: URL, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        var isDirectory = ObjCBool(false)
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        XCTAssertTrue(exists && isDirectory.boolValue, message, file: file, line: line)
    }

    private func swiftPackageFiles(root: URL) throws -> [URL] {
        let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsPackageDescendants]
        )
        return try enumerator?.compactMap { item in
            guard let url = item as? URL else { return nil }
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            return values.isRegularFile == true ? url : nil
        } ?? []
    }

    private func sourceLikeFiles(root: URL) throws -> [URL] {
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory) else {
            return []
        }
        let files: [URL]
        if isDirectory.boolValue {
            files = try swiftPackageFiles(root: root)
        } else {
            files = [root]
        }
        return files.filter { file in
            [
                "swift",
                "md",
                "py",
                "sh",
                "template",
            ].contains(file.pathExtension) || file.lastPathComponent.contains(".template")
        }
    }

    private func swiftFiles(root: URL) throws -> [URL] {
        try swiftPackageFiles(root: root).filter { $0.pathExtension == "swift" }
    }

    private func importedModules(in file: URL) throws -> Set<String> {
        let text = try String(contentsOf: file, encoding: .utf8)
        return Set(text.split(separator: "\n").compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("import ") || trimmed.hasPrefix("@testable import ") else {
                return nil
            }
            return String(trimmed.split(separator: " ").last ?? "")
        })
    }

    private func useCaseStructBody(in text: String, file: URL) throws -> String {
        let pattern = #"public\s+struct\s+\w+UseCase(?:<[^>]+>)?\s*\{"#
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let matchRange = Range(match.range, in: text),
              let openBraceIndex = text[matchRange].lastIndex(of: "{") else {
            XCTFail("Usecase file must declare public struct ...UseCase: \(file.path)")
            return ""
        }

        let bodyStart = text.index(after: openBraceIndex)
        var depth = 1
        var index = bodyStart
        while index < text.endIndex {
            let character = text[index]
            if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 {
                    return String(text[bodyStart..<index])
                }
            }
            index = text.index(after: index)
        }

        XCTFail("Usecase struct body must be balanced: \(file.path)")
        return ""
    }

    private func topLevelLines(in body: String) -> [String] {
        var depth = 1
        var lines: [String] = []
        for line in body.split(separator: "\n", omittingEmptySubsequences: false) {
            if depth == 1 {
                lines.append(String(line))
            }
            for character in line {
                if character == "{" {
                    depth += 1
                } else if character == "}" {
                    depth -= 1
                }
            }
        }
        return lines
    }

    private func storedPropertyPatternMatches(_ line: String) -> Bool {
        line.hasPrefix("let ")
            || line.hasPrefix("var ")
            || line.hasPrefix("public let ")
            || line.hasPrefix("public var ")
            || line.hasPrefix("internal let ")
            || line.hasPrefix("internal var ")
            || line.hasPrefix("private let ")
            || line.hasPrefix("private var ")
            || line.hasPrefix("fileprivate let ")
            || line.hasPrefix("fileprivate var ")
    }

    private func containsConcreteProcessInvocation(_ text: String) -> Bool {
        let pattern = #"(^|[^A-Za-z0-9_])Process\s*\("#
        return containsRegex(pattern, in: text)
    }

    private func containsRegex(_ pattern: String, in text: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return false
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.firstMatch(in: text, range: range) != nil
    }
}
