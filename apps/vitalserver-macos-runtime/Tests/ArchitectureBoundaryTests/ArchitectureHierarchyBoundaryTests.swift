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
            "Errors/Context",
            "Errors/Definitions",
            "Contracts/Shared",
            "Contracts/RuntimeControl",
            "Domain/Models",
            "Domain/Policies",
            "Domain/StateMachines",
            "Application/Ports",
            "Application/UseCases",
            "Workflow/RuntimeInstallLifecycle",
            "Workflow/RuntimeHealth",
            "Workflow/RuntimeRepairLifecycle",
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
            "Adapters/Outbound/VirtualMachine",
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

    func testBootstrapCompositionKeepsOnlyConstantsAndPathComposition() throws {
        let compositionRoot = packageRoot().appendingPathComponent("Sources/Bootstrap/Composition")
        let fileNames = Set(
            try FileManager.default.contentsOfDirectory(
                at: compositionRoot,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
            .filter { url in
                (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
            }
            .map(\.lastPathComponent)
        )

        XCTAssertEqual(
            fileNames,
            [
                "Constants.swift",
                "GeneratedVersion.swift",
                "LauncherPaths.swift",
                "RuntimeManagedServicePaths.swift",
            ],
            "Bootstrap/Composition must not contain Host runner, file IO, process, Workflow, or Usecase composition"
        )
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

    func testSourceTestAndSupportFoldersDoNotKeepEmptyPlaceholders() throws {
        let root = packageRoot()
        let scannedRoots = [
            root.appendingPathComponent("Sources"),
            root.appendingPathComponent("Tests"),
            root.appendingPathComponent("Support"),
        ]

        let emptyPlaceholderDirectories = try scannedRoots.flatMap { try emptyDirectories(root: $0) }
        XCTAssertTrue(
            emptyPlaceholderDirectories.isEmpty,
            "Empty source/test/support placeholder directories must not remain: \(emptyPlaceholderDirectories.map(\.path).sorted())"
        )
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

    func testBootstrapDIHasExplicitApplicationContainer() throws {
        let file = packageRoot()
            .appendingPathComponent("Sources/Bootstrap/DI/RuntimeApplicationContainer.swift")
        let text = try String(contentsOf: file, encoding: .utf8)

        XCTAssertTrue(text.contains("public struct RuntimeApplicationContainer"))
        XCTAssertTrue(text.contains("RuntimeLifecycleComposition.resolve"))
        for token in [
            "static let shared",
            "static var shared",
            "RuntimeApplicationContainer.shared",
        ] {
            XCTAssertFalse(
                text.contains(token),
                "DI container must be explicit per host startup, not a global service locator: \(token)"
            )
        }
    }

    func testRuntimeLifecycleDependencyResolutionLivesInBootstrapDI() throws {
        let root = packageRoot()
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent("Sources/Bootstrap/DI/RuntimeLifecycleComposition.swift").path
            ),
            "Concrete lifecycle dependency resolution belongs in Bootstrap/DI"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent("Sources/Bootstrap/Composition/RuntimeLifecycleComposition.swift").path
            ),
            "Composition must not own application-level dependency graph resolution"
        )
    }

    func testHostCLIRuntimeLifecycleUsesApplicationContainerForInitialDependencyGraph() throws {
        let file = packageRoot()
            .appendingPathComponent("Sources/Hosts/CLI/ProcessBoundary/RuntimeLifecycle.swift")
        let text = try String(contentsOf: file, encoding: .utf8)

        XCTAssertTrue(text.contains("let container: RuntimeApplicationContainer"))
        XCTAssertTrue(text.contains("RuntimeApplicationContainer("))
        XCTAssertFalse(
            text.contains("RuntimeLifecycleComposition.resolve("),
            "HostCLI must receive the initial dependency graph through Bootstrap/DI container"
        )
    }

    func testHostCLIRepairFactoriesLiveAtProcessBoundary() throws {
        let file = packageRoot()
            .appendingPathComponent("Sources/Hosts/CLI/ProcessBoundary/RuntimeLifecycle+Workflows.swift")
        let text = try String(contentsOf: file, encoding: .utf8)

        XCTAssertTrue(text.contains("container.makeRuntimeDatastoreRepairComposition"))
        XCTAssertTrue(text.contains("container.makeRuntimeVMDiskRepairComposition"))
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: packageRoot()
                    .appendingPathComponent("Sources/Hosts/CLI/ProcessBoundary/RuntimeApplicationContainer+Repair.swift")
                    .path
            ),
            "Repair composition factories belong at the Host process boundary"
        )
        for token in [
            "RuntimeDatastoreRepairCompositionContext(",
            "RuntimeDatastoreRepairCompositionOperations(",
            "RuntimeVMDiskRepairCompositionContext(",
            "RuntimeVMDiskRepairCompositionOperations(",
        ] {
            XCTAssertFalse(
                text.contains(token),
                "RuntimeLifecycle must provide explicit actions and delegate repair composition to the Host factory: \(token)"
            )
        }
    }

    func testBootstrapDIDoesNotContainRepairExecutionFactories() throws {
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: packageRoot()
                    .appendingPathComponent("Sources/Bootstrap/DI/RuntimeApplicationContainer+Repair.swift")
                    .path
            ),
            "Repair execution factories must not live in Bootstrap DI"
        )
    }

    func testWorkflowTestTargetRemainsForStatefulOrchestration() throws {
        let manifest = try String(
            contentsOf: packageRoot().appendingPathComponent("Package.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(
            manifest.contains("name: \"WorkflowTests\""),
            "Stateful lifecycle orchestration must keep Workflow-specific tests"
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

    func testDomainPoliciesDoNotOwnPollingOrEffectClosures() throws {
        let domainRoot = packageRoot().appendingPathComponent("Sources/Domain")
        for file in try swiftFiles(root: domainRoot) {
            let text = try String(contentsOf: file, encoding: .utf8)
            for token in [
                "sleep:",
                "onProgress:",
                "observe:",
                "loadResult: () ->",
                "Thread.sleep",
            ] {
                XCTAssertFalse(
                    text.contains(token),
                    "Domain must return pure decisions; polling/effect closure \(token) belongs in Workflow/Application: \(file.path)"
                )
            }
        }
    }

    func testBootstrapDoesNotOwnCommandExecutionDetails() throws {
        let bootstrapRoot = packageRoot().appendingPathComponent("Sources/Bootstrap")
        for file in try swiftFiles(root: bootstrapRoot) {
            let text = try String(contentsOf: file, encoding: .utf8)
            for token in [
                "Constants.Commands",
                "runProcess",
                "runRequired",
                "runProcessToFile",
                "Process(",
                "FileManager",
                "ProcessInfo",
            ] {
                XCTAssertFalse(
                    text.contains(token),
                    "Bootstrap must assemble explicit ports, not own command execution details via \(token): \(file.path)"
                )
            }
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
                "RuntimeErrorDescription.describe",
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

    func testRuntimeInstallLifecycleKeepsStatefulWorkflowOnly() throws {
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: packageRoot()
                    .appendingPathComponent("Sources/Workflow/RuntimeInstallLifecycle/RuntimeInstallWorkflow.swift")
                    .path
            ),
            "Install state/progress orchestration belongs in Workflow"
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: packageRoot()
                    .appendingPathComponent("Sources/Hosts/CLI/ProcessBoundary/RuntimeInstallComposition.swift")
                    .path
            ),
            "Install concrete runner wiring belongs at the Host process boundary"
        )

        let forbiddenFiles = [
            "Sources/Workflow/RuntimeInstallLifecycle/RuntimeFreshInstallPreflightRunner.swift",
            "Sources/Workflow/RuntimeInstallLifecycle/RuntimeInstallStepExecutor.swift",
            "Sources/Errors/Definitions/RuntimeInstallWorkflowError.swift",
            "Sources/Bootstrap/Composition/RuntimeInstallComposition.swift",
        ]

        for relativePath in forbiddenFiles {
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: packageRoot().appendingPathComponent(relativePath).path),
                "Install Workflow must not own preflight adapters, step executors, or Workflow-specific errors: \(relativePath)"
            )
        }
    }

    func testRuntimeInstallLifecycleWorkflowDirectoryHasOnlyWorkflowRunner() throws {
        let installWorkflowRoot = packageRoot().appendingPathComponent("Sources/Workflow/RuntimeInstallLifecycle")
        let fileNames = Set(try swiftFiles(root: installWorkflowRoot).map(\.lastPathComponent))
        XCTAssertEqual(
            fileNames,
            ["RuntimeInstallWorkflow.swift"],
            "RuntimeInstallLifecycle Workflow must keep only the stateful runner"
        )
    }

    func testRuntimeInstallStepExecutionDoesNotRemainInBootstrap() throws {
        let file = packageRoot()
            .appendingPathComponent("Sources/Bootstrap/Composition/RuntimeInstallComposition.swift")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: file.path),
            "Install concrete execution belongs at the Host process boundary, not Bootstrap"
        )
    }

    func testRuntimeConfigureExecutionDoesNotRemainInBootstrapOrWorkflow() {
        let root = packageRoot()
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: root
                    .appendingPathComponent("Sources/Hosts/CLI/ProcessBoundary/RuntimeConfigureRunner.swift")
                    .path
            ),
            "Runtime configure execution belongs at the Host process boundary"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root
                    .appendingPathComponent("Sources/Bootstrap/Composition/RuntimeConfigureRunner.swift")
                    .path
            ),
            "Runtime configure execution must not live in Bootstrap composition"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root
                    .appendingPathComponent("Sources/Workflow/RuntimeConfigureLifecycle/RuntimeConfigureWorkflow.swift")
                    .path
            ),
            "Runtime configure execution belongs in Application usecase and Host process boundary, not Workflow"
        )
    }

    func testRuntimeHealthWaitExecutionBelongsInWorkflow() {
        let root = packageRoot()
        let requiredFiles = [
            "Sources/Workflow/RuntimeHealth/RuntimeHealthWaitWorkflow.swift",
            "Sources/Workflow/RuntimeHealth/RuntimeHealthWaitRunner.swift",
        ]

        for path in requiredFiles {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path),
                "\(path) must own runtime health wait execution"
            )
        }

        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent(
                    "Sources/Adapters/Inbound/CLI/Presentation/RuntimeHealthWaitRunner.swift"
                ).path
            ),
            "Runtime health wait execution must not live in inbound presentation adapters"
        )
    }

    func testRuntimeHealthWaitSleepIntervalDoesNotRemainInBootstrap() throws {
        let bootstrapFile = packageRoot()
            .appendingPathComponent("Sources/Bootstrap/Composition/RuntimeHealthWaitRunnerComposition.swift")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: bootstrapFile.path),
            "Runtime health wait concrete composition belongs at the Host process boundary, not Bootstrap"
        )

        let hostFile = packageRoot()
            .appendingPathComponent("Sources/Hosts/CLI/ProcessBoundary/RuntimeHealthWaitRunnerComposition.swift")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: hostFile.path),
            "Runtime health wait Host process-boundary composition must exist"
        )

        let workflowText = try String(
            contentsOf: packageRoot()
                .appendingPathComponent("Sources/Workflow/RuntimeHealth/RuntimeHealthWaitRunner.swift"),
            encoding: .utf8
        )
        for token in [
            "RuntimeHealthWaitWorkflowContext",
            "sleep:",
        ] {
            XCTAssertTrue(
                workflowText.contains(token),
                "Runtime health wait polling flow belongs in Workflow: \(token)"
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

    func testRuntimeDatastoreRepairKeepsStatefulWorkflowOnly() {
        let root = packageRoot()
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent("Sources/Workflow/RuntimeRepairLifecycle/RuntimeDatastoreRepairWorkflow.swift").path
            ),
            "Datastore repair request/wait/restart orchestration belongs in Workflow"
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent("Sources/Hosts/CLI/ProcessBoundary/RuntimeDatastoreRepairComposition.swift").path
            ),
            "Datastore repair Host process-boundary composition must exist"
        )

        let forbiddenFiles = [
            "Sources/Workflow/RuntimeRepairLifecycle/RuntimeDatastoreRepairRunner.swift",
            "Sources/Workflow/RuntimeRepairLifecycle/RuntimeDatastoreRepairResultWaiter.swift",
            "Sources/Errors/Definitions/RuntimeDatastoreRepairWorkflowError.swift",
        ]

        for path in forbiddenFiles {
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path),
                "\(path) must not own datastore repair concrete execution"
            )
        }
    }

    func testRuntimeDatastoreRepairBestEffortStatusDoesNotRemainInBootstrap() throws {
        let file = packageRoot()
            .appendingPathComponent("Sources/Bootstrap/Composition/RuntimeDatastoreRepairComposition.swift")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: file.path),
            "Datastore repair concrete execution belongs at the Host process boundary, not Bootstrap"
        )
    }

    func testRepairRuntimeUseCasesStaySplitByOperationResponsibility() throws {
        let root = packageRoot()
        let requiredFiles = [
            "Sources/Application/UseCases/RepairRuntime/RepairRuntimeSharedPlans.swift",
            "Sources/Application/UseCases/RepairRuntime/RuntimeVMDiskRepairUseCase.swift",
            "Sources/Application/UseCases/RepairRuntime/RuntimeDatastoreRepairUseCase.swift",
            "Sources/Application/UseCases/RepairRuntime/RuntimeRedisBackupUseCase.swift",
        ]

        for path in requiredFiles {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path),
                "RepairRuntime usecase responsibility must stay operation-specific: \(path)"
            )
        }

        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent(
                    "Sources/Application/UseCases/RepairRuntime/RepairRuntimeUseCase.swift"
                ).path
            ),
            "RepairRuntimeUseCase must not return as a mixed VM disk/datastore/Redis backup planning bucket"
        )

        let scannedRoots = [
            root.appendingPathComponent("Sources"),
            root.appendingPathComponent("Tests"),
        ]
        let files = try scannedRoots.flatMap { try sourceLikeFiles(root: $0) }
            .filter { !$0.path.contains("/Tests/ArchitectureBoundaryTests/") }
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            XCTAssertFalse(
                text.contains("RepairRuntimeUseCase("),
                "Callers must depend on operation-specific repair usecases instead of RepairRuntimeUseCase: \(file.path)"
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

    func testRuntimeServiceStopPollingDoesNotRemainInBootstrap() throws {
        let file = packageRoot()
            .appendingPathComponent("Sources/Bootstrap/DI/RuntimeLifecycleComposition.swift")
        let text = try String(contentsOf: file, encoding: .utf8)
        for token in [
            "Thread.sleep",
            "while try",
            "waitUntilServiceStops",
            "launchdServiceIsLoaded",
            "service did not unload within",
            "launchd service state read failed",
            "ProcessState.",
            "requestStopAndWait",
            "waitUntilObservedProcessStopped",
            "RuntimeVMLifecycleStore(",
            "print(\"[",
        ] {
            XCTAssertFalse(
                text.contains(token),
                "Runtime service stop polling belongs in OutboundAdapters, not Bootstrap: \(token)"
            )
        }

        let hostText = try String(
            contentsOf: packageRoot()
                .appendingPathComponent("Sources/Hosts/CLI/ProcessBoundary/RuntimeLifecycle.swift"),
            encoding: .utf8
        )
        for token in [
            "ProcessState.requestStopAndWait",
            "ProcessState.waitUntilObservedProcessStopped",
            "RuntimeVMLifecycleStore(",
        ] {
            XCTAssertTrue(
                hostText.contains(token),
                "Runtime service process-boundary execution must stay in HostCLI: \(token)"
            )
        }
    }

    func testRuntimeBackupStoreProcessExecutionDoesNotRemainInBootstrap() throws {
        let bootstrapFile = packageRoot()
            .appendingPathComponent("Sources/Bootstrap/Composition/RuntimeBackupStoreComposition.swift")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: bootstrapFile.path),
            "BackupStore concrete composition belongs at the Host process boundary, not Bootstrap"
        )

        let hostFile = packageRoot()
            .appendingPathComponent("Sources/Hosts/CLI/ProcessBoundary/RuntimeBackupStoreComposition.swift")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: hostFile.path),
            "BackupStore Host process-boundary composition must exist"
        )

        let hostSupportText = try String(
            contentsOf: packageRoot()
                .appendingPathComponent("Sources/Hosts/CLI/ProcessBoundary/RuntimeLifecycle+Support.swift"),
            encoding: .utf8
        )
        for token in [
            "runRequired",
            "Constants.Commands.chmod",
        ] {
            XCTAssertTrue(
                hostSupportText.contains(token),
                "BackupStore process execution must stay at the Host process boundary: \(token)"
            )
        }
    }

    func testRuntimeCloudInitSeedProcessExecutionDoesNotRemainInBootstrap() throws {
        let bootstrapFile = packageRoot()
            .appendingPathComponent("Sources/Bootstrap/Composition/RuntimeCloudInitSeedComposition.swift")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: bootstrapFile.path),
            "Cloud-init seed concrete composition belongs at the Host process boundary, not Bootstrap"
        )

        let hostFile = packageRoot()
            .appendingPathComponent("Sources/Hosts/CLI/ProcessBoundary/RuntimeCloudInitSeedComposition.swift")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: hostFile.path),
            "Cloud-init seed Host process-boundary composition must exist"
        )

        let hostSupportText = try String(
            contentsOf: packageRoot()
                .appendingPathComponent("Sources/Hosts/CLI/ProcessBoundary/RuntimeLifecycle+Support.swift"),
            encoding: .utf8
        )
        for token in [
            "runRequired",
            "hdiutil",
            "Constants.Commands.hdiutil",
        ] {
            XCTAssertTrue(
                hostSupportText.contains(token),
                "Cloud-init seed image process execution must stay at the Host process boundary: \(token)"
            )
        }
    }

    func testRuntimeFreshInstallPreflightProcessObservationDoesNotRemainInBootstrap() throws {
        let bootstrapFile = packageRoot()
            .appendingPathComponent("Sources/Bootstrap/Composition/RuntimeFreshInstallPreflightComposition.swift")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: bootstrapFile.path),
            "Fresh install preflight concrete observation composition belongs at the Host process boundary, not Bootstrap"
        )

        let hostFile = packageRoot()
            .appendingPathComponent("Sources/Hosts/CLI/ProcessBoundary/RuntimeFreshInstallPreflightComposition.swift")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: hostFile.path),
            "Fresh install preflight Host process-boundary composition must exist"
        )
    }

    func testRuntimeVersionStoreFileIOCompositionDoesNotRemainInBootstrap() throws {
        let bootstrapFile = packageRoot()
            .appendingPathComponent("Sources/Bootstrap/Composition/RuntimeVersionStoreComposition.swift")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: bootstrapFile.path),
            "Runtime version file IO composition belongs at the Host process boundary, not Bootstrap"
        )

        let hostFile = packageRoot()
            .appendingPathComponent("Sources/Hosts/CLI/ProcessBoundary/RuntimeVersionStoreComposition.swift")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: hostFile.path),
            "Runtime version store Host process-boundary composition must exist"
        )
    }

    func testVMRuntimeConfigFileIOCompositionDoesNotRemainInBootstrap() throws {
        let bootstrapFile = packageRoot()
            .appendingPathComponent("Sources/Bootstrap/Composition/VMRuntimeConfigComposition.swift")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: bootstrapFile.path),
            "VM runtime config file IO and JSON composition belongs at the Host process boundary, not Bootstrap"
        )

        let hostFile = packageRoot()
            .appendingPathComponent("Sources/Hosts/CLI/ProcessBoundary/VMRuntimeConfigComposition.swift")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: hostFile.path),
            "VM runtime config Host process-boundary composition must exist"
        )
    }

    func testRuntimeRedisBackupExecutionBelongsInWorkflow() throws {
        let root = packageRoot()
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent(
                    "Sources/Workflow/RuntimeRepairLifecycle/RuntimeRedisBackupWorkflow.swift"
                ).path
            ),
            "Redis backup request/wait/status orchestration belongs in Workflow"
        )

        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent(
                    "Sources/Bootstrap/Composition/RuntimeRedisBackupComposition.swift"
                ).path
            ),
            "Redis backup concrete execution must not live in Bootstrap composition"
        )

        let forbiddenFiles = [
            "Sources/Application/UseCases/RepairRuntime/RuntimeRedisBackupWorkflow.swift",
            "Sources/Errors/Definitions/RuntimeRedisBackupWorkflowError.swift",
        ]

        for path in forbiddenFiles {
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path),
                "\(path) must not own redis backup execution or workflow-specific errors"
            )
        }
    }

    func testRuntimeVMDiskRepairExecutionBelongsInWorkflow() {
        let root = packageRoot()
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent(
                    "Sources/Workflow/RuntimeRepairLifecycle/RuntimeVMDiskRepairWorkflow.swift"
                ).path
            ),
            "VM disk repair sequence/status/restart orchestration belongs in Workflow"
        )

        let forbiddenFiles = [
            "Sources/Application/UseCases/RepairRuntime/RunVMDiskRepairUseCase.swift",
            "Sources/Errors/Definitions/RuntimeVMDiskRepairWorkflowError.swift",
        ]

        for path in forbiddenFiles {
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path),
                "\(path) must not own VM disk repair execution or workflow-specific errors"
            )
        }
    }

    func testRuntimeVMDiskRepairWorkflowConsumesExplicitBestEffortResult() throws {
        let file = packageRoot()
            .appendingPathComponent("Sources/Workflow/RuntimeRepairLifecycle/RuntimeVMDiskRepairWorkflow.swift")
        let text = try String(contentsOf: file, encoding: .utf8)

        XCTAssertTrue(text.contains("RuntimeBestEffortOperationResult"))
        for token in [
            "describeError",
            "RuntimeErrorDescription.describe",
        ] {
            XCTAssertFalse(
                text.contains(token),
                "VM disk repair Workflow must consume explicit best-effort failure results, not format thrown errors: \(token)"
            )
        }
    }

    func testRuntimeVMDiskRepairExecutionDoesNotRemainInBootstrap() throws {
        let file = packageRoot()
            .appendingPathComponent("Sources/Bootstrap/Composition/RuntimeVMDiskRepairComposition.swift")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: file.path),
            "VM disk repair concrete execution belongs at the Host process boundary, not Bootstrap"
        )

        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: packageRoot()
                    .appendingPathComponent("Sources/Hosts/CLI/ProcessBoundary/RuntimeVMDiskRepairComposition.swift")
                    .path
            ),
            "VM disk repair Host process-boundary composition must exist"
        )
    }

    func testRuntimeUninstallKeepsStatefulWorkflowOnly() {
        let root = packageRoot()
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent("Sources/Workflow/RuntimeUninstallLifecycle/RuntimeUninstallWorkflow.swift").path
            ),
            "Uninstall state/progress orchestration belongs in Workflow"
        )

        let forbiddenFiles = [
            "Sources/Errors/Definitions/RuntimeUninstallWorkflowError.swift",
        ]

        for path in forbiddenFiles {
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path),
                "\(path) must not own runtime uninstall Workflow-specific errors"
            )
        }
    }

    func testRuntimeUninstallExecutionDoesNotRemainInBootstrap() throws {
        let bootstrapFile = packageRoot()
            .appendingPathComponent("Sources/Bootstrap/Composition/RuntimeUninstallComposition.swift")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: bootstrapFile.path),
            "Runtime uninstall composition belongs at the Host process boundary, not Bootstrap"
        )

        let hostFile = packageRoot()
            .appendingPathComponent("Sources/Hosts/CLI/ProcessBoundary/RuntimeUninstallComposition.swift")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: hostFile.path),
            "Runtime uninstall Host process-boundary composition must exist"
        )

        let workflowFile = packageRoot()
            .appendingPathComponent("Sources/Workflow/RuntimeUninstallLifecycle/RuntimeUninstallWorkflow.swift")
        let workflowText = try String(
            contentsOf: workflowFile,
            encoding: .utf8
        )
        for token in [
            "UninstallRuntimeUseCase()",
            "executeFileRemoval",
            "executeReceiptForgetting",
            "RuntimeUninstallFileRemovalExecutionError",
            "RuntimeUninstallReceiptForgetExecutionError",
            "RuntimeUninstallPreservedPaths",
            "preserveUserData",
            "restorePreservedPaths",
            "restorePreservedDataAfterFailureIfNeeded",
            "safeRemove",
            "receiptForgetDecision",
        ] {
            XCTAssertTrue(
                workflowText.contains(token),
                "Runtime uninstall execution responsibility must remain explicit in Workflow: \(token)"
            )
        }

        let hostSupportText = try String(
            contentsOf: packageRoot()
                .appendingPathComponent("Sources/Hosts/CLI/ProcessBoundary/RuntimeLifecycle+Support.swift"),
            encoding: .utf8
        )
        for token in [
            "runProcess",
            "RuntimePackageReceiptStateReader",
            "Constants.Commands.lsof",
            "Constants.Commands.pkgutil",
        ] {
            XCTAssertTrue(
                hostSupportText.contains(token),
                "Runtime uninstall process observation/execution must stay at Host process boundary: \(token)"
            )
        }
    }

    func testRuntimeWatchdogKeepsRunnerButNotManagedOperationGuardInWorkflow() throws {
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: packageRoot()
                    .appendingPathComponent("Sources/Workflow/RuntimeWatchdog/RuntimeWatchdogRunner.swift")
                    .path
            ),
            "Watchdog runner orchestration belongs in Workflow"
        )

        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: packageRoot()
                    .appendingPathComponent("Sources/Workflow/RuntimeWatchdog/RuntimeManagedOperationGuard.swift")
                    .path
            ),
            "Managed operation guard decision must stay in Application/Bootstrap, not Workflow"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: packageRoot()
                    .appendingPathComponent("Sources/Bootstrap/Composition/RuntimeManagedOperationGuardComposition.swift")
                    .path
            ),
            "Managed operation guard Host composition must not live in Bootstrap"
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: packageRoot()
                    .appendingPathComponent("Sources/Hosts/CLI/ProcessBoundary/RuntimeManagedOperationGuardComposition.swift")
                    .path
            ),
            "Managed operation guard Host process-boundary composition must exist"
        )
    }

    func testRuntimeWatchdogDecisionExecutionDoesNotRemainInBootstrap() throws {
        let bootstrapFile = packageRoot()
            .appendingPathComponent("Sources/Bootstrap/Composition/RuntimeWatchdogRunnerComposition.swift")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: bootstrapFile.path),
            "Watchdog concrete runner composition belongs at the Host process boundary, not Bootstrap"
        )

        let hostFile = packageRoot()
            .appendingPathComponent("Sources/Hosts/CLI/ProcessBoundary/RuntimeWatchdogRunnerComposition.swift")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: hostFile.path),
            "Watchdog Host process-boundary composition must exist"
        )
    }

    func testRuntimeWatchdogWorkflowConsumesExplicitBestEffortResultsForLogPreparation() throws {
        let file = packageRoot()
            .appendingPathComponent("Sources/Workflow/RuntimeWatchdog/RuntimeWatchdogRunner.swift")
        let text = try String(contentsOf: file, encoding: .utf8)

        XCTAssertTrue(text.contains("RuntimeBestEffortOperationResult"))
        for token in [
            "describeError",
            "RuntimeErrorDescription.describe",
            "try operations.createLogsDirectory",
            "try operations.rotateRuntimeLogs",
            "try operations.collectGuestLogs",
        ] {
            XCTAssertFalse(
                text.contains(token),
                "Watchdog Workflow must consume explicit log-preparation results, not format thrown errors: \(token)"
            )
        }
    }

    func testRuntimeApplyBundleExecutionDoesNotRemainInBootstrap() throws {
        let bootstrapFile = packageRoot()
            .appendingPathComponent("Sources/Bootstrap/Composition/RuntimeBundleComposition.swift")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: bootstrapFile.path),
            "Apply bundle concrete execution belongs at the Host process boundary, not Bootstrap"
        )

        let hostFile = packageRoot()
            .appendingPathComponent("Sources/Hosts/CLI/ProcessBoundary/RuntimeBundleComposition.swift")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: hostFile.path),
            "Apply bundle Host process-boundary composition must exist"
        )
    }

    func testRuntimeBundleVerificationIODoesNotRemainInBootstrap() throws {
        let file = packageRoot()
            .appendingPathComponent("Sources/Bootstrap/Composition/RuntimeBundleComposition.swift")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: file.path),
            "Bundle verification file IO must not live in Bootstrap composition"
        )
    }

    func testRuntimeApplyBundlePreflightJudgementDoesNotRemainInBootstrap() throws {
        let file = packageRoot()
            .appendingPathComponent("Sources/Bootstrap/Composition/RuntimeBundleComposition.swift")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: file.path),
            "Apply bundle preflight judgement must not live in Bootstrap composition"
        )
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

    func testRuntimeGuestUpdateWaitExecutionBelongsInWorkflow() throws {
        let requiredFiles = [
            "Sources/Workflow/RuntimeUpdateLifecycle/RuntimeGuestActivationWorkflow.swift",
            "Sources/Workflow/RuntimeUpdateLifecycle/RuntimeGuestShutdownWorkflow.swift",
            "Sources/Hosts/CLI/ProcessBoundary/RuntimeGuestActivationComposition.swift",
            "Sources/Hosts/CLI/ProcessBoundary/RuntimeGuestShutdownComposition.swift",
        ]

        for relativePath in requiredFiles {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: packageRoot().appendingPathComponent(relativePath).path),
                "Guest update activation/shutdown wait execution belongs in Workflow: \(relativePath)"
            )
        }

        let forbiddenFiles = [
            "Sources/Application/UseCases/UpdateRuntime/RuntimeGuestUpdateUseCase.swift",
            "Sources/Application/UseCases/UpdateRuntime/RuntimeGuestUpdateUseCases.swift",
            "Sources/Workflow/RuntimeUpdateLifecycle/RuntimeGuestActivationRunner.swift",
            "Sources/Workflow/RuntimeUpdateLifecycle/RuntimeGuestShutdownRunner.swift",
            "Sources/Errors/Definitions/RuntimeGuestActivationWorkflowError.swift",
            "Sources/Errors/Definitions/RuntimeGuestShutdownWorkflowError.swift",
            "Sources/Bootstrap/Composition/RuntimeGuestActivationComposition.swift",
            "Sources/Bootstrap/Composition/RuntimeGuestShutdownComposition.swift",
        ]

        for relativePath in forbiddenFiles {
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: packageRoot().appendingPathComponent(relativePath).path),
                "Guest update activation/shutdown workflow must not use obsolete placement or workflow-specific errors: \(relativePath)"
            )
        }
    }

    func testRuntimeUpdatePlanningStaysSplitByOperationResponsibility() throws {
        let root = packageRoot()
        let requiredFiles = [
            "Sources/Application/UseCases/UpdateRuntime/ApplyRuntimeBundleUseCase.swift",
            "Sources/Application/UseCases/UpdateRuntime/ApplyRuntimeBundlePreflightUseCase.swift",
            "Sources/Application/UseCases/UpdateRuntime/PrepareRuntimeBundleUseCase.swift",
            "Sources/Application/UseCases/UpdateRuntime/RequireRuntimeGuestCapabilityUseCase.swift",
            "Sources/Application/UseCases/UpdateRuntime/RollbackRuntimeUseCase.swift",
            "Sources/Application/UseCases/UpdateRuntime/RuntimeGuestActivationUseCase.swift",
            "Sources/Application/UseCases/UpdateRuntime/RuntimeGuestShutdownUseCase.swift",
            "Sources/Application/UseCases/UpdateRuntime/RuntimeGuestUpdateSharedPlans.swift",
            "Sources/Application/UseCases/UpdateRuntime/UpdateRuntimeSharedPlans.swift",
        ]

        for path in requiredFiles {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path),
                "Runtime update planning must stay operation-specific: \(path)"
            )
        }

        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent("Sources/Application/UseCases/UpdateRuntime/UpdateRuntimeUseCase.swift").path
            ),
            "UpdateRuntimeUseCase must not return as a mixed apply/rollback/guest planning bucket"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent("Sources/Application/UseCases/UpdateRuntime/RuntimeGuestUpdateUseCase.swift").path
            ),
            "RuntimeGuestUpdateUseCase must not return as a mixed activation/shutdown planning bucket"
        )

        let applyFile = root.appendingPathComponent(
            "Sources/Application/UseCases/UpdateRuntime/ApplyRuntimeBundleUseCase.swift"
        )
        let preflightFile = root.appendingPathComponent(
            "Sources/Application/UseCases/UpdateRuntime/ApplyRuntimeBundlePreflightUseCase.swift"
        )
        let applyText = try String(contentsOf: applyFile, encoding: .utf8)
        let preflightText = try String(contentsOf: preflightFile, encoding: .utf8)
        let preflightJudgementTokens = [
            "preflightManifestPlan(",
            "preflightCapabilityPlan(",
            "storageRequirement(",
            "storagePreflightStagedBundleLogMessage(",
            "replacingRootfsStoragePreflightPlan(",
            "unchangedRootfsStoragePreflightPlan(",
            "rootfsStorageObservationPlan(",
            "rootfsStorageDecision(",
            "missingFileFailureMessage(",
            "backupCreatedLogMessage(",
            "diskHealthDecision(",
        ]

        for token in preflightJudgementTokens {
            XCTAssertFalse(
                applyText.contains(token),
                "ApplyRuntimeBundleUseCase must not reabsorb apply preflight judgement: \(token)"
            )
            XCTAssertTrue(
                preflightText.contains(token),
                "ApplyRuntimeBundlePreflightUseCase must own apply preflight judgement: \(token)"
            )
        }

        let scannedRoots = [
            root.appendingPathComponent("Sources"),
            root.appendingPathComponent("Tests"),
        ]
        let files = try scannedRoots.flatMap { try sourceLikeFiles(root: $0) }
            .filter { !$0.path.contains("/Tests/ArchitectureBoundaryTests/") }
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            XCTAssertFalse(
                text.contains("UpdateRuntimeUseCase("),
                "Callers must depend on operation-specific update usecases instead of UpdateRuntimeUseCase: \(file.path)"
            )
            XCTAssertFalse(
                text.contains("RuntimeGuestUpdateUseCase("),
                "Callers must depend on activation/shutdown-specific guest update usecases instead of RuntimeGuestUpdateUseCase: \(file.path)"
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

    func testRuntimeUpdateLifecycleWorkflowDirectoryHasOnlyWorkflowRunners() throws {
        let updateWorkflowRoot = packageRoot().appendingPathComponent("Sources/Workflow/RuntimeUpdateLifecycle")
        let fileNames = Set(try swiftFiles(root: updateWorkflowRoot).map(\.lastPathComponent))

        XCTAssertEqual(
            fileNames,
            [
                "RuntimeApplyBundleWorkflow.swift",
                "RuntimeGuestActivationWorkflow.swift",
                "RuntimeGuestShutdownWorkflow.swift",
                "RuntimeRollbackWorkflow.swift",
            ],
            "RuntimeUpdateLifecycle Workflow must keep only stateful runners: \(fileNames.sorted())"
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
        let workflowFile = packageRoot().appendingPathComponent(
            "Sources/Workflow/RuntimeUpdateLifecycle/RuntimeGuestCapabilityChecker.swift"
        )

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: workflowFile.path),
            "Guest capability requirement execution belongs in Application usecase, not Workflow"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: packageRoot()
                    .appendingPathComponent("Sources/Bootstrap/Composition/RuntimeGuestCapabilityCheckerComposition.swift")
                    .path
            ),
            "Guest capability Host composition must not live in Bootstrap"
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: packageRoot()
                    .appendingPathComponent("Sources/Hosts/CLI/ProcessBoundary/RuntimeGuestCapabilityCheckerComposition.swift")
                    .path
            ),
            "Guest capability Host process-boundary composition must exist"
        )
    }

    func testRuntimeRollbackKeepsStatefulWorkflowOnly() throws {
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: packageRoot()
                    .appendingPathComponent("Sources/Workflow/RuntimeUpdateLifecycle/RuntimeRollbackWorkflow.swift")
                    .path
            ),
            "Rollback progress/status orchestration belongs in Workflow"
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: packageRoot()
                    .appendingPathComponent("Sources/Hosts/CLI/ProcessBoundary/RuntimeRollbackComposition.swift")
                    .path
            ),
            "Rollback Host process-boundary composition must exist"
        )

        let forbiddenFiles = [
            "Sources/Workflow/RuntimeUpdateLifecycle/RuntimeRollbackPreflightRunner.swift",
            "Sources/Workflow/RuntimeUpdateLifecycle/RuntimeRollbackRunner.swift",
            "Sources/Workflow/RuntimeUpdateLifecycle/RuntimeRollbackStepExecutor.swift",
            "Sources/Errors/Definitions/RuntimeRollbackWorkflowError.swift",
        ]

        for relativePath in forbiddenFiles {
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: packageRoot().appendingPathComponent(relativePath).path),
                "Rollback Workflow must not own preflight runners, step executors, or Workflow-specific errors: \(relativePath)"
            )
        }
    }

    func testRuntimeRollbackStepExecutionDoesNotRemainInBootstrap() throws {
        let file = packageRoot()
            .appendingPathComponent("Sources/Bootstrap/Composition/RuntimeRollbackComposition.swift")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: file.path),
            "Rollback concrete execution belongs at the Host process boundary, not Bootstrap"
        )
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

    private func emptyDirectories(root: URL) throws -> [URL] {
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return []
        }

        let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        return try enumerator?.compactMap { item in
            guard let url = item as? URL else { return nil }
            let values = try url.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory == true else { return nil }
            let children = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            return children.isEmpty ? url : nil
        } ?? []
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
