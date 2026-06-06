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

    func testWorkflowSourceContainsOnlyLayerMarker() throws {
        let workflowRoot = packageRoot().appendingPathComponent("Sources/Workflow")
        let fileNames = Set(try swiftFiles(root: workflowRoot).map(\.lastPathComponent))

        XCTAssertEqual(
            fileNames,
            ["WorkflowLayerMarker.swift"],
            "Workflow must not own execution, IO helpers, or orchestration after responsibilities move inward/outward"
        )
    }

    func testWorkflowTestTargetDoesNotRemain() throws {
        let manifest = try String(
            contentsOf: packageRoot().appendingPathComponent("Package.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(
            manifest.contains("name: \"WorkflowTests\""),
            "Tests must follow the owning layer after Workflow execution is removed"
        )
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
                "error.localizedDescription",
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

    func testRuntimeInstallLifecycleExecutionDoesNotRemainInWorkflow() throws {
        let forbiddenFiles = [
            "Sources/Workflow/RuntimeInstallLifecycle/RuntimeFreshInstallPreflightRunner.swift",
            "Sources/Workflow/RuntimeInstallLifecycle/RuntimeInstallStepExecutor.swift",
            "Sources/Workflow/RuntimeInstallLifecycle/RuntimeInstallWorkflow.swift",
            "Sources/Errors/Definitions/RuntimeInstallWorkflowError.swift",
        ]

        for relativePath in forbiddenFiles {
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: packageRoot().appendingPathComponent(relativePath).path),
                "Install execution belongs in Application usecases and Bootstrap adapters, not Workflow: \(relativePath)"
            )
        }
    }

    func testRuntimeInstallLifecycleWorkflowDirectoryHasNoExecutionFiles() throws {
        let installWorkflowRoot = packageRoot().appendingPathComponent("Sources/Workflow/RuntimeInstallLifecycle")
        XCTAssertTrue(
            try swiftFiles(root: installWorkflowRoot).isEmpty,
            "RuntimeInstallLifecycle execution belongs in Application usecases and Bootstrap composition, not Workflow"
        )
    }

    func testRuntimeConfigureExecutionDoesNotRemainInWorkflow() {
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: packageRoot()
                    .appendingPathComponent("Sources/Workflow/RuntimeConfigureLifecycle/RuntimeConfigureWorkflow.swift")
                    .path
            ),
            "Runtime configure execution belongs in Application usecase and Bootstrap composition, not Workflow"
        )
    }

    func testRuntimeHealthWaitExecutionDoesNotRemainInWorkflow() {
        let root = packageRoot()
        let forbiddenFiles = [
            "Sources/Workflow/RuntimeHealth/RuntimeHealthWaitWorkflow.swift",
            "Sources/Errors/Definitions/RuntimeHealthWaitWorkflowError.swift",
        ]

        for path in forbiddenFiles {
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path),
                "\(path) must not own runtime health wait execution"
            )
        }
    }

    func testRuntimeHealthRefreshExecutionDoesNotRemainInWorkflow() {
        let root = packageRoot()
        let forbiddenFiles = [
            "Sources/Workflow/RuntimeHealth/RuntimeHealthRefreshWorkflow.swift",
            "Sources/Errors/Definitions/RuntimeHealthRefreshWorkflowError.swift",
        ]

        for path in forbiddenFiles {
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path),
                "\(path) must not own runtime health refresh execution"
            )
        }
    }

    func testRuntimeDatastoreRepairExecutionDoesNotRemainInWorkflow() {
        let root = packageRoot()
        let forbiddenFiles = [
            "Sources/Workflow/RuntimeRepairLifecycle/RuntimeDatastoreRepairWorkflow.swift",
            "Sources/Workflow/RuntimeRepairLifecycle/RuntimeDatastoreRepairRunner.swift",
            "Sources/Workflow/RuntimeRepairLifecycle/RuntimeDatastoreRepairResultWaiter.swift",
            "Sources/Errors/Definitions/RuntimeDatastoreRepairWorkflowError.swift",
        ]

        for path in forbiddenFiles {
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path),
                "\(path) must not own datastore repair execution"
            )
        }
    }

    func testRuntimeServiceLifecycleExecutionDoesNotRemainInWorkflow() throws {
        let root = packageRoot()
        let forbiddenFiles = [
            "Sources/Workflow/RuntimeServiceLifecycle/RuntimeServiceLifecycleWorkflow.swift",
            "Sources/Errors/Definitions/RuntimeServiceLifecycleWorkflowError.swift",
        ]

        for path in forbiddenFiles {
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path),
                "\(path) must not own runtime service lifecycle execution"
            )
        }
    }

    func testRuntimeRedisBackupExecutionDoesNotRemainInWorkflow() throws {
        let root = packageRoot()
        let forbiddenFiles = [
            "Sources/Workflow/RuntimeRepairLifecycle/RuntimeRedisBackupWorkflow.swift",
            "Sources/Errors/Definitions/RuntimeRedisBackupWorkflowError.swift",
        ]

        for path in forbiddenFiles {
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path),
                "\(path) must not own redis backup execution"
            )
        }
    }

    func testRuntimeVMDiskRepairExecutionDoesNotRemainInWorkflow() {
        let root = packageRoot()
        let forbiddenFiles = [
            "Sources/Workflow/RuntimeRepairLifecycle/RuntimeVMDiskRepairWorkflow.swift",
            "Sources/Errors/Definitions/RuntimeVMDiskRepairWorkflowError.swift",
        ]

        for path in forbiddenFiles {
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path),
                "\(path) must not own VM disk repair execution"
            )
        }
    }

    func testRuntimeUninstallExecutionDoesNotRemainInWorkflow() {
        let root = packageRoot()
        let forbiddenFiles = [
            "Sources/Workflow/RuntimeUninstallLifecycle/RuntimeUninstallWorkflow.swift",
            "Sources/Errors/Definitions/RuntimeUninstallWorkflowError.swift",
        ]

        for path in forbiddenFiles {
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path),
                "\(path) must not own runtime uninstall execution"
            )
        }
    }

    func testRuntimeWatchdogWorkflowRunnerAndGuardAreMovedToUseCases() throws {
        let files = [
            "Sources/Workflow/RuntimeWatchdog/RuntimeWatchdogRunner.swift",
            "Sources/Workflow/RuntimeWatchdog/RuntimeManagedOperationGuard.swift",
        ]

        for file in files {
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: packageRoot().appendingPathComponent(file).path),
                "RuntimeWatchdog runner/guard orchestration must live in Application UseCases, not Workflow: \(file)"
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

    func testRuntimeGuestUpdateWorkflowThinWrappersDoNotExist() throws {
        let forbiddenFiles = [
            "Sources/Workflow/RuntimeUpdateLifecycle/RuntimeGuestActivationRunner.swift",
            "Sources/Workflow/RuntimeUpdateLifecycle/RuntimeGuestActivationWorkflow.swift",
            "Sources/Workflow/RuntimeUpdateLifecycle/RuntimeGuestShutdownRunner.swift",
            "Sources/Workflow/RuntimeUpdateLifecycle/RuntimeGuestShutdownWorkflow.swift",
            "Sources/Errors/Definitions/RuntimeGuestActivationWorkflowError.swift",
            "Sources/Errors/Definitions/RuntimeGuestShutdownWorkflowError.swift",
        ]

        for relativePath in forbiddenFiles {
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: packageRoot().appendingPathComponent(relativePath).path),
                "Guest update activation/shutdown execution belongs in Application usecases, not Workflow: \(relativePath)"
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

    func testRuntimeUpdateLifecycleWorkflowDirectoryHasNoExecutionFiles() throws {
        let updateWorkflowRoot = packageRoot().appendingPathComponent("Sources/Workflow/RuntimeUpdateLifecycle")
        let fileNames = Set(try swiftFiles(root: updateWorkflowRoot).map(\.lastPathComponent))

        XCTAssertTrue(
            fileNames.isEmpty,
            "RuntimeUpdateLifecycle execution belongs in Application usecases and Bootstrap adapters, not Workflow: \(fileNames.sorted())"
        )
    }

    func testRuntimeBundlePreparationWorkflowDoesNotExist() throws {
        let file = packageRoot().appendingPathComponent(
            "Sources/Workflow/RuntimeUpdateLifecycle/RuntimeBundlePreparationWorkflow.swift"
        )

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: file.path),
            "Bundle preparation execution belongs in Application usecase, not Workflow"
        )
    }

    func testRuntimeGuestCapabilityCheckerDoesNotRemainInWorkflow() throws {
        let file = packageRoot().appendingPathComponent(
            "Sources/Workflow/RuntimeUpdateLifecycle/RuntimeGuestCapabilityChecker.swift"
        )

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: file.path),
            "Guest capability requirement execution belongs in Application usecase, not Workflow"
        )
    }

    func testRuntimeRollbackExecutionDoesNotRemainInWorkflow() throws {
        let forbiddenFiles = [
            "Sources/Workflow/RuntimeUpdateLifecycle/RuntimeRollbackPreflightRunner.swift",
            "Sources/Workflow/RuntimeUpdateLifecycle/RuntimeRollbackRunner.swift",
            "Sources/Workflow/RuntimeUpdateLifecycle/RuntimeRollbackStepExecutor.swift",
            "Sources/Workflow/RuntimeUpdateLifecycle/RuntimeRollbackWorkflow.swift",
            "Sources/Errors/Definitions/RuntimeRollbackWorkflowError.swift",
        ]

        for relativePath in forbiddenFiles {
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: packageRoot().appendingPathComponent(relativePath).path),
                "Rollback execution belongs in Application usecase and Bootstrap adapters, not Workflow: \(relativePath)"
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
