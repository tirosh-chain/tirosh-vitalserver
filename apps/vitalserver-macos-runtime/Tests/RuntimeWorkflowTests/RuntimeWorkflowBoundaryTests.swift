import XCTest

final class RuntimeWorkflowBoundaryTests: XCTestCase {
    func testIdealLayerSkeletonExistsAsSwiftPMTargetsAndFolders() throws {
        let sourcesRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources")
        let packageManifest = try String(
            contentsOf: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Package.swift"),
            encoding: .utf8
        )
        let layerFolders: [String: [String]] = [
            "Domain": ["Models", "Policies", "StateMachines", "Invariants"],
            "Application": ["UseCases", "Ports"],
            "Workflow": [
                "RuntimeServiceLifecycle",
                "RuntimeHealth",
                "RuntimeConfigureLifecycle",
                "RuntimeInstallLifecycle",
                "RuntimeUpdateLifecycle",
                "RuntimeUninstallLifecycle",
                "RuntimeRepairLifecycle",
                "RuntimeWatchdog",
                "RuntimeShared",
            ],
            "Infrastructure": ["FileSystem", "Repositories", "ObservabilityStore", "PackageReceipts"],
            "HostAdapters": ["Launchd", "Process", "Hdiutil", "Pkgutil", "Virtualization", "CloudInit"],
            "Interfaces": ["HostCLI", "RuntimeControlAPI", "MacRuntimeControlApp"],
            "Bootstrap": ["DI", "Composition"],
        ]

        for (layer, responsibilityFolders) in layerFolders {
            XCTAssertTrue(
                packageManifest.contains("name: \"\(layer)\""),
                "Package.swift must declare the ideal layer target \(layer)"
            )

            let layerRoot = sourcesRoot.appendingPathComponent(layer)
            assertDirectoryExists(layerRoot, "ideal layer root is missing: \(layer)")
            for folder in responsibilityFolders {
                assertDirectoryExists(
                    layerRoot.appendingPathComponent(folder),
                    "ideal layer responsibility folder is missing: \(layer)/\(folder)"
                )
            }
        }
    }

    func testIdealLayerSwiftPMTargetGraphPreservesDependencyDirection() throws {
        let packageManifest = try String(
            contentsOf: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Package.swift"),
            encoding: .utf8
        )

        assertTarget(
            "Domain",
            in: packageManifest,
            includesDependencies: ["Contracts"],
            excludesDependencies: ["Application", "Workflow", "Infrastructure", "HostAdapters", "Interfaces", "Bootstrap"]
        )
        assertTarget(
            "Application",
            in: packageManifest,
            includesDependencies: ["Contracts", "Domain"],
            excludesDependencies: ["Core", "Workflow", "Infrastructure", "HostAdapters", "Interfaces", "Bootstrap"]
        )
        assertTarget(
            "Workflow",
            in: packageManifest,
            includesDependencies: ["Contracts", "Domain", "Application"],
            excludesDependencies: ["Infrastructure", "HostAdapters", "Interfaces", "Bootstrap"]
        )
        assertTarget(
            "Infrastructure",
            in: packageManifest,
            includesDependencies: ["Contracts", "Domain", "Application", "Workflow"],
            excludesDependencies: ["HostAdapters", "Interfaces", "Bootstrap"]
        )
        assertTarget(
            "HostAdapters",
            in: packageManifest,
            includesDependencies: ["Contracts", "Domain", "Application", "Workflow"],
            excludesDependencies: ["Infrastructure", "Interfaces", "Bootstrap"]
        )
        assertTarget(
            "Interfaces",
            in: packageManifest,
            includesDependencies: ["Contracts", "Domain", "Application", "Workflow"],
            excludesDependencies: ["Infrastructure", "HostAdapters", "Bootstrap"]
        )
        assertTarget(
            "Bootstrap",
            in: packageManifest,
            includesDependencies: [
                "Contracts",
                "Domain",
                "Application",
                "Workflow",
                "Infrastructure",
                "HostAdapters",
                "Interfaces",
            ],
            excludesDependencies: []
        )
    }

    func testHostCLIPathCompositionLivesInBootstrapWithHostCLIAliasOnly() throws {
        let sourcesRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources")
        let packageManifest = try String(
            contentsOf: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Package.swift"),
            encoding: .utf8
        )
        let bootstrapFile = sourcesRoot.appendingPathComponent("Bootstrap/Composition/LauncherPaths.swift")
        let hostCLIFile = sourcesRoot.appendingPathComponent("HostCLI/Runtime/LauncherPaths.swift")

        assertFileExists(bootstrapFile, "LauncherPaths path composition must live in Bootstrap")
        assertFileExists(hostCLIFile, "LauncherPaths HostCLI shim must remain explicit")

        let bootstrapContents = try String(contentsOf: bootstrapFile, encoding: .utf8)
        let hostCLIContents = try String(contentsOf: hostCLIFile, encoding: .utf8)
        XCTAssertTrue(bootstrapContents.contains("public struct LauncherPaths"))
        XCTAssertFalse(bootstrapContents.contains("import HostCLI"))
        XCTAssertFalse(bootstrapContents.contains("Constants."))
        XCTAssertTrue(hostCLIContents.contains("typealias LauncherPaths = Bootstrap.LauncherPaths"))
        XCTAssertFalse(hostCLIContents.contains("struct LauncherPaths"))

        assertTarget(
            "HostCLI",
            in: packageManifest,
            includesDependencies: ["Bootstrap"],
            excludesDependencies: []
        )
    }

    func testRuntimeConstantsLiveInBootstrapWithHostCLIAliasOnly() throws {
        let packageRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let sourcesRoot = packageRoot.appendingPathComponent("Sources")
        let bootstrapConstantsFile = sourcesRoot.appendingPathComponent("Bootstrap/Composition/Constants.swift")
        let bootstrapGeneratedVersionFile = sourcesRoot.appendingPathComponent("Bootstrap/Composition/GeneratedVersion.swift")
        let hostCLIConstantsFile = sourcesRoot.appendingPathComponent("HostCLI/Runtime/Constants.swift")
        let hostCLIGeneratedVersionFile = sourcesRoot.appendingPathComponent("HostCLI/Runtime/GeneratedVersion.swift")
        let syncReleaseScript = packageRoot.appendingPathComponent("Support/Build/sync-release.py")

        assertFileExists(bootstrapConstantsFile, "runtime constants must live in Bootstrap")
        assertFileExists(bootstrapGeneratedVersionFile, "generated helper version constants must live in Bootstrap")
        assertFileExists(hostCLIConstantsFile, "Constants HostCLI shim must remain explicit")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: hostCLIGeneratedVersionFile.path),
            "HostCLI must not retain generated version ownership"
        )

        let bootstrapConstantsContents = try String(contentsOf: bootstrapConstantsFile, encoding: .utf8)
        let bootstrapGeneratedVersionContents = try String(contentsOf: bootstrapGeneratedVersionFile, encoding: .utf8)
        let hostCLIConstantsContents = try String(contentsOf: hostCLIConstantsFile, encoding: .utf8)
        let syncReleaseContents = try String(contentsOf: syncReleaseScript, encoding: .utf8)

        XCTAssertTrue(bootstrapConstantsContents.contains("public enum Constants"))
        XCTAssertFalse(bootstrapConstantsContents.contains("import HostCLI"))
        XCTAssertFalse(bootstrapConstantsContents.contains("import Core"))
        XCTAssertTrue(bootstrapGeneratedVersionContents.contains("public extension Constants"))
        XCTAssertTrue(hostCLIConstantsContents.contains("typealias Constants = Bootstrap.Constants"))
        XCTAssertFalse(hostCLIConstantsContents.contains("enum Constants"))
        XCTAssertTrue(syncReleaseContents.contains("Sources/Bootstrap/Composition/GeneratedVersion.swift"))
        XCTAssertFalse(syncReleaseContents.contains("Sources/HostCLI/Runtime/GeneratedVersion.swift"))
    }

    func testRuntimeLifecycleCompositionLivesInBootstrapWithHostCLIAliasOnly() throws {
        let sourcesRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources")
        let bootstrapFile = sourcesRoot.appendingPathComponent("Bootstrap/Composition/RuntimeLifecycleComposition.swift")
        let hostCLIFile = sourcesRoot.appendingPathComponent("HostCLI/Runtime/RuntimeLifecycleComposition.swift")

        assertFileExists(bootstrapFile, "runtime lifecycle dependency wiring must live in Bootstrap")
        assertFileExists(hostCLIFile, "RuntimeLifecycleComposition HostCLI shim must remain explicit")

        let bootstrapContents = try String(contentsOf: bootstrapFile, encoding: .utf8)
        let hostCLIContents = try String(contentsOf: hostCLIFile, encoding: .utf8)

        XCTAssertTrue(bootstrapContents.contains("public struct RuntimeLifecycleComposition"))
        XCTAssertTrue(bootstrapContents.contains("public static func resolve"))
        XCTAssertFalse(bootstrapContents.contains("import HostCLI"))
        XCTAssertFalse(bootstrapContents.contains("import Core"))
        XCTAssertFalse(bootstrapContents.contains("import HostInfrastructure"))
        XCTAssertTrue(hostCLIContents.contains("typealias RuntimeLifecycleComposition = Bootstrap.RuntimeLifecycleComposition"))
        XCTAssertFalse(hostCLIContents.contains("struct RuntimeLifecycleComposition"))
        XCTAssertFalse(hostCLIContents.contains("static func resolve"))
    }

    func testRuntimeBundleCompositionLivesInBootstrapWithHostCLIAliasesOnly() throws {
        let sourcesRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources")
        let bootstrapFile = sourcesRoot.appendingPathComponent("Bootstrap/Composition/RuntimeBundleComposition.swift")
        let hostCLIFile = sourcesRoot.appendingPathComponent("HostCLI/Runtime/RuntimeBundleComposition.swift")

        assertFileExists(bootstrapFile, "update bundle composition wiring must live in Bootstrap")
        assertFileExists(hostCLIFile, "RuntimeBundleComposition HostCLI shim must remain explicit")

        let bootstrapContents = try String(contentsOf: bootstrapFile, encoding: .utf8)
        let hostCLIContents = try String(contentsOf: hostCLIFile, encoding: .utf8)

        XCTAssertTrue(bootstrapContents.contains("public struct RuntimeBundleCompositionContext"))
        XCTAssertTrue(bootstrapContents.contains("public struct RuntimeBundleCompositionOperations"))
        XCTAssertTrue(bootstrapContents.contains("public struct RuntimeBundleComposition"))
        XCTAssertFalse(bootstrapContents.contains("import HostCLI"))
        XCTAssertFalse(bootstrapContents.contains("import Core"))
        XCTAssertFalse(bootstrapContents.contains("import HostInfrastructure"))
        XCTAssertTrue(hostCLIContents.contains("typealias RuntimeBundleCompositionContext = Bootstrap.RuntimeBundleCompositionContext"))
        XCTAssertTrue(hostCLIContents.contains("typealias RuntimeBundleCompositionOperations = Bootstrap.RuntimeBundleCompositionOperations"))
        XCTAssertTrue(hostCLIContents.contains("typealias RuntimeBundleComposition = Bootstrap.RuntimeBundleComposition"))
        XCTAssertFalse(hostCLIContents.contains("struct RuntimeBundleComposition"))
    }

    func testRuntimeGuestUpdateCompositionsLiveInBootstrapWithHostCLIAliasesOnly() throws {
        let sourcesRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources")
        let activationBootstrapFile = sourcesRoot
            .appendingPathComponent("Bootstrap/Composition/RuntimeGuestActivationComposition.swift")
        let activationHostCLIFile = sourcesRoot
            .appendingPathComponent("HostCLI/Runtime/RuntimeGuestActivationComposition.swift")
        let shutdownBootstrapFile = sourcesRoot
            .appendingPathComponent("Bootstrap/Composition/RuntimeGuestShutdownComposition.swift")
        let shutdownHostCLIFile = sourcesRoot
            .appendingPathComponent("HostCLI/Runtime/RuntimeGuestShutdownComposition.swift")
        let hostCLIWorkflowFile = sourcesRoot.appendingPathComponent("HostCLI/Runtime/RuntimeLifecycle+Workflows.swift")

        assertFileExists(activationBootstrapFile, "guest activation composition must live in Bootstrap")
        assertFileExists(activationHostCLIFile, "RuntimeGuestActivationComposition HostCLI shim must remain explicit")
        assertFileExists(shutdownBootstrapFile, "guest shutdown composition must live in Bootstrap")
        assertFileExists(shutdownHostCLIFile, "RuntimeGuestShutdownComposition HostCLI shim must remain explicit")

        let activationBootstrapContents = try String(contentsOf: activationBootstrapFile, encoding: .utf8)
        let activationHostCLIContents = try String(contentsOf: activationHostCLIFile, encoding: .utf8)
        let shutdownBootstrapContents = try String(contentsOf: shutdownBootstrapFile, encoding: .utf8)
        let shutdownHostCLIContents = try String(contentsOf: shutdownHostCLIFile, encoding: .utf8)
        let hostCLIWorkflowContents = try String(contentsOf: hostCLIWorkflowFile, encoding: .utf8)
        guard let activationStart = hostCLIWorkflowContents.range(of: "func runtimeGuestActivationWorkflow()"),
              let activationEnd = hostCLIWorkflowContents.range(
                  of: "func prepareGuestShutdownForUpdate",
                  range: activationStart.upperBound..<hostCLIWorkflowContents.endIndex
              ),
              let shutdownEnd = hostCLIWorkflowContents.range(
                  of: "func requireGuestCapability",
                  range: activationEnd.upperBound..<hostCLIWorkflowContents.endIndex
              )
        else {
            XCTFail("HostCLI guest activation/shutdown helpers must remain discoverable")
            return
        }
        let hostCLIActivationContents = String(hostCLIWorkflowContents[activationStart.lowerBound..<activationEnd.lowerBound])
        let hostCLIShutdownContents = String(hostCLIWorkflowContents[activationEnd.lowerBound..<shutdownEnd.lowerBound])

        XCTAssertTrue(activationBootstrapContents.contains("public struct RuntimeGuestActivationCompositionContext"))
        XCTAssertTrue(activationBootstrapContents.contains("public struct RuntimeGuestActivationCompositionOperations"))
        XCTAssertTrue(activationBootstrapContents.contains("public struct RuntimeGuestActivationComposition"))
        XCTAssertTrue(activationBootstrapContents.contains("RuntimeGuestActivationWorkflow("))
        XCTAssertTrue(activationBootstrapContents.contains("RuntimeGuestActivationWorkflowContext("))
        XCTAssertTrue(activationBootstrapContents.contains("RuntimeGuestActivationWorkflowOperations("))
        XCTAssertTrue(activationBootstrapContents.contains("Constants.Runtime.updateActivationWaitTimeoutSeconds"))
        XCTAssertTrue(activationBootstrapContents.contains("guestGateway.removeUpdateActivationResult()"))
        XCTAssertTrue(activationBootstrapContents.contains("guestGateway.writeUpdateActivationRequest"))
        XCTAssertTrue(activationBootstrapContents.contains("guestGateway.loadUpdateActivationResultDocument()"))
        XCTAssertFalse(activationBootstrapContents.contains("import HostCLI"))
        XCTAssertFalse(activationBootstrapContents.contains("import Core"))
        XCTAssertFalse(activationBootstrapContents.contains("import HostInfrastructure"))
        XCTAssertTrue(activationHostCLIContents.contains(
            "typealias RuntimeGuestActivationCompositionContext = Bootstrap.RuntimeGuestActivationCompositionContext"
        ))
        XCTAssertTrue(activationHostCLIContents.contains(
            "typealias RuntimeGuestActivationCompositionOperations = Bootstrap.RuntimeGuestActivationCompositionOperations"
        ))
        XCTAssertTrue(activationHostCLIContents.contains(
            "typealias RuntimeGuestActivationComposition = Bootstrap.RuntimeGuestActivationComposition"
        ))
        XCTAssertFalse(activationHostCLIContents.contains("struct RuntimeGuestActivationComposition"))
        XCTAssertTrue(hostCLIActivationContents.contains("RuntimeGuestActivationComposition("))
        XCTAssertFalse(hostCLIActivationContents.contains("RuntimeGuestActivationWorkflow("))
        XCTAssertFalse(hostCLIActivationContents.contains("RuntimeGuestActivationWorkflowContext("))
        XCTAssertFalse(hostCLIActivationContents.contains("RuntimeGuestActivationWorkflowOperations("))
        XCTAssertFalse(hostCLIActivationContents.contains("Constants.Runtime.updateActivationWaitTimeoutSeconds"))
        XCTAssertFalse(hostCLIActivationContents.contains("removeUpdateActivationResult"))
        XCTAssertFalse(hostCLIActivationContents.contains("writeUpdateActivationRequest"))
        XCTAssertFalse(hostCLIActivationContents.contains("loadUpdateActivationResultDocument"))

        XCTAssertTrue(shutdownBootstrapContents.contains("public struct RuntimeGuestShutdownCompositionContext"))
        XCTAssertTrue(shutdownBootstrapContents.contains("public struct RuntimeGuestShutdownCompositionOperations"))
        XCTAssertTrue(shutdownBootstrapContents.contains("public struct RuntimeGuestShutdownComposition"))
        XCTAssertTrue(shutdownBootstrapContents.contains("RuntimeGuestShutdownWorkflow("))
        XCTAssertTrue(shutdownBootstrapContents.contains("RuntimeGuestShutdownWorkflowContext("))
        XCTAssertTrue(shutdownBootstrapContents.contains("RuntimeGuestShutdownWorkflowOperations("))
        XCTAssertTrue(shutdownBootstrapContents.contains("Constants.Runtime.updateShutdownWaitTimeoutSeconds"))
        XCTAssertTrue(shutdownBootstrapContents.contains("guestGateway.removeUpdateShutdownResult()"))
        XCTAssertTrue(shutdownBootstrapContents.contains("guestGateway.writeUpdateShutdownRequest"))
        XCTAssertTrue(shutdownBootstrapContents.contains("guestGateway.loadUpdateShutdownResultDocument()"))
        XCTAssertFalse(shutdownBootstrapContents.contains("import HostCLI"))
        XCTAssertFalse(shutdownBootstrapContents.contains("import Core"))
        XCTAssertFalse(shutdownBootstrapContents.contains("import HostInfrastructure"))
        XCTAssertTrue(shutdownHostCLIContents.contains(
            "typealias RuntimeGuestShutdownCompositionContext = Bootstrap.RuntimeGuestShutdownCompositionContext"
        ))
        XCTAssertTrue(shutdownHostCLIContents.contains(
            "typealias RuntimeGuestShutdownCompositionOperations = Bootstrap.RuntimeGuestShutdownCompositionOperations"
        ))
        XCTAssertTrue(shutdownHostCLIContents.contains(
            "typealias RuntimeGuestShutdownComposition = Bootstrap.RuntimeGuestShutdownComposition"
        ))
        XCTAssertFalse(shutdownHostCLIContents.contains("struct RuntimeGuestShutdownComposition"))
        XCTAssertTrue(hostCLIShutdownContents.contains("RuntimeGuestShutdownComposition("))
        XCTAssertFalse(hostCLIShutdownContents.contains("RuntimeGuestShutdownWorkflow("))
        XCTAssertFalse(hostCLIShutdownContents.contains("RuntimeGuestShutdownWorkflowContext("))
        XCTAssertFalse(hostCLIShutdownContents.contains("RuntimeGuestShutdownWorkflowOperations("))
        XCTAssertFalse(hostCLIShutdownContents.contains("Constants.Runtime.updateShutdownWaitTimeoutSeconds"))
        XCTAssertFalse(hostCLIShutdownContents.contains("removeUpdateShutdownResult"))
        XCTAssertFalse(hostCLIShutdownContents.contains("writeUpdateShutdownRequest"))
        XCTAssertFalse(hostCLIShutdownContents.contains("loadUpdateShutdownResultDocument"))
    }

    func testRuntimeInstallCompositionLivesInBootstrapWithHostCLIAliasesOnly() throws {
        let sourcesRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources")
        let bootstrapFile = sourcesRoot.appendingPathComponent("Bootstrap/Composition/RuntimeInstallComposition.swift")
        let hostCLIFile = sourcesRoot.appendingPathComponent("HostCLI/Runtime/RuntimeInstallComposition.swift")

        assertFileExists(bootstrapFile, "install composition wiring must live in Bootstrap")
        assertFileExists(hostCLIFile, "RuntimeInstallComposition HostCLI shim must remain explicit")

        let bootstrapContents = try String(contentsOf: bootstrapFile, encoding: .utf8)
        let hostCLIContents = try String(contentsOf: hostCLIFile, encoding: .utf8)

        XCTAssertTrue(bootstrapContents.contains("public struct RuntimeInstallCompositionContext"))
        XCTAssertTrue(bootstrapContents.contains("public struct RuntimeInstallCompositionOperations"))
        XCTAssertTrue(bootstrapContents.contains("public struct RuntimeInstallComposition"))
        XCTAssertFalse(bootstrapContents.contains("import HostCLI"))
        XCTAssertFalse(bootstrapContents.contains("import Core"))
        XCTAssertFalse(bootstrapContents.contains("import HostInfrastructure"))
        XCTAssertFalse(bootstrapContents.contains("InstallSettings.default"))
        XCTAssertFalse(bootstrapContents.contains(".hostCLI"))
        XCTAssertFalse(bootstrapContents.contains("service.launchDaemonPlist"))
        XCTAssertTrue(hostCLIContents.contains("typealias RuntimeInstallCompositionContext = Bootstrap.RuntimeInstallCompositionContext"))
        XCTAssertTrue(hostCLIContents.contains("typealias RuntimeInstallCompositionOperations = Bootstrap.RuntimeInstallCompositionOperations"))
        XCTAssertTrue(hostCLIContents.contains("typealias RuntimeInstallComposition = Bootstrap.RuntimeInstallComposition"))
        XCTAssertFalse(hostCLIContents.contains("struct RuntimeInstallComposition"))
    }

    func testRuntimeManagedServicePathsLiveInBootstrapWithHostCLIExtensionShimOnly() throws {
        let sourcesRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources")
        let bootstrapFile = sourcesRoot.appendingPathComponent("Bootstrap/Composition/RuntimeManagedServicePaths.swift")
        let hostCLIFile = sourcesRoot.appendingPathComponent("HostCLI/Runtime/RuntimeManagedService+Launchd.swift")
        let lifecycleCompositionFile = sourcesRoot.appendingPathComponent("Bootstrap/Composition/RuntimeLifecycleComposition.swift")
        let installCompositionFile = sourcesRoot.appendingPathComponent("Bootstrap/Composition/RuntimeInstallComposition.swift")

        assertFileExists(bootstrapFile, "managed-service product path composition must live in Bootstrap")
        assertFileExists(hostCLIFile, "RuntimeManagedService HostCLI extension shim must remain explicit")

        let bootstrapContents = try String(contentsOf: bootstrapFile, encoding: .utf8)
        let hostCLIContents = try String(contentsOf: hostCLIFile, encoding: .utf8)
        let lifecycleCompositionContents = try String(contentsOf: lifecycleCompositionFile, encoding: .utf8)
        let installCompositionContents = try String(contentsOf: installCompositionFile, encoding: .utf8)

        XCTAssertTrue(bootstrapContents.contains("public enum RuntimeManagedServicePaths"))
        XCTAssertTrue(bootstrapContents.contains("public static func launchDaemonPlist"))
        XCTAssertTrue(bootstrapContents.contains("public static func displayName"))
        XCTAssertFalse(bootstrapContents.contains("import HostCLI"))
        XCTAssertFalse(bootstrapContents.contains("import Core"))
        XCTAssertFalse(bootstrapContents.contains("import HostInfrastructure"))
        XCTAssertTrue(hostCLIContents.contains("RuntimeManagedServicePaths.launchDaemonPlist(self)"))
        XCTAssertTrue(hostCLIContents.contains("RuntimeManagedServicePaths.displayName(self)"))
        XCTAssertFalse(hostCLIContents.contains("Constants.InstallPaths.launchDaemons"))
        XCTAssertFalse(hostCLIContents.contains("import Core"))
        XCTAssertTrue(lifecycleCompositionContents.contains("RuntimeManagedServicePaths.launchDaemonPlist"))
        XCTAssertTrue(installCompositionContents.contains("RuntimeManagedServicePaths.launchDaemonPlist"))
        XCTAssertFalse(lifecycleCompositionContents.contains("private static func launchDaemonPlist"))
        XCTAssertFalse(installCompositionContents.contains("private func launchDaemonPlist"))
    }

    func testRuntimeCloudInitSeedCompositionLivesInBootstrapWithHostCLIAliasOnly() throws {
        let sourcesRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources")
        let bootstrapFile = sourcesRoot.appendingPathComponent("Bootstrap/Composition/RuntimeCloudInitSeedComposition.swift")
        let hostCLIShimFile = sourcesRoot.appendingPathComponent("HostCLI/Runtime/RuntimeCloudInitSeedComposition.swift")
        let hostCLIWorkflowFile = sourcesRoot.appendingPathComponent("HostCLI/Runtime/RuntimeLifecycle+Workflows.swift")
        let installCompositionFile = sourcesRoot.appendingPathComponent("Bootstrap/Composition/RuntimeInstallComposition.swift")

        assertFileExists(bootstrapFile, "cloud-init seed writer product composition must live in Bootstrap")
        assertFileExists(hostCLIShimFile, "RuntimeCloudInitSeedComposition HostCLI shim must remain explicit")

        let bootstrapContents = try String(contentsOf: bootstrapFile, encoding: .utf8)
        let hostCLIShimContents = try String(contentsOf: hostCLIShimFile, encoding: .utf8)
        let hostCLIWorkflowContents = try String(contentsOf: hostCLIWorkflowFile, encoding: .utf8)
        let installCompositionContents = try String(contentsOf: installCompositionFile, encoding: .utf8)

        XCTAssertTrue(bootstrapContents.contains("public enum RuntimeCloudInitSeedComposition"))
        XCTAssertTrue(bootstrapContents.contains("public static func make"))
        XCTAssertTrue(bootstrapContents.contains("public static func context"))
        XCTAssertTrue(bootstrapContents.contains("public static func operations"))
        XCTAssertTrue(bootstrapContents.contains("public static func defaultInstanceID"))
        XCTAssertTrue(bootstrapContents.contains("Constants.BootAssets.cloudInit"))
        XCTAssertTrue(bootstrapContents.contains("Constants.Commands.hdiutil"))
        XCTAssertFalse(bootstrapContents.contains("import HostCLI"))
        XCTAssertFalse(bootstrapContents.contains("import Core"))
        XCTAssertFalse(bootstrapContents.contains("import HostInfrastructure"))
        XCTAssertTrue(hostCLIShimContents.contains(
            "typealias RuntimeCloudInitSeedComposition = Bootstrap.RuntimeCloudInitSeedComposition"
        ))
        XCTAssertFalse(hostCLIShimContents.contains("enum RuntimeCloudInitSeedComposition"))
        XCTAssertTrue(hostCLIWorkflowContents.contains("RuntimeCloudInitSeedComposition.make"))
        XCTAssertFalse(hostCLIWorkflowContents.contains("RuntimeCloudInitSeedContext("))
        XCTAssertFalse(hostCLIWorkflowContents.contains("RuntimeCloudInitSeedOperations("))
        XCTAssertFalse(hostCLIWorkflowContents.contains("Constants.BootAssets.cloudInit"))
        XCTAssertTrue(installCompositionContents.contains("RuntimeCloudInitSeedComposition.make"))
        XCTAssertFalse(installCompositionContents.contains("RuntimeCloudInitSeedContext("))
        XCTAssertFalse(installCompositionContents.contains("RuntimeCloudInitSeedOperations("))
        XCTAssertFalse(installCompositionContents.contains("Constants.BootAssets.cloudInit"))
    }

    func testRuntimeServiceControlCompositionLivesInBootstrapWithHostCLIAliasesOnly() throws {
        let sourcesRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources")
        let bootstrapFile = sourcesRoot.appendingPathComponent("Bootstrap/Composition/RuntimeServiceControlComposition.swift")
        let hostCLIShimFile = sourcesRoot.appendingPathComponent("HostCLI/Runtime/RuntimeServiceControlComposition.swift")
        let hostCLIWorkflowFile = sourcesRoot.appendingPathComponent("HostCLI/Runtime/RuntimeLifecycle+Workflows.swift")

        assertFileExists(bootstrapFile, "service-control runner composition must live in Bootstrap")
        assertFileExists(hostCLIShimFile, "RuntimeServiceControlComposition HostCLI shim must remain explicit")

        let bootstrapContents = try String(contentsOf: bootstrapFile, encoding: .utf8)
        let hostCLIShimContents = try String(contentsOf: hostCLIShimFile, encoding: .utf8)
        let hostCLIWorkflowContents = try String(contentsOf: hostCLIWorkflowFile, encoding: .utf8)

        XCTAssertTrue(bootstrapContents.contains("public struct RuntimeServiceControlCompositionOperations"))
        XCTAssertTrue(bootstrapContents.contains("public enum RuntimeServiceControlComposition"))
        XCTAssertTrue(bootstrapContents.contains("public static func make"))
        XCTAssertTrue(bootstrapContents.contains("RuntimeServiceControlRunner("))
        XCTAssertTrue(bootstrapContents.contains("Dictionary(uniqueKeysWithValues: services.map"))
        XCTAssertFalse(bootstrapContents.contains("import HostCLI"))
        XCTAssertFalse(bootstrapContents.contains("import Core"))
        XCTAssertFalse(bootstrapContents.contains("import HostInfrastructure"))
        XCTAssertTrue(hostCLIShimContents.contains(
            "typealias RuntimeServiceControlCompositionOperations = Bootstrap.RuntimeServiceControlCompositionOperations"
        ))
        XCTAssertTrue(hostCLIShimContents.contains(
            "typealias RuntimeServiceControlComposition = Bootstrap.RuntimeServiceControlComposition"
        ))
        XCTAssertFalse(hostCLIShimContents.contains("struct RuntimeServiceControlCompositionOperations"))
        XCTAssertTrue(hostCLIWorkflowContents.contains("RuntimeServiceControlComposition.make"))
        XCTAssertFalse(hostCLIWorkflowContents.contains("RuntimeServiceControlRunner("))
        XCTAssertFalse(hostCLIWorkflowContents.contains("serviceStates:"))
        XCTAssertFalse(hostCLIWorkflowContents.contains("Dictionary(uniqueKeysWithValues: services.map"))
    }

    func testRuntimeStatusPrinterCompositionLivesInBootstrapWithHostCLIAliasesOnly() throws {
        let sourcesRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources")
        let bootstrapFile = sourcesRoot.appendingPathComponent("Bootstrap/Composition/RuntimeStatusPrinterComposition.swift")
        let hostCLIShimFile = sourcesRoot.appendingPathComponent("HostCLI/Runtime/RuntimeStatusPrinterComposition.swift")
        let hostCLIWorkflowFile = sourcesRoot.appendingPathComponent("HostCLI/Runtime/RuntimeLifecycle+Workflows.swift")

        assertFileExists(bootstrapFile, "status printer composition must live in Bootstrap")
        assertFileExists(hostCLIShimFile, "RuntimeStatusPrinterComposition HostCLI shim must remain explicit")

        let bootstrapContents = try String(contentsOf: bootstrapFile, encoding: .utf8)
        let hostCLIShimContents = try String(contentsOf: hostCLIShimFile, encoding: .utf8)
        let hostCLIWorkflowContents = try String(contentsOf: hostCLIWorkflowFile, encoding: .utf8)

        XCTAssertTrue(bootstrapContents.contains("public struct RuntimeStatusPrinterCompositionContext"))
        XCTAssertTrue(bootstrapContents.contains("public struct RuntimeStatusPrinterCompositionOperations"))
        XCTAssertTrue(bootstrapContents.contains("public enum RuntimeStatusPrinterComposition"))
        XCTAssertTrue(bootstrapContents.contains("public static func make"))
        XCTAssertTrue(bootstrapContents.contains("RuntimeStatusPrinter("))
        XCTAssertTrue(bootstrapContents.contains("Constants.InstallPaths.vmBin"))
        XCTAssertTrue(bootstrapContents.contains("Constants.InstallPaths.proxyRun"))
        XCTAssertTrue(bootstrapContents.contains("Constants.Runtime.proxyHealthURL"))
        XCTAssertFalse(bootstrapContents.contains("import HostCLI"))
        XCTAssertFalse(bootstrapContents.contains("import Core"))
        XCTAssertFalse(bootstrapContents.contains("import HostInfrastructure"))
        XCTAssertTrue(hostCLIShimContents.contains(
            "typealias RuntimeStatusPrinterCompositionContext = Bootstrap.RuntimeStatusPrinterCompositionContext"
        ))
        XCTAssertTrue(hostCLIShimContents.contains(
            "typealias RuntimeStatusPrinterCompositionOperations = Bootstrap.RuntimeStatusPrinterCompositionOperations"
        ))
        XCTAssertTrue(hostCLIShimContents.contains(
            "typealias RuntimeStatusPrinterComposition = Bootstrap.RuntimeStatusPrinterComposition"
        ))
        XCTAssertFalse(hostCLIShimContents.contains("struct RuntimeStatusPrinterCompositionContext"))
        XCTAssertTrue(hostCLIWorkflowContents.contains("RuntimeStatusPrinterComposition.make"))
        XCTAssertFalse(hostCLIWorkflowContents.contains("RuntimeStatusPrinter("))
        XCTAssertFalse(hostCLIWorkflowContents.contains("Constants.InstallPaths.vmBin"))
        XCTAssertFalse(hostCLIWorkflowContents.contains("Constants.InstallPaths.proxyRun"))
        XCTAssertFalse(hostCLIWorkflowContents.contains("Constants.Runtime.proxyHealthURL"))
    }

    func testRuntimeHealthCheckRunnerCompositionLivesInBootstrapWithHostCLIAliasesOnly() throws {
        let sourcesRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources")
        let bootstrapFile = sourcesRoot.appendingPathComponent("Bootstrap/Composition/RuntimeHealthCheckRunnerComposition.swift")
        let hostCLIShimFile = sourcesRoot.appendingPathComponent("HostCLI/Runtime/RuntimeHealthCheckRunnerComposition.swift")
        let hostCLIWorkflowFile = sourcesRoot.appendingPathComponent("HostCLI/Runtime/RuntimeLifecycle+Workflows.swift")

        assertFileExists(bootstrapFile, "health-check runner composition must live in Bootstrap")
        assertFileExists(hostCLIShimFile, "RuntimeHealthCheckRunnerComposition HostCLI shim must remain explicit")

        let bootstrapContents = try String(contentsOf: bootstrapFile, encoding: .utf8)
        let hostCLIShimContents = try String(contentsOf: hostCLIShimFile, encoding: .utf8)
        let hostCLIWorkflowContents = try String(contentsOf: hostCLIWorkflowFile, encoding: .utf8)

        XCTAssertTrue(bootstrapContents.contains("public struct RuntimeHealthCheckRunnerCompositionOperations"))
        XCTAssertTrue(bootstrapContents.contains("public enum RuntimeHealthCheckRunnerComposition"))
        XCTAssertTrue(bootstrapContents.contains("public static func make"))
        XCTAssertTrue(bootstrapContents.contains("RuntimeHealthCheckRunner("))
        XCTAssertTrue(bootstrapContents.contains("writeRuntimeStatusBestEffort"))
        XCTAssertTrue(bootstrapContents.contains("recordRuntimeObservedEventBestEffort"))
        XCTAssertTrue(bootstrapContents.contains(".healthObserved"))
        XCTAssertFalse(bootstrapContents.contains("import HostCLI"))
        XCTAssertFalse(bootstrapContents.contains("import Core"))
        XCTAssertFalse(bootstrapContents.contains("import HostInfrastructure"))
        XCTAssertTrue(hostCLIShimContents.contains(
            "typealias RuntimeHealthCheckRunnerCompositionOperations = Bootstrap.RuntimeHealthCheckRunnerCompositionOperations"
        ))
        XCTAssertTrue(hostCLIShimContents.contains(
            "typealias RuntimeHealthCheckRunnerComposition = Bootstrap.RuntimeHealthCheckRunnerComposition"
        ))
        XCTAssertFalse(hostCLIShimContents.contains("struct RuntimeHealthCheckRunnerCompositionOperations"))
        XCTAssertTrue(hostCLIWorkflowContents.contains("RuntimeHealthCheckRunnerComposition.make"))
        XCTAssertFalse(hostCLIWorkflowContents.contains("RuntimeHealthCheckRunner("))
        XCTAssertFalse(hostCLIWorkflowContents.contains("writeRuntimeStatusBestEffort"))
        XCTAssertFalse(hostCLIWorkflowContents.contains("recordRuntimeObservedEventBestEffort"))
        XCTAssertFalse(hostCLIWorkflowContents.contains(".healthObserved"))
    }

    func testRuntimeRedisBackupCompositionLivesInBootstrapWithHostCLIAliasesOnly() throws {
        let sourcesRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources")
        let bootstrapFile = sourcesRoot.appendingPathComponent("Bootstrap/Composition/RuntimeRedisBackupComposition.swift")
        let hostCLIShimFile = sourcesRoot.appendingPathComponent("HostCLI/Runtime/RuntimeRedisBackupComposition.swift")
        let hostCLIWorkflowFile = sourcesRoot.appendingPathComponent("HostCLI/Runtime/RuntimeLifecycle+Workflows.swift")

        assertFileExists(bootstrapFile, "Redis backup workflow composition must live in Bootstrap")
        assertFileExists(hostCLIShimFile, "RuntimeRedisBackupComposition HostCLI shim must remain explicit")

        let bootstrapContents = try String(contentsOf: bootstrapFile, encoding: .utf8)
        let hostCLIShimContents = try String(contentsOf: hostCLIShimFile, encoding: .utf8)
        let hostCLIWorkflowContents = try String(contentsOf: hostCLIWorkflowFile, encoding: .utf8)

        XCTAssertTrue(bootstrapContents.contains("public struct RuntimeRedisBackupCompositionContext"))
        XCTAssertTrue(bootstrapContents.contains("public struct RuntimeRedisBackupCompositionOperations"))
        XCTAssertTrue(bootstrapContents.contains("public struct RuntimeRedisBackupComposition"))
        XCTAssertTrue(bootstrapContents.contains("RuntimeRedisBackupWorkflowContext"))
        XCTAssertTrue(bootstrapContents.contains("RedisBackupResultReader.load"))
        XCTAssertTrue(bootstrapContents.contains("Constants.Runtime.redisBackupRequestFile"))
        XCTAssertTrue(bootstrapContents.contains("Constants.Runtime.redisBackupResultFile"))
        XCTAssertTrue(bootstrapContents.contains("Constants.Runtime.redisBackupWaitTimeoutSeconds"))
        XCTAssertFalse(bootstrapContents.contains("import HostCLI"))
        XCTAssertFalse(bootstrapContents.contains("import Core"))
        XCTAssertFalse(bootstrapContents.contains("import HostInfrastructure"))
        XCTAssertTrue(hostCLIShimContents.contains(
            "typealias RuntimeRedisBackupCompositionContext = Bootstrap.RuntimeRedisBackupCompositionContext"
        ))
        XCTAssertTrue(hostCLIShimContents.contains(
            "typealias RuntimeRedisBackupCompositionOperations = Bootstrap.RuntimeRedisBackupCompositionOperations"
        ))
        XCTAssertTrue(hostCLIShimContents.contains(
            "typealias RuntimeRedisBackupComposition = Bootstrap.RuntimeRedisBackupComposition"
        ))
        XCTAssertFalse(hostCLIShimContents.contains("struct RuntimeRedisBackupComposition"))
        XCTAssertTrue(hostCLIWorkflowContents.contains("RuntimeRedisBackupComposition("))
        XCTAssertFalse(hostCLIWorkflowContents.contains("RuntimeRedisBackupWorkflow("))
        XCTAssertFalse(hostCLIWorkflowContents.contains("Constants.Runtime.redisBackupRequestFile"))
        XCTAssertFalse(hostCLIWorkflowContents.contains("Constants.Runtime.redisBackupResultFile"))
        XCTAssertFalse(hostCLIWorkflowContents.contains("Constants.Runtime.redisBackupWaitTimeoutSeconds"))
        XCTAssertFalse(hostCLIWorkflowContents.contains("RedisBackupResultReader.load"))
        XCTAssertFalse(hostCLIWorkflowContents.contains("JSONEncoder()"))
    }

    func testRuntimeDatastoreRepairCompositionLivesInBootstrapWithHostCLIAliasesOnly() throws {
        let sourcesRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources")
        let bootstrapFile = sourcesRoot.appendingPathComponent("Bootstrap/Composition/RuntimeDatastoreRepairComposition.swift")
        let hostCLIShimFile = sourcesRoot.appendingPathComponent("HostCLI/Runtime/RuntimeDatastoreRepairComposition.swift")
        let hostCLIWorkflowFile = sourcesRoot.appendingPathComponent("HostCLI/Runtime/RuntimeLifecycle+Workflows.swift")

        assertFileExists(bootstrapFile, "datastore repair workflow composition must live in Bootstrap")
        assertFileExists(hostCLIShimFile, "RuntimeDatastoreRepairComposition HostCLI shim must remain explicit")

        let bootstrapContents = try String(contentsOf: bootstrapFile, encoding: .utf8)
        let hostCLIShimContents = try String(contentsOf: hostCLIShimFile, encoding: .utf8)
        let hostCLIWorkflowContents = try String(contentsOf: hostCLIWorkflowFile, encoding: .utf8)
        guard let datastoreStart = hostCLIWorkflowContents.range(of: "func runtimeDatastoreRepairWorkflow()"),
              let datastoreEnd = hostCLIWorkflowContents.range(
                  of: "func runtimeVMDiskRepairRunner()",
                  range: datastoreStart.upperBound..<hostCLIWorkflowContents.endIndex
              )
        else {
            XCTFail("HostCLI runtimeDatastoreRepairWorkflow and runtimeVMDiskRepairRunner functions must remain discoverable")
            return
        }
        let hostCLIDatastoreContents = String(hostCLIWorkflowContents[datastoreStart.lowerBound..<datastoreEnd.lowerBound])

        XCTAssertTrue(bootstrapContents.contains("public struct RuntimeDatastoreRepairCompositionContext"))
        XCTAssertTrue(bootstrapContents.contains("public struct RuntimeDatastoreRepairCompositionOperations"))
        XCTAssertTrue(bootstrapContents.contains("public struct RuntimeDatastoreRepairComposition"))
        XCTAssertTrue(bootstrapContents.contains("RuntimeDatastoreRepairWorkflow("))
        XCTAssertTrue(bootstrapContents.contains("RuntimeDatastoreRepairWorkflowContext("))
        XCTAssertTrue(bootstrapContents.contains("RuntimeDatastoreRepairWorkflowOperations("))
        XCTAssertTrue(bootstrapContents.contains("Constants.Runtime.datastoreRepairWaitTimeoutSeconds"))
        XCTAssertTrue(bootstrapContents.contains("guestGateway.removeDatastoreRepairResult()"))
        XCTAssertTrue(bootstrapContents.contains("guestGateway.writeDatastoreRepairRequest"))
        XCTAssertTrue(bootstrapContents.contains("guestGateway.loadDatastoreRepairResultDocument()"))
        XCTAssertFalse(bootstrapContents.contains("import HostCLI"))
        XCTAssertFalse(bootstrapContents.contains("import Core"))
        XCTAssertFalse(bootstrapContents.contains("import HostInfrastructure"))
        XCTAssertTrue(hostCLIShimContents.contains(
            "typealias RuntimeDatastoreRepairCompositionContext = Bootstrap.RuntimeDatastoreRepairCompositionContext"
        ))
        XCTAssertTrue(hostCLIShimContents.contains(
            "typealias RuntimeDatastoreRepairCompositionOperations = Bootstrap.RuntimeDatastoreRepairCompositionOperations"
        ))
        XCTAssertTrue(hostCLIShimContents.contains(
            "typealias RuntimeDatastoreRepairComposition = Bootstrap.RuntimeDatastoreRepairComposition"
        ))
        XCTAssertFalse(hostCLIShimContents.contains("struct RuntimeDatastoreRepairComposition"))
        XCTAssertTrue(hostCLIDatastoreContents.contains("RuntimeDatastoreRepairComposition("))
        XCTAssertFalse(hostCLIDatastoreContents.contains("RuntimeDatastoreRepairWorkflow("))
        XCTAssertFalse(hostCLIDatastoreContents.contains("RuntimeDatastoreRepairWorkflowContext("))
        XCTAssertFalse(hostCLIDatastoreContents.contains("RuntimeDatastoreRepairWorkflowOperations("))
        XCTAssertFalse(hostCLIDatastoreContents.contains("Constants.Runtime.datastoreRepairWaitTimeoutSeconds"))
        XCTAssertFalse(hostCLIDatastoreContents.contains("removeDatastoreRepairResult"))
        XCTAssertFalse(hostCLIDatastoreContents.contains("writeDatastoreRepairRequest"))
        XCTAssertFalse(hostCLIDatastoreContents.contains("loadDatastoreRepairResultDocument"))
    }

    func testRuntimeVMDiskRepairCompositionLivesInBootstrapWithHostCLIAliasesOnly() throws {
        let sourcesRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources")
        let bootstrapFile = sourcesRoot.appendingPathComponent("Bootstrap/Composition/RuntimeVMDiskRepairComposition.swift")
        let hostCLIShimFile = sourcesRoot.appendingPathComponent("HostCLI/Runtime/RuntimeVMDiskRepairComposition.swift")
        let hostCLIWorkflowFile = sourcesRoot.appendingPathComponent("HostCLI/Runtime/RuntimeLifecycle+Workflows.swift")

        assertFileExists(bootstrapFile, "VM disk repair runner composition must live in Bootstrap")
        assertFileExists(hostCLIShimFile, "RuntimeVMDiskRepairComposition HostCLI shim must remain explicit")

        let bootstrapContents = try String(contentsOf: bootstrapFile, encoding: .utf8)
        let hostCLIShimContents = try String(contentsOf: hostCLIShimFile, encoding: .utf8)
        let hostCLIWorkflowContents = try String(contentsOf: hostCLIWorkflowFile, encoding: .utf8)
        guard let repairStart = hostCLIWorkflowContents.range(of: "func runtimeVMDiskRepairRunner()"),
              let repairEnd = hostCLIWorkflowContents.range(
                  of: "func runtimeServiceControlRunner()",
                  range: repairStart.upperBound..<hostCLIWorkflowContents.endIndex
              )
        else {
            XCTFail("HostCLI runtimeVMDiskRepairRunner and runtimeServiceControlRunner functions must remain discoverable")
            return
        }
        let hostCLIRepairContents = String(hostCLIWorkflowContents[repairStart.lowerBound..<repairEnd.lowerBound])

        XCTAssertTrue(bootstrapContents.contains("public struct RuntimeVMDiskRepairCompositionContext"))
        XCTAssertTrue(bootstrapContents.contains("public struct RuntimeVMDiskRepairCompositionOperations"))
        XCTAssertTrue(bootstrapContents.contains("public enum RuntimeVMDiskRepairComposition"))
        XCTAssertTrue(bootstrapContents.contains("RuntimeVMDiskRepairRunner("))
        XCTAssertTrue(bootstrapContents.contains("RuntimeVMDiskRepairContext("))
        XCTAssertTrue(bootstrapContents.contains("RuntimeVMDiskRepairOperations("))
        XCTAssertTrue(bootstrapContents.contains("Constants.Artifacts.rootfsBase"))
        XCTAssertTrue(bootstrapContents.contains("Constants.BootAssets.disk"))
        XCTAssertTrue(bootstrapContents.contains("Constants.Defaults.defaultDiskGiB"))
        XCTAssertTrue(bootstrapContents.contains("Constants.Runtime.freeSpaceMarginBytes"))
        XCTAssertTrue(bootstrapContents.contains("Constants.Commands.gunzip"))
        XCTAssertTrue(bootstrapContents.contains("Constants.Commands.truncate"))
        XCTAssertFalse(bootstrapContents.contains("import HostCLI"))
        XCTAssertFalse(bootstrapContents.contains("import Core"))
        XCTAssertFalse(bootstrapContents.contains("import HostInfrastructure"))
        XCTAssertTrue(hostCLIShimContents.contains(
            "typealias RuntimeVMDiskRepairCompositionContext = Bootstrap.RuntimeVMDiskRepairCompositionContext"
        ))
        XCTAssertTrue(hostCLIShimContents.contains(
            "typealias RuntimeVMDiskRepairCompositionOperations = Bootstrap.RuntimeVMDiskRepairCompositionOperations"
        ))
        XCTAssertTrue(hostCLIShimContents.contains(
            "typealias RuntimeVMDiskRepairComposition = Bootstrap.RuntimeVMDiskRepairComposition"
        ))
        XCTAssertFalse(hostCLIShimContents.contains("struct RuntimeVMDiskRepairComposition"))
        XCTAssertTrue(hostCLIRepairContents.contains("RuntimeVMDiskRepairComposition.make"))
        XCTAssertFalse(hostCLIRepairContents.contains("RuntimeVMDiskRepairRunner("))
        XCTAssertFalse(hostCLIRepairContents.contains("RuntimeVMDiskRepairContext("))
        XCTAssertFalse(hostCLIRepairContents.contains("RuntimeVMDiskRepairOperations("))
        XCTAssertFalse(hostCLIRepairContents.contains("Constants.Artifacts.rootfsBase"))
        XCTAssertFalse(hostCLIRepairContents.contains("Constants.BootAssets.disk"))
        XCTAssertFalse(hostCLIRepairContents.contains("Constants.Defaults.defaultDiskGiB"))
        XCTAssertFalse(hostCLIRepairContents.contains("Constants.Runtime.freeSpaceMarginBytes"))
        XCTAssertFalse(hostCLIRepairContents.contains("Constants.Commands.gunzip"))
        XCTAssertFalse(hostCLIRepairContents.contains("Constants.Commands.truncate"))
    }

    func testRuntimeRollbackCompositionLivesInBootstrapWithHostCLIAliasesOnly() throws {
        let sourcesRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources")
        let bootstrapFile = sourcesRoot.appendingPathComponent("Bootstrap/Composition/RuntimeRollbackComposition.swift")
        let hostCLIShimFile = sourcesRoot.appendingPathComponent("HostCLI/Runtime/RuntimeRollbackComposition.swift")
        let hostCLIWorkflowFile = sourcesRoot.appendingPathComponent("HostCLI/Runtime/RuntimeLifecycle+Workflows.swift")

        assertFileExists(bootstrapFile, "rollback workflow composition must live in Bootstrap")
        assertFileExists(hostCLIShimFile, "RuntimeRollbackComposition HostCLI shim must remain explicit")

        let bootstrapContents = try String(contentsOf: bootstrapFile, encoding: .utf8)
        let hostCLIShimContents = try String(contentsOf: hostCLIShimFile, encoding: .utf8)
        let hostCLIWorkflowContents = try String(contentsOf: hostCLIWorkflowFile, encoding: .utf8)
        guard let rollbackStart = hostCLIWorkflowContents.range(of: "func runtimeRollbackWorkflow()"),
              let rollbackEnd = hostCLIWorkflowContents.range(
                  of: "func runtimeGuestActivationWorkflow()",
                  range: rollbackStart.upperBound..<hostCLIWorkflowContents.endIndex
              )
        else {
            XCTFail("HostCLI rollback and guest activation factories must remain discoverable")
            return
        }
        let hostCLIRollbackContents = String(hostCLIWorkflowContents[rollbackStart.lowerBound..<rollbackEnd.lowerBound])

        XCTAssertTrue(bootstrapContents.contains("public struct RuntimeRollbackCompositionContext"))
        XCTAssertTrue(bootstrapContents.contains("public struct RuntimeRollbackCompositionOperations"))
        XCTAssertTrue(bootstrapContents.contains("public enum RuntimeRollbackComposition"))
        XCTAssertTrue(bootstrapContents.contains("RuntimeRollbackWorkflow("))
        XCTAssertTrue(bootstrapContents.contains("RuntimeRollbackWorkflowContext("))
        XCTAssertTrue(bootstrapContents.contains("RuntimeRollbackWorkflowOperations("))
        XCTAssertTrue(bootstrapContents.contains("Constants.Artifacts.rootfsBase"))
        XCTAssertTrue(bootstrapContents.contains("Constants.Artifacts.runtimeVersion"))
        XCTAssertTrue(bootstrapContents.contains("Constants.BootAssets.disk"))
        XCTAssertTrue(bootstrapContents.contains("Constants.Product.managerAppPath"))
        XCTAssertFalse(bootstrapContents.contains("import HostCLI"))
        XCTAssertFalse(bootstrapContents.contains("import Core"))
        XCTAssertFalse(bootstrapContents.contains("import HostInfrastructure"))
        XCTAssertTrue(hostCLIShimContents.contains(
            "typealias RuntimeRollbackCompositionContext = Bootstrap.RuntimeRollbackCompositionContext"
        ))
        XCTAssertTrue(hostCLIShimContents.contains(
            "typealias RuntimeRollbackCompositionOperations = Bootstrap.RuntimeRollbackCompositionOperations"
        ))
        XCTAssertTrue(hostCLIShimContents.contains(
            "typealias RuntimeRollbackComposition = Bootstrap.RuntimeRollbackComposition"
        ))
        XCTAssertFalse(hostCLIShimContents.contains("struct RuntimeRollbackCompositionContext"))
        XCTAssertTrue(hostCLIRollbackContents.contains("RuntimeRollbackComposition.make"))
        XCTAssertFalse(hostCLIRollbackContents.contains("RuntimeRollbackWorkflow("))
        XCTAssertFalse(hostCLIRollbackContents.contains("RuntimeRollbackWorkflowContext("))
        XCTAssertFalse(hostCLIRollbackContents.contains("RuntimeRollbackWorkflowOperations("))
        XCTAssertFalse(hostCLIRollbackContents.contains("Constants.Artifacts.rootfsBase"))
        XCTAssertFalse(hostCLIRollbackContents.contains("Constants.Artifacts.runtimeVersion"))
        XCTAssertFalse(hostCLIRollbackContents.contains("Constants.BootAssets.disk"))
        XCTAssertFalse(hostCLIRollbackContents.contains("Constants.Product.managerAppPath"))
    }

    func testRuntimeHealthCheckerCompositionLivesInBootstrapWithHostCLIShimOnly() throws {
        let sourcesRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources")
        let bootstrapFile = sourcesRoot.appendingPathComponent("Bootstrap/Composition/RuntimeHealthCheckerComposition.swift")
        let hostCLIFile = sourcesRoot.appendingPathComponent("HostCLI/Runtime/RuntimeHealthChecker.swift")
        let lifecycleCompositionFile = sourcesRoot.appendingPathComponent("Bootstrap/Composition/RuntimeLifecycleComposition.swift")

        assertFileExists(bootstrapFile, "health checker product context composition must live in Bootstrap")
        assertFileExists(hostCLIFile, "RuntimeHealthChecker HostCLI shim must remain explicit")

        let bootstrapContents = try String(contentsOf: bootstrapFile, encoding: .utf8)
        let hostCLIContents = try String(contentsOf: hostCLIFile, encoding: .utf8)
        let lifecycleCompositionContents = try String(contentsOf: lifecycleCompositionFile, encoding: .utf8)

        XCTAssertTrue(bootstrapContents.contains("public enum RuntimeHealthCheckerComposition"))
        XCTAssertTrue(bootstrapContents.contains("public static func make"))
        XCTAssertTrue(bootstrapContents.contains("public static func context"))
        XCTAssertTrue(bootstrapContents.contains("RuntimeManagedServicePaths.launchDaemonPlist(.proxy)"))
        XCTAssertFalse(bootstrapContents.contains("import HostCLI"))
        XCTAssertFalse(bootstrapContents.contains("import Core"))
        XCTAssertFalse(bootstrapContents.contains("import HostInfrastructure"))
        XCTAssertTrue(hostCLIContents.contains("typealias RuntimeHealthCheckerContext = Infrastructure.RuntimeHealthCheckerContext"))
        XCTAssertTrue(hostCLIContents.contains("typealias RuntimeHealthChecker = Infrastructure.RuntimeHealthChecker"))
        XCTAssertTrue(hostCLIContents.contains("RuntimeHealthCheckerComposition.make"))
        XCTAssertFalse(hostCLIContents.contains("Constants."))
        XCTAssertFalse(hostCLIContents.contains("InstallSettings.defaultProxyPort"))
        XCTAssertFalse(hostCLIContents.contains(".hostCLI"))
        XCTAssertFalse(hostCLIContents.contains("extension RuntimeHealthCheckerContext"))
        XCTAssertTrue(lifecycleCompositionContents.contains("RuntimeHealthCheckerComposition.context"))
    }

    func testVMRuntimeConfigCompositionLivesInBootstrapWithHostCLIShimOnly() throws {
        let sourcesRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources")
        let bootstrapFile = sourcesRoot.appendingPathComponent("Bootstrap/Composition/VMRuntimeConfigComposition.swift")
        let hostCLIFile = sourcesRoot.appendingPathComponent("HostCLI/VirtualMachine/VMRuntimeConfig.swift")
        let configureCompositionFile = sourcesRoot.appendingPathComponent("Bootstrap/Composition/RuntimeConfigureRunner.swift")
        let installCompositionFile = sourcesRoot.appendingPathComponent("Bootstrap/Composition/RuntimeInstallComposition.swift")

        assertFileExists(bootstrapFile, "VM runtime config product defaults must live in Bootstrap")
        assertFileExists(hostCLIFile, "VMRuntimeConfig HostCLI shim must remain explicit")

        let bootstrapContents = try String(contentsOf: bootstrapFile, encoding: .utf8)
        let hostCLIContents = try String(contentsOf: hostCLIFile, encoding: .utf8)
        let configureCompositionContents = try String(contentsOf: configureCompositionFile, encoding: .utf8)
        let installCompositionContents = try String(contentsOf: installCompositionFile, encoding: .utf8)

        XCTAssertTrue(bootstrapContents.contains("public enum VMRuntimeConfigComposition"))
        XCTAssertTrue(bootstrapContents.contains("public static func defaultConfig"))
        XCTAssertTrue(bootstrapContents.contains("public static func load"))
        XCTAssertTrue(bootstrapContents.contains("public static func validateBootFiles"))
        XCTAssertTrue(bootstrapContents.contains("public static func ensureRuntimeDefaults"))
        XCTAssertFalse(bootstrapContents.contains("import HostCLI"))
        XCTAssertFalse(bootstrapContents.contains("import Core"))
        XCTAssertFalse(bootstrapContents.contains("import HostInfrastructure"))
        XCTAssertTrue(hostCLIContents.contains("typealias VMRuntimeConfig = HostAdapters.VMRuntimeConfig"))
        XCTAssertTrue(hostCLIContents.contains("VMRuntimeConfigComposition.defaultConfig"))
        XCTAssertTrue(hostCLIContents.contains("VMRuntimeConfigComposition.load"))
        XCTAssertTrue(hostCLIContents.contains("VMRuntimeConfigComposition.validateBootFiles"))
        XCTAssertTrue(hostCLIContents.contains("VMRuntimeConfigComposition.ensureRuntimeDefaults"))
        XCTAssertFalse(hostCLIContents.contains("Constants."))
        XCTAssertFalse(hostCLIContents.contains("LauncherError"))
        XCTAssertFalse(hostCLIContents.contains("import Core"))
        XCTAssertFalse(hostCLIContents.contains("import HostInfrastructure"))
        XCTAssertTrue(configureCompositionContents.contains("VMRuntimeConfigComposition.load"))
        XCTAssertTrue(configureCompositionContents.contains("VMRuntimeConfigComposition.ensureRuntimeDefaults"))
        XCTAssertTrue(installCompositionContents.contains("VMRuntimeConfigComposition.defaultConfig"))
        XCTAssertTrue(installCompositionContents.contains("VMRuntimeConfigComposition.ensureRuntimeDefaults"))
        XCTAssertFalse(configureCompositionContents.contains("private func ensureNetworkIdentity"))
        XCTAssertFalse(installCompositionContents.contains("private func defaultVMRuntimeConfig"))
    }

    func testRuntimeConfigureRunnerLivesInBootstrapWithHostCLIAliasesOnly() throws {
        let sourcesRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources")
        let bootstrapFile = sourcesRoot.appendingPathComponent("Bootstrap/Composition/RuntimeConfigureRunner.swift")
        let hostCLIFile = sourcesRoot.appendingPathComponent("HostCLI/Runtime/RuntimeConfigureRunner.swift")
        let lifecycleWorkflowsFile = sourcesRoot.appendingPathComponent("HostCLI/Runtime/RuntimeLifecycle+Workflows.swift")

        assertFileExists(bootstrapFile, "configure usecase and workflow wiring must live in Bootstrap")
        assertFileExists(hostCLIFile, "RuntimeConfigureRunner HostCLI shim must remain explicit")
        assertFileExists(lifecycleWorkflowsFile, "RuntimeLifecycle workflow factory must remain explicit")

        let bootstrapContents = try String(contentsOf: bootstrapFile, encoding: .utf8)
        let hostCLIContents = try String(contentsOf: hostCLIFile, encoding: .utf8)
        let lifecycleWorkflowsContents = try String(contentsOf: lifecycleWorkflowsFile, encoding: .utf8)

        XCTAssertTrue(bootstrapContents.contains("public struct RuntimeConfigureCompositionContext"))
        XCTAssertTrue(bootstrapContents.contains("public struct RuntimeConfigureCompositionOperations"))
        XCTAssertTrue(bootstrapContents.contains("public enum RuntimeConfigureComposition"))
        XCTAssertTrue(bootstrapContents.contains("public static func make"))
        XCTAssertTrue(bootstrapContents.contains("public struct RuntimeConfigureActions"))
        XCTAssertTrue(bootstrapContents.contains("public struct RuntimeConfigureResult"))
        XCTAssertTrue(bootstrapContents.contains("public struct RuntimeConfigureRunner"))
        XCTAssertTrue(bootstrapContents.contains("RuntimeConfigureActions("))
        XCTAssertTrue(bootstrapContents.contains("RuntimeConfigureRunner("))
        XCTAssertFalse(bootstrapContents.contains("import HostCLI"))
        XCTAssertFalse(bootstrapContents.contains("import Core"))
        XCTAssertFalse(bootstrapContents.contains("import HostInfrastructure"))
        XCTAssertFalse(bootstrapContents.contains("ConfigureRuntimeUseCase<NetworkMode>"))
        XCTAssertTrue(bootstrapContents.contains("ConfigureRuntimeUseCase<RuntimeNetworkMode>"))
        XCTAssertTrue(hostCLIContents.contains("typealias RuntimeConfigureCompositionContext = Bootstrap.RuntimeConfigureCompositionContext"))
        XCTAssertTrue(hostCLIContents.contains("typealias RuntimeConfigureCompositionOperations = Bootstrap.RuntimeConfigureCompositionOperations"))
        XCTAssertTrue(hostCLIContents.contains("typealias RuntimeConfigureComposition = Bootstrap.RuntimeConfigureComposition"))
        XCTAssertTrue(hostCLIContents.contains("typealias RuntimeConfigureActions = Bootstrap.RuntimeConfigureActions"))
        XCTAssertTrue(hostCLIContents.contains("typealias RuntimeConfigureResult = Bootstrap.RuntimeConfigureResult"))
        XCTAssertTrue(hostCLIContents.contains("typealias RuntimeConfigureRunner = Bootstrap.RuntimeConfigureRunner"))
        XCTAssertFalse(hostCLIContents.contains("struct RuntimeConfigureRunner"))
        XCTAssertFalse(hostCLIContents.contains("ConfigureRuntimeUseCase"))
        XCTAssertTrue(lifecycleWorkflowsContents.contains("RuntimeConfigureComposition.make"))
        XCTAssertTrue(lifecycleWorkflowsContents.contains("RuntimeConfigureCompositionContext("))
        XCTAssertTrue(lifecycleWorkflowsContents.contains("RuntimeConfigureCompositionOperations("))
        XCTAssertFalse(lifecycleWorkflowsContents.contains("RuntimeConfigureRunner(\n"))
        XCTAssertFalse(lifecycleWorkflowsContents.contains("RuntimeConfigureActions("))
    }

    func testCoreUsesExplicitResponsibilityFoldersInsteadOfApplicationFolder() {
        let coreRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/Core")
        let ambiguousApplicationFolder = coreRoot.appendingPathComponent("Application")

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: ambiguousApplicationFolder.path),
            "Core must not use an ambiguous Application folder; workflow orchestration belongs to Workflow"
        )

        for folder in ["Plan", "Preflight", "Policy", "StateMachine", "Verification", "Document"] {
            var isDirectory: ObjCBool = false
            let path = coreRoot.appendingPathComponent(folder).path
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
                "Core responsibility folder is missing: \(folder)"
            )
            XCTAssertTrue(isDirectory.boolValue, "Core responsibility path must be a directory: \(folder)")
        }
    }

    func testTransitionalRuntimeWorkflowContainsNoSwiftImplementationFiles() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/RuntimeWorkflow")

        let swiftFiles = try swiftFiles(in: root)

        XCTAssertTrue(
            swiftFiles.isEmpty,
            "transitional RuntimeWorkflow target must not retain Swift implementation files"
        )
    }

    func testPackageManifestDoesNotDeclareTransitionalRuntimeWorkflowTarget() throws {
        let packageManifest = try String(
            contentsOf: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Package.swift"),
            encoding: .utf8
        )

        XCTAssertNil(
            targetDeclaration("RuntimeWorkflow", in: packageManifest),
            "Package.swift must not retain the transitional RuntimeWorkflow target"
        )
    }

    func testInstallTransitionPolicyAndOperationPlanLiveInDomainWithCoreAliasesOnly() throws {
        let sourcesRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources")
        let domainPlan = sourcesRoot.appendingPathComponent("Domain/Models/RuntimeOperationPlan.swift")
        let domainTransition = sourcesRoot.appendingPathComponent("Domain/StateMachines/RuntimeInstallTransitionPolicy.swift")
        let corePlan = sourcesRoot.appendingPathComponent("Core/Plan/RuntimeOperationPlan.swift")
        let coreTransition = sourcesRoot.appendingPathComponent("Core/StateMachine/RuntimeInstallTransitionPolicy.swift")

        assertFileExists(domainPlan, "RuntimeOperationPlan implementation must live in Domain")
        assertFileExists(domainTransition, "RuntimeInstallTransitionPolicy implementation must live in Domain")

        let domainPlanContents = try String(contentsOf: domainPlan, encoding: .utf8)
        let domainTransitionContents = try String(contentsOf: domainTransition, encoding: .utf8)
        XCTAssertTrue(domainPlanContents.contains("public struct RuntimeOperationPlan"))
        XCTAssertTrue(domainTransitionContents.contains("public enum RuntimeInstallTransitionPolicy"))
        XCTAssertFalse(domainPlanContents.contains("import Core"))
        XCTAssertFalse(domainTransitionContents.contains("import Core"))

        let corePlanContents = try String(contentsOf: corePlan, encoding: .utf8)
        let coreTransitionContents = try String(contentsOf: coreTransition, encoding: .utf8)
        XCTAssertTrue(corePlanContents.contains("public typealias RuntimeOperationPlan = Domain.RuntimeOperationPlan"))
        XCTAssertTrue(coreTransitionContents.contains("public typealias RuntimeInstallTransitionPolicy = Domain.RuntimeInstallTransitionPolicy"))
        XCTAssertFalse(corePlanContents.contains("public struct RuntimeOperationPlan"))
        XCTAssertFalse(coreTransitionContents.contains("public enum RuntimeInstallTransitionPolicy"))
    }

    func testInstallWorkflowOrchestrationLivesInFinalWorkflowLayer() throws {
        let sourcesRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources")
        let workflowInstall = sourcesRoot
            .appendingPathComponent("Workflow/RuntimeInstallLifecycle/RuntimeInstallWorkflow.swift")
        let workflowPreflight = sourcesRoot
            .appendingPathComponent("Workflow/RuntimeInstallLifecycle/RuntimeFreshInstallPreflightRunner.swift")
        let legacyInstall = sourcesRoot
            .appendingPathComponent("RuntimeWorkflow/Install/RuntimeInstallWorkflow.swift")
        let legacyPreflight = sourcesRoot
            .appendingPathComponent("RuntimeWorkflow/Install/RuntimeFreshInstallPreflightRunner.swift")

        assertFileExists(workflowInstall, "RuntimeInstallWorkflow orchestration must live in final Workflow")
        assertFileExists(workflowPreflight, "RuntimeFreshInstallPreflightRunner orchestration must live in final Workflow")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: legacyInstall.path),
            "RuntimeInstallWorkflow must not remain in transitional RuntimeWorkflow"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: legacyPreflight.path),
            "RuntimeFreshInstallPreflightRunner must not remain in transitional RuntimeWorkflow"
        )

        let installContents = try String(contentsOf: workflowInstall, encoding: .utf8)
        let preflightContents = try String(contentsOf: workflowPreflight, encoding: .utf8)
        XCTAssertFalse(installContents.contains("import Core"))
        XCTAssertFalse(installContents.contains("import RuntimeWorkflow"))
        XCTAssertFalse(preflightContents.contains("import Core"))
        XCTAssertFalse(preflightContents.contains("import RuntimeWorkflow"))
        XCTAssertTrue(installContents.contains("RuntimeInstallTransitionPolicy.transition"))
        XCTAssertTrue(preflightContents.contains("RuntimeFreshInstallPreflightPolicy.document"))
    }

    func testRuntimeFreshInstallPreflightCompositionLivesInBootstrapWithHostCLIAliasesOnly() throws {
        let sourcesRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources")
        let bootstrapFile = sourcesRoot
            .appendingPathComponent("Bootstrap/Composition/RuntimeFreshInstallPreflightComposition.swift")
        let hostCLIShimFile = sourcesRoot
            .appendingPathComponent("HostCLI/Runtime/RuntimeFreshInstallPreflightComposition.swift")
        let hostCLISupportFile = sourcesRoot
            .appendingPathComponent("HostCLI/Runtime/RuntimeLifecycle+Support.swift")

        assertFileExists(bootstrapFile, "RuntimeFreshInstallPreflightComposition must live in Bootstrap")
        assertFileExists(hostCLIShimFile, "RuntimeFreshInstallPreflightComposition HostCLI shim must remain explicit")

        let bootstrapContents = try String(contentsOf: bootstrapFile, encoding: .utf8)
        let hostCLIShimContents = try String(contentsOf: hostCLIShimFile, encoding: .utf8)
        let hostCLISupportContents = try String(contentsOf: hostCLISupportFile, encoding: .utf8)
        guard let preflightStart = hostCLISupportContents.range(of: "func runtimeFreshInstallPreflightRunner"),
              let preflightEnd = hostCLISupportContents.range(
                  of: "func freshInstallArtifactPaths",
                  range: preflightStart.upperBound..<hostCLISupportContents.endIndex
              ),
              let artifactPathsEnd = hostCLISupportContents.range(
                  of: "func installProvisionPayloadPaths",
                  range: preflightEnd.upperBound..<hostCLISupportContents.endIndex
              )
        else {
            XCTFail("HostCLI fresh-install preflight helpers must remain discoverable")
            return
        }
        let hostCLIPreflightContents = String(
            hostCLISupportContents[preflightStart.lowerBound..<preflightEnd.lowerBound]
        )
        let hostCLIArtifactPathsContents = String(
            hostCLISupportContents[preflightEnd.lowerBound..<artifactPathsEnd.lowerBound]
        )

        XCTAssertTrue(bootstrapContents.contains("public struct RuntimeFreshInstallPreflightCompositionContext"))
        XCTAssertTrue(bootstrapContents.contains("public struct RuntimeFreshInstallPreflightCompositionOperations"))
        XCTAssertTrue(bootstrapContents.contains("public enum RuntimeFreshInstallPreflightComposition"))
        XCTAssertTrue(bootstrapContents.contains("RuntimeFreshInstallPreflightRunner("))
        XCTAssertTrue(bootstrapContents.contains("RuntimeInstallSettingsStateReader.state"))
        XCTAssertTrue(bootstrapContents.contains("RuntimeInstallArtifactStateReader.states"))
        XCTAssertTrue(bootstrapContents.contains("RuntimePackageReceiptStateReader.states"))
        XCTAssertTrue(bootstrapContents.contains("RuntimeHostProxyPortStateReader.state"))
        XCTAssertFalse(bootstrapContents.contains("import HostCLI"))
        XCTAssertFalse(bootstrapContents.contains("import Core"))
        XCTAssertFalse(bootstrapContents.contains("import HostInfrastructure"))
        XCTAssertTrue(
            hostCLIShimContents.contains(
                "typealias RuntimeFreshInstallPreflightCompositionContext = Bootstrap.RuntimeFreshInstallPreflightCompositionContext"
            )
        )
        XCTAssertTrue(
            hostCLIShimContents.contains(
                "typealias RuntimeFreshInstallPreflightCompositionOperations = Bootstrap.RuntimeFreshInstallPreflightCompositionOperations"
            )
        )
        XCTAssertTrue(
            hostCLIShimContents.contains(
                "typealias RuntimeFreshInstallPreflightComposition = Bootstrap.RuntimeFreshInstallPreflightComposition"
            )
        )
        XCTAssertFalse(hostCLIShimContents.contains("struct RuntimeFreshInstallPreflightComposition"))
        XCTAssertTrue(hostCLIPreflightContents.contains("RuntimeFreshInstallPreflightComposition.make"))
        XCTAssertFalse(hostCLIPreflightContents.contains("RuntimeFreshInstallPreflightRunner("))
        XCTAssertFalse(hostCLIPreflightContents.contains("RuntimeInstallSettingsStateReader"))
        XCTAssertFalse(hostCLIPreflightContents.contains("RuntimePackageReceiptStateReader"))
        XCTAssertFalse(hostCLIPreflightContents.contains("RuntimeHostProxyPortStateReader"))
        XCTAssertTrue(hostCLIArtifactPathsContents.contains("RuntimeFreshInstallPreflightComposition.freshInstallArtifactPaths"))
        XCTAssertFalse(hostCLIArtifactPathsContents.contains("installedPaths.managerApp"))
    }

    func testInstallPreflightPoliciesLiveInDomainWithCoreAliasesOnly() throws {
        let sourcesRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources")
        let domainPreflight = sourcesRoot.appendingPathComponent("Domain/Policies/RuntimeFreshInstallPreflightPolicy.swift")
        let domainUninstallReadiness = sourcesRoot.appendingPathComponent("Domain/Policies/RuntimeUninstallReadinessPolicy.swift")
        let corePreflight = sourcesRoot.appendingPathComponent("Core/Policy/RuntimeFreshInstallPreflightPolicy.swift")
        let coreUninstallReadiness = sourcesRoot.appendingPathComponent("Core/Policy/RuntimeUninstallReadinessPolicy.swift")

        assertFileExists(domainPreflight, "RuntimeFreshInstallPreflightPolicy implementation must live in Domain")
        assertFileExists(domainUninstallReadiness, "RuntimeUninstallReadinessPolicy implementation must live in Domain")

        let domainPreflightContents = try String(contentsOf: domainPreflight, encoding: .utf8)
        let domainReadinessContents = try String(contentsOf: domainUninstallReadiness, encoding: .utf8)
        XCTAssertTrue(domainPreflightContents.contains("public enum RuntimeFreshInstallPreflightPolicy"))
        XCTAssertTrue(domainReadinessContents.contains("public enum RuntimeUninstallReadinessPolicy"))
        XCTAssertFalse(domainPreflightContents.contains("import Core"))
        XCTAssertFalse(domainReadinessContents.contains("import Core"))

        let corePreflightContents = try String(contentsOf: corePreflight, encoding: .utf8)
        let coreReadinessContents = try String(contentsOf: coreUninstallReadiness, encoding: .utf8)
        XCTAssertTrue(corePreflightContents.contains("public typealias RuntimeFreshInstallPreflightPolicy = Domain.RuntimeFreshInstallPreflightPolicy"))
        XCTAssertTrue(coreReadinessContents.contains("public typealias RuntimeUninstallReadinessPolicy = Domain.RuntimeUninstallReadinessPolicy"))
        XCTAssertFalse(corePreflightContents.contains("public enum RuntimeFreshInstallPreflightPolicy"))
        XCTAssertFalse(coreReadinessContents.contains("public enum RuntimeUninstallReadinessPolicy"))
    }

    func testUninstallTransitionPolicyLivesInDomainWithCoreAliasesOnly() throws {
        let sourcesRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources")
        let domainTransition = sourcesRoot.appendingPathComponent("Domain/StateMachines/RuntimeUninstallTransitionPolicy.swift")
        let coreTransition = sourcesRoot.appendingPathComponent("Core/StateMachine/RuntimeUninstallTransitionPolicy.swift")

        assertFileExists(domainTransition, "RuntimeUninstallTransitionPolicy implementation must live in Domain")

        let domainTransitionContents = try String(contentsOf: domainTransition, encoding: .utf8)
        XCTAssertTrue(domainTransitionContents.contains("public enum RuntimeUninstallTransitionPolicy"))
        XCTAssertFalse(domainTransitionContents.contains("import Core"))

        let coreTransitionContents = try String(contentsOf: coreTransition, encoding: .utf8)
        XCTAssertTrue(coreTransitionContents.contains("public typealias RuntimeUninstallTransitionPolicy = Domain.RuntimeUninstallTransitionPolicy"))
        XCTAssertFalse(coreTransitionContents.contains("public enum RuntimeUninstallTransitionPolicy"))
    }

    func testUninstallWorkflowOrchestrationLivesInFinalWorkflowLayer() throws {
        let sourcesRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources")
        let workflowUninstall = sourcesRoot
            .appendingPathComponent("Workflow/RuntimeUninstallLifecycle/RuntimeUninstallWorkflow.swift")
        let legacyUninstall = sourcesRoot
            .appendingPathComponent("RuntimeWorkflow/Uninstall/RuntimeUninstallWorkflow.swift")

        assertFileExists(workflowUninstall, "RuntimeUninstallWorkflow orchestration must live in final Workflow")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: legacyUninstall.path),
            "RuntimeUninstallWorkflow must not remain in transitional RuntimeWorkflow"
        )

        let contents = try String(contentsOf: workflowUninstall, encoding: .utf8)
        XCTAssertFalse(contents.contains("import Core"))
        XCTAssertFalse(contents.contains("import RuntimeWorkflow"))
        XCTAssertTrue(contents.contains("RuntimeUninstallTransitionPolicy.transition"))
    }

    func testRuntimeUninstallCompositionLivesInBootstrapWithHostCLIAliasesOnly() throws {
        let sourcesRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources")
        let bootstrapFile = sourcesRoot.appendingPathComponent("Bootstrap/Composition/RuntimeUninstallComposition.swift")
        let hostCLIShimFile = sourcesRoot.appendingPathComponent("HostCLI/Runtime/RuntimeUninstallComposition.swift")
        let hostCLISupportFile = sourcesRoot.appendingPathComponent("HostCLI/Runtime/RuntimeLifecycle+Support.swift")

        assertFileExists(bootstrapFile, "uninstall workflow composition must live in Bootstrap")
        assertFileExists(hostCLIShimFile, "RuntimeUninstallComposition HostCLI shim must remain explicit")

        let bootstrapContents = try String(contentsOf: bootstrapFile, encoding: .utf8)
        let hostCLIShimContents = try String(contentsOf: hostCLIShimFile, encoding: .utf8)
        let hostCLISupportContents = try String(contentsOf: hostCLISupportFile, encoding: .utf8)
        guard let uninstallStart = hostCLISupportContents.range(of: "func runtimeUninstallRunner()"),
              let uninstallEnd = hostCLISupportContents.range(
                  of: "func runtimeFreshInstallPreflightRunner()",
                  range: uninstallStart.upperBound..<hostCLISupportContents.endIndex
              )
        else {
            XCTFail("HostCLI runtimeUninstallRunner and runtimeFreshInstallPreflightRunner functions must remain discoverable")
            return
        }
        let hostCLIUninstallContents = String(hostCLISupportContents[uninstallStart.lowerBound..<uninstallEnd.lowerBound])

        XCTAssertTrue(bootstrapContents.contains("public struct RuntimeUninstallCompositionContext"))
        XCTAssertTrue(bootstrapContents.contains("public struct RuntimeUninstallCompositionOperations"))
        XCTAssertTrue(bootstrapContents.contains("public enum RuntimeUninstallComposition"))
        XCTAssertTrue(bootstrapContents.contains("RuntimeUninstallWorkflow("))
        XCTAssertTrue(bootstrapContents.contains("RuntimeUninstallPaths("))
        XCTAssertTrue(bootstrapContents.contains("RuntimeUninstallStateReaders("))
        XCTAssertTrue(bootstrapContents.contains("RuntimeUninstallEffects("))
        XCTAssertTrue(bootstrapContents.contains("RuntimeUninstallStateStore("))
        XCTAssertTrue(bootstrapContents.contains("RuntimePackageReceiptStateReader.states"))
        XCTAssertTrue(bootstrapContents.contains("RuntimeInstallArtifactStateReader.states"))
        XCTAssertTrue(bootstrapContents.contains("ProcessState.inspect"))
        XCTAssertTrue(bootstrapContents.contains("Constants.Commands.pkgutil"))
        XCTAssertFalse(bootstrapContents.contains("import HostCLI"))
        XCTAssertFalse(bootstrapContents.contains("import Core"))
        XCTAssertFalse(bootstrapContents.contains("import HostInfrastructure"))
        XCTAssertTrue(hostCLIShimContents.contains(
            "typealias RuntimeUninstallCompositionContext = Bootstrap.RuntimeUninstallCompositionContext"
        ))
        XCTAssertTrue(hostCLIShimContents.contains(
            "typealias RuntimeUninstallCompositionOperations = Bootstrap.RuntimeUninstallCompositionOperations"
        ))
        XCTAssertTrue(hostCLIShimContents.contains(
            "typealias RuntimeUninstallComposition = Bootstrap.RuntimeUninstallComposition"
        ))
        XCTAssertFalse(hostCLIShimContents.contains("struct RuntimeUninstallComposition"))
        XCTAssertTrue(hostCLIUninstallContents.contains("RuntimeUninstallComposition.make"))
        XCTAssertFalse(hostCLIUninstallContents.contains("RuntimeUninstallWorkflow("))
        XCTAssertFalse(hostCLIUninstallContents.contains("RuntimeUninstallPaths("))
        XCTAssertFalse(hostCLIUninstallContents.contains("RuntimeUninstallStateReaders("))
        XCTAssertFalse(hostCLIUninstallContents.contains("RuntimeUninstallEffects("))
        XCTAssertFalse(hostCLIUninstallContents.contains("RuntimeUninstallStateStore("))
        XCTAssertFalse(hostCLIUninstallContents.contains("RuntimePackageReceiptStateReader.states"))
        XCTAssertFalse(hostCLIUninstallContents.contains("RuntimeInstallArtifactStateReader.states"))
        XCTAssertFalse(hostCLIUninstallContents.contains("ProcessState.inspect"))
        XCTAssertFalse(hostCLIUninstallContents.contains("/usr/sbin/pkgutil"))
    }

    func testRollbackPreflightContextLivesInDomainWithCoreAliasOnly() throws {
        let sourcesRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources")
        let domainPreflight = sourcesRoot.appendingPathComponent("Domain/Models/RollbackPreflight.swift")
        let corePreflight = sourcesRoot.appendingPathComponent("Core/Preflight/RollbackPreflight.swift")

        assertFileExists(domainPreflight, "RollbackPreflightContext implementation must live in Domain")

        let domainContents = try String(contentsOf: domainPreflight, encoding: .utf8)
        XCTAssertTrue(domainContents.contains("public struct RollbackPreflightContext"))
        XCTAssertFalse(domainContents.contains("import Core"))

        let coreContents = try String(contentsOf: corePreflight, encoding: .utf8)
        XCTAssertTrue(coreContents.contains("public typealias RollbackPreflightContext = Domain.RollbackPreflightContext"))
        XCTAssertFalse(coreContents.contains("public struct RollbackPreflightContext"))
    }

    func testRollbackWorkflowLivesInFinalWorkflowLayer() throws {
        let sourcesRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources")
        let movedFiles = [
            "RuntimeRollbackPreflightRunner.swift",
            "RuntimeRollbackRunner.swift",
            "RuntimeRollbackStepExecutor.swift",
            "RuntimeRollbackWorkflow.swift",
        ]

        for fileName in movedFiles {
            let workflowFile = sourcesRoot.appendingPathComponent("Workflow/RuntimeUpdateLifecycle/\(fileName)")
            let legacyFile = sourcesRoot.appendingPathComponent("RuntimeWorkflow/Rollback/\(fileName)")
            assertFileExists(workflowFile, "\(fileName) must live in final Workflow")
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: legacyFile.path),
                "\(fileName) must not remain in transitional RuntimeWorkflow"
            )

            let contents = try String(contentsOf: workflowFile, encoding: .utf8)
            XCTAssertFalse(contents.contains("import Core"), "\(fileName) must not import Core")
            XCTAssertFalse(contents.contains("import RuntimeWorkflow"), "\(fileName) must not import RuntimeWorkflow")
        }
    }

    func testRedisBackupWorkflowLivesInFinalWorkflowLayer() throws {
        let sourcesRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources")
        let workflowRedisBackup = sourcesRoot
            .appendingPathComponent("Workflow/RuntimeRepairLifecycle/RuntimeRedisBackupWorkflow.swift")
        let legacyRedisBackup = sourcesRoot
            .appendingPathComponent("RuntimeWorkflow/RedisBackup/RuntimeRedisBackupWorkflow.swift")

        assertFileExists(workflowRedisBackup, "RuntimeRedisBackupWorkflow must live in final Workflow")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: legacyRedisBackup.path),
            "RuntimeRedisBackupWorkflow must not remain in transitional RuntimeWorkflow"
        )

        let contents = try String(contentsOf: workflowRedisBackup, encoding: .utf8)
        XCTAssertFalse(contents.contains("import Core"))
        XCTAssertFalse(contents.contains("import RuntimeWorkflow"))
        XCTAssertTrue(contents.contains("public enum RuntimeRedisBackupWorkflowError"))
    }

    func testDatastoreRepairWorkflowLivesInFinalWorkflowLayer() throws {
        let sourcesRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources")
        let movedFiles = [
            "RuntimeDatastoreRepairResultWaiter.swift",
            "RuntimeDatastoreRepairRunner.swift",
            "RuntimeDatastoreRepairWorkflow.swift",
        ]

        for fileName in movedFiles {
            let workflowFile = sourcesRoot.appendingPathComponent("Workflow/RuntimeRepairLifecycle/\(fileName)")
            let legacyFile = sourcesRoot.appendingPathComponent("RuntimeWorkflow/DatastoreRepair/\(fileName)")
            assertFileExists(workflowFile, "\(fileName) must live in final Workflow")
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: legacyFile.path),
                "\(fileName) must not remain in transitional RuntimeWorkflow"
            )

            let contents = try String(contentsOf: workflowFile, encoding: .utf8)
            XCTAssertFalse(contents.contains("import Core"), "\(fileName) must not import Core")
            XCTAssertFalse(contents.contains("import RuntimeWorkflow"), "\(fileName) must not import RuntimeWorkflow")
        }
    }

    func testVMDiskRepairWorkflowLivesInFinalWorkflowLayer() throws {
        let sourcesRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources")
        let workflowRepair = sourcesRoot
            .appendingPathComponent("Workflow/RuntimeRepairLifecycle/RuntimeVMDiskRepairWorkflow.swift")
        let legacyRepair = sourcesRoot
            .appendingPathComponent("RuntimeWorkflow/VMDiskRepair/RuntimeVMDiskRepairWorkflow.swift")

        assertFileExists(workflowRepair, "RuntimeVMDiskRepairRunner must live in final Workflow")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: legacyRepair.path),
            "RuntimeVMDiskRepairRunner must not remain in transitional RuntimeWorkflow"
        )

        let contents = try String(contentsOf: workflowRepair, encoding: .utf8)
        XCTAssertTrue(contents.contains("public struct RuntimeVMDiskRepairRunner"))
        XCTAssertFalse(contents.contains("import Core"))
        XCTAssertFalse(contents.contains("import RuntimeWorkflow"))
        XCTAssertTrue(contents.contains("public enum RuntimeVMDiskRepairWorkflowError"))
    }

    func testBundlePreparationWorkflowLivesInFinalWorkflowLayer() throws {
        let sourcesRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources")
        let workflowPreparation = sourcesRoot
            .appendingPathComponent("Workflow/RuntimeUpdateLifecycle/RuntimeBundlePreparationWorkflow.swift")
        let legacyPreparation = sourcesRoot
            .appendingPathComponent("RuntimeWorkflow/ApplyBundle/RuntimeBundlePreparationWorkflow.swift")

        assertFileExists(workflowPreparation, "RuntimeBundlePreparationWorkflow must live in final Workflow")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: legacyPreparation.path),
            "RuntimeBundlePreparationWorkflow must not remain in transitional RuntimeWorkflow"
        )

        let contents = try String(contentsOf: workflowPreparation, encoding: .utf8)
        XCTAssertFalse(contents.contains("import Core"))
        XCTAssertFalse(contents.contains("import RuntimeWorkflow"))
        XCTAssertTrue(contents.contains("public struct RuntimeBundlePreparationWorkflow"))
    }

    func testBundleStagerLivesInFinalWorkflowLayer() throws {
        let sourcesRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources")
        let workflowStager = sourcesRoot
            .appendingPathComponent("Workflow/RuntimeUpdateLifecycle/RuntimeBundleStager.swift")
        let legacyStager = sourcesRoot
            .appendingPathComponent("HostCLI/Runtime/RuntimeBundleStager.swift")

        assertFileExists(workflowStager, "RuntimeBundleStager must live in final Workflow")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: legacyStager.path),
            "RuntimeBundleStager must not remain in HostCLI"
        )

        let contents = try String(contentsOf: workflowStager, encoding: .utf8)
        XCTAssertFalse(contents.contains("import Core"))
        XCTAssertFalse(contents.contains("import RuntimeWorkflow"))
        XCTAssertTrue(contents.contains("public struct RuntimeBundleStager"))
    }

    func testUpdateBundleVerificationPolicyLivesInDomainWithCoreAliasesOnly() throws {
        let sourcesRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources")
        let domainVerifier = sourcesRoot.appendingPathComponent("Domain/Policies/UpdateBundleVerifier.swift")
        let domainArchiveVerifier = sourcesRoot.appendingPathComponent("Domain/Policies/UpdateBundleArchiveVerifier.swift")
        let domainChecksumParser = sourcesRoot.appendingPathComponent("Domain/Policies/UpdateBundleChecksumFileParser.swift")
        let domainCompatibility = sourcesRoot.appendingPathComponent("Domain/Policies/RuntimeUpdateCompatibilityChecker.swift")
        let domainPreflight = sourcesRoot.appendingPathComponent("Domain/Policies/RuntimeUpdatePreflightPolicy.swift")
        let domainPreflightContext = sourcesRoot.appendingPathComponent("Domain/Models/ApplyBundlePreflight.swift")
        let domainPlanRunner = sourcesRoot.appendingPathComponent("Domain/Models/RuntimeOperationPlanRunner.swift")
        let coreVerifier = sourcesRoot.appendingPathComponent("Core/Verification/UpdateBundleVerifier.swift")
        let coreArchiveVerifier = sourcesRoot.appendingPathComponent("Core/Verification/UpdateBundleArchiveVerifier.swift")
        let coreChecksumParser = sourcesRoot.appendingPathComponent("Core/Verification/UpdateBundleChecksumFileParser.swift")
        let coreCompatibility = sourcesRoot.appendingPathComponent("Core/Policy/RuntimeUpdateCompatibilityChecker.swift")
        let corePreflight = sourcesRoot.appendingPathComponent("Core/Policy/RuntimeUpdatePreflightPolicy.swift")
        let corePreflightContext = sourcesRoot.appendingPathComponent("Core/Preflight/ApplyBundlePreflight.swift")
        let corePlanRunner = sourcesRoot.appendingPathComponent("Core/Plan/RuntimeOperationPlanRunner.swift")

        assertFileExists(domainVerifier, "UpdateBundleVerifier implementation must live in Domain")
        assertFileExists(domainArchiveVerifier, "UpdateBundleArchiveVerifier implementation must live in Domain")
        assertFileExists(domainChecksumParser, "UpdateBundleChecksumFileParser implementation must live in Domain")
        assertFileExists(domainCompatibility, "RuntimeUpdateCompatibilityChecker implementation must live in Domain")
        assertFileExists(domainPreflight, "RuntimeUpdatePreflightPolicy implementation must live in Domain")
        assertFileExists(domainPreflightContext, "ApplyBundlePreflightContext implementation must live in Domain")
        assertFileExists(domainPlanRunner, "RuntimeOperationPlanRunner implementation must live in Domain")

        let domainVerifierContents = try String(contentsOf: domainVerifier, encoding: .utf8)
        let domainArchiveContents = try String(contentsOf: domainArchiveVerifier, encoding: .utf8)
        let domainChecksumContents = try String(contentsOf: domainChecksumParser, encoding: .utf8)
        let domainCompatibilityContents = try String(contentsOf: domainCompatibility, encoding: .utf8)
        let domainPreflightContents = try String(contentsOf: domainPreflight, encoding: .utf8)
        let domainPreflightContextContents = try String(contentsOf: domainPreflightContext, encoding: .utf8)
        let domainPlanRunnerContents = try String(contentsOf: domainPlanRunner, encoding: .utf8)
        XCTAssertTrue(domainVerifierContents.contains("public enum UpdateBundleVerifier"))
        XCTAssertTrue(domainArchiveContents.contains("public enum UpdateBundleArchiveVerifier"))
        XCTAssertTrue(domainChecksumContents.contains("public enum UpdateBundleChecksumFileParser"))
        XCTAssertTrue(domainCompatibilityContents.contains("public enum RuntimeUpdateCompatibilityChecker"))
        XCTAssertTrue(domainPreflightContents.contains("public enum RuntimeUpdatePreflightPolicy"))
        XCTAssertTrue(domainPreflightContextContents.contains("public struct ApplyBundlePreflightContext"))
        XCTAssertTrue(domainPlanRunnerContents.contains("public enum RuntimeOperationPlanRunner"))
        XCTAssertFalse(domainVerifierContents.contains("import Core"))
        XCTAssertFalse(domainArchiveContents.contains("import Core"))
        XCTAssertFalse(domainChecksumContents.contains("import Core"))
        XCTAssertFalse(domainCompatibilityContents.contains("import Core"))
        XCTAssertFalse(domainPreflightContents.contains("import Core"))
        XCTAssertFalse(domainPreflightContextContents.contains("import Core"))
        XCTAssertFalse(domainPlanRunnerContents.contains("import Core"))

        let coreVerifierContents = try String(contentsOf: coreVerifier, encoding: .utf8)
        let coreArchiveContents = try String(contentsOf: coreArchiveVerifier, encoding: .utf8)
        let coreChecksumContents = try String(contentsOf: coreChecksumParser, encoding: .utf8)
        let coreCompatibilityContents = try String(contentsOf: coreCompatibility, encoding: .utf8)
        let corePreflightContents = try String(contentsOf: corePreflight, encoding: .utf8)
        let corePreflightContextContents = try String(contentsOf: corePreflightContext, encoding: .utf8)
        let corePlanRunnerContents = try String(contentsOf: corePlanRunner, encoding: .utf8)
        XCTAssertTrue(coreVerifierContents.contains("public typealias UpdateBundleVerifier = Domain.UpdateBundleVerifier"))
        XCTAssertTrue(coreArchiveContents.contains("public typealias UpdateBundleArchiveVerifier = Domain.UpdateBundleArchiveVerifier"))
        XCTAssertTrue(coreChecksumContents.contains("public typealias UpdateBundleChecksumFileParser = Domain.UpdateBundleChecksumFileParser"))
        XCTAssertTrue(coreCompatibilityContents.contains("public typealias RuntimeUpdateCompatibilityChecker = Domain.RuntimeUpdateCompatibilityChecker"))
        XCTAssertTrue(corePreflightContents.contains("public typealias RuntimeUpdatePreflightPolicy = Domain.RuntimeUpdatePreflightPolicy"))
        XCTAssertTrue(corePreflightContextContents.contains("public typealias ApplyBundlePreflightContext = Domain.ApplyBundlePreflightContext"))
        XCTAssertTrue(corePlanRunnerContents.contains("public typealias RuntimeOperationPlanRunner = Domain.RuntimeOperationPlanRunner"))
        XCTAssertFalse(coreVerifierContents.contains("public enum UpdateBundleVerifier"))
        XCTAssertFalse(coreArchiveContents.contains("public enum UpdateBundleArchiveVerifier"))
        XCTAssertFalse(coreChecksumContents.contains("public enum UpdateBundleChecksumFileParser"))
        XCTAssertFalse(coreCompatibilityContents.contains("public enum RuntimeUpdateCompatibilityChecker"))
        XCTAssertFalse(corePreflightContents.contains("public enum RuntimeUpdatePreflightPolicy"))
        XCTAssertFalse(corePreflightContextContents.contains("public struct ApplyBundlePreflightContext"))
        XCTAssertFalse(corePlanRunnerContents.contains("public enum RuntimeOperationPlanRunner"))
    }

    func testHealthBootstrapStatusAndEventPoliciesLiveInDomainWithCoreAliasesOnly() throws {
        let sourcesRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources")
        let files: [(domain: String, core: String, declaration: String, alias: String)] = [
            (
                "Domain/Policies/GuestBootstrapEvaluator.swift",
                "Core/Guest/GuestBootstrapEvaluator.swift",
                "public enum GuestBootstrapEvaluator",
                "public typealias GuestBootstrapEvaluator = Domain.GuestBootstrapEvaluator"
            ),
            (
                "Domain/Policies/RuntimeHealthEvaluator.swift",
                "Core/Health/RuntimeHealthEvaluator.swift",
                "public enum RuntimeHealthEvaluator",
                "public typealias RuntimeHealthEvaluator = Domain.RuntimeHealthEvaluator"
            ),
            (
                "Domain/Policies/RuntimeVMHealthPolicy.swift",
                "Core/Health/RuntimeVMHealthPolicy.swift",
                "public enum RuntimeVMHealthPolicy",
                "public typealias RuntimeVMHealthPolicy = Domain.RuntimeVMHealthPolicy"
            ),
            (
                "Domain/Models/RuntimeStatusDocumentBuilder.swift",
                "Core/Document/RuntimeStatusDocumentBuilder.swift",
                "public enum RuntimeStatusDocumentBuilder",
                "public typealias RuntimeStatusDocumentBuilder = Domain.RuntimeStatusDocumentBuilder"
            ),
            (
                "Domain/Policies/RuntimeObservedEventTypePolicy.swift",
                "Core/Policy/RuntimeObservedEventTypePolicy.swift",
                "public enum RuntimeObservedEventTypePolicy",
                "public typealias RuntimeObservedEventTypePolicy = Domain.RuntimeObservedEventTypePolicy"
            ),
            (
                "Domain/Policies/RuntimeInstallProvisionPayloadPolicy.swift",
                "Core/Policy/RuntimeInstallProvisionPayloadPolicy.swift",
                "public enum RuntimeInstallProvisionPayloadPolicy",
                "public typealias RuntimeInstallProvisionPayloadPolicy = Domain.RuntimeInstallProvisionPayloadPolicy"
            ),
            (
                "Domain/Policies/RuntimeManagedOperationPolicy.swift",
                "Core/Policy/RuntimeManagedOperationPolicy.swift",
                "public enum RuntimeManagedOperationPolicy",
                "public typealias RuntimeManagedOperationPolicy = Domain.RuntimeManagedOperationPolicy"
            ),
        ]

        for file in files {
            let domainFile = sourcesRoot.appendingPathComponent(file.domain)
            let coreFile = sourcesRoot.appendingPathComponent(file.core)
            assertFileExists(domainFile, "\(file.declaration) implementation must live in Domain")
            assertFileExists(coreFile, "\(file.alias) shim must remain explicit while Core is transitional")

            let domainContents = try String(contentsOf: domainFile, encoding: .utf8)
            let coreContents = try String(contentsOf: coreFile, encoding: .utf8)
            XCTAssertTrue(domainContents.contains(file.declaration), "\(file.domain) must own the implementation")
            XCTAssertFalse(domainContents.contains("import Core"), "\(file.domain) must not import Core")
            XCTAssertTrue(coreContents.contains(file.alias), "\(file.core) must point to Domain")
            XCTAssertFalse(coreContents.contains(file.declaration), "\(file.core) must not retain implementation")
        }
    }

    func testBundleVerificationWorkflowsLiveInFinalWorkflowLayer() throws {
        let sourcesRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources")
        let movedFiles = [
            "RuntimeArtifactReplacer.swift",
            "RuntimeApplyBundlePreflightRunner.swift",
            "RuntimeApplyBundleRunner.swift",
            "RuntimeApplyBundleStepExecutor.swift",
            "RuntimeApplyBundleWorkflow.swift",
            "RuntimeBundleDigestVerifier.swift",
            "RuntimeBundleDirectoryVerifier.swift",
            "RuntimeBundleMaterializer.swift",
            "RuntimeGuestActivationRunner.swift",
            "RuntimeGuestActivationWorkflow.swift",
            "RuntimeGuestShutdownRunner.swift",
            "RuntimeGuestShutdownWorkflow.swift",
            "RuntimeMigrationRunner.swift",
        ]

        for fileName in movedFiles {
            let workflowFile = sourcesRoot.appendingPathComponent("Workflow/RuntimeUpdateLifecycle/\(fileName)")
            let hostCLILegacyFile = sourcesRoot.appendingPathComponent("HostCLI/Runtime/\(fileName)")
            let runtimeWorkflowLegacyFile = sourcesRoot.appendingPathComponent("RuntimeWorkflow/ApplyBundle/\(fileName)")
            assertFileExists(workflowFile, "\(fileName) must live in final Workflow")
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: hostCLILegacyFile.path),
                "\(fileName) must not remain in HostCLI"
            )
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: runtimeWorkflowLegacyFile.path),
                "\(fileName) must not remain in transitional RuntimeWorkflow"
            )

            let contents = try String(contentsOf: workflowFile, encoding: .utf8)
            XCTAssertFalse(contents.contains("import Core"), "\(fileName) must not import Core")
            XCTAssertFalse(contents.contains("import RuntimeWorkflow"), "\(fileName) must not import RuntimeWorkflow")
        }
    }

    func testGuestCapabilityGateLivesInFinalWorkflowLayerWithHostCLIAliasesOnly() throws {
        let sourcesRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources")
        let workflowFile = sourcesRoot
            .appendingPathComponent("Workflow/RuntimeUpdateLifecycle/RuntimeGuestCapabilityChecker.swift")
        let hostCLIFile = sourcesRoot
            .appendingPathComponent("HostCLI/Runtime/RuntimeGuestCapabilityChecker.swift")
        let bootstrapCompositionFile = sourcesRoot
            .appendingPathComponent("Bootstrap/Composition/RuntimeGuestCapabilityCheckerComposition.swift")
        let hostCLICompositionShimFile = sourcesRoot
            .appendingPathComponent("HostCLI/Runtime/RuntimeGuestCapabilityCheckerComposition.swift")
        let hostCLIWorkflowFile = sourcesRoot
            .appendingPathComponent("HostCLI/Runtime/RuntimeLifecycle+Workflows.swift")

        assertFileExists(workflowFile, "RuntimeGuestCapabilityChecker must live in final Workflow")
        assertFileExists(hostCLIFile, "RuntimeGuestCapabilityChecker HostCLI shim must remain explicit")
        assertFileExists(
            bootstrapCompositionFile,
            "RuntimeGuestCapabilityCheckerComposition must live in Bootstrap"
        )
        assertFileExists(
            hostCLICompositionShimFile,
            "RuntimeGuestCapabilityCheckerComposition HostCLI shim must remain explicit"
        )

        let workflowContents = try String(contentsOf: workflowFile, encoding: .utf8)
        let hostCLIContents = try String(contentsOf: hostCLIFile, encoding: .utf8)
        let bootstrapCompositionContents = try String(contentsOf: bootstrapCompositionFile, encoding: .utf8)
        let hostCLICompositionShimContents = try String(contentsOf: hostCLICompositionShimFile, encoding: .utf8)
        let hostCLIWorkflowContents = try String(contentsOf: hostCLIWorkflowFile, encoding: .utf8)
        guard let requireCapabilityStart = hostCLIWorkflowContents.range(of: "func requireGuestCapability"),
              let requireCapabilityEnd = hostCLIWorkflowContents.range(
                  of: "private extension RuntimeLifecycle",
                  range: requireCapabilityStart.upperBound..<hostCLIWorkflowContents.endIndex
              )
        else {
            XCTFail("HostCLI requireGuestCapability helper must remain discoverable")
            return
        }
        let hostCLIRequireCapabilityContents = String(
            hostCLIWorkflowContents[requireCapabilityStart.lowerBound..<requireCapabilityEnd.lowerBound]
        )

        XCTAssertTrue(workflowContents.contains("public enum RuntimeGuestCapabilityCheckError"))
        XCTAssertTrue(workflowContents.contains("public struct RuntimeGuestCapabilityChecker"))
        XCTAssertFalse(workflowContents.contains("import Core"))
        XCTAssertFalse(workflowContents.contains("import HostCLI"))
        XCTAssertFalse(workflowContents.contains("LauncherError"))

        XCTAssertTrue(
            hostCLIContents.contains(
                "typealias RuntimeGuestCapabilityCheckError = Workflow.RuntimeGuestCapabilityCheckError"
            )
        )
        XCTAssertTrue(
            hostCLIContents.contains(
                "typealias RuntimeGuestCapabilityChecker = Workflow.RuntimeGuestCapabilityChecker"
            )
        )
        XCTAssertFalse(
            hostCLIContents.contains("public struct RuntimeGuestCapabilityChecker"),
            "HostCLI must not retain guest capability checker implementation"
        )
        XCTAssertFalse(
            hostCLIContents.contains("public enum RuntimeGuestCapabilityCheckError"),
            "HostCLI must not retain guest capability error implementation"
        )
        XCTAssertTrue(
            bootstrapCompositionContents.contains("public enum RuntimeGuestCapabilityCheckerComposition")
        )
        XCTAssertTrue(bootstrapCompositionContents.contains("RuntimeGuestCapabilityChecker("))
        XCTAssertTrue(bootstrapCompositionContents.contains("guestGateway.loadRuntimeStateDocument()"))
        XCTAssertFalse(bootstrapCompositionContents.contains("import HostCLI"))
        XCTAssertFalse(bootstrapCompositionContents.contains("import Core"))
        XCTAssertFalse(bootstrapCompositionContents.contains("import HostInfrastructure"))
        XCTAssertTrue(
            hostCLICompositionShimContents.contains(
                "typealias RuntimeGuestCapabilityCheckerComposition = Bootstrap.RuntimeGuestCapabilityCheckerComposition"
            )
        )
        XCTAssertFalse(hostCLICompositionShimContents.contains("enum RuntimeGuestCapabilityCheckerComposition"))
        XCTAssertTrue(hostCLIRequireCapabilityContents.contains("RuntimeGuestCapabilityCheckerComposition.make"))
        XCTAssertFalse(hostCLIRequireCapabilityContents.contains("RuntimeGuestCapabilityChecker("))
        XCTAssertFalse(hostCLIRequireCapabilityContents.contains("loadRuntimeStateDocument"))
    }

    func testRuntimeWorkflowStatusReporterLivesInFinalWorkflowSharedLayer() throws {
        let sourcesRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources")
        let bootstrapCompositionFile = sourcesRoot
            .appendingPathComponent("Bootstrap/Composition/RuntimeWorkflowStatusReporterComposition.swift")
        let hostCLICompositionShimFile = sourcesRoot
            .appendingPathComponent("HostCLI/Runtime/RuntimeWorkflowStatusReporterComposition.swift")
        let statusWriterCompositionFile = sourcesRoot
            .appendingPathComponent("Bootstrap/Composition/RuntimeStatusWriterComposition.swift")
        let hostCLIStatusWriterCompositionShimFile = sourcesRoot
            .appendingPathComponent("HostCLI/Runtime/RuntimeStatusWriterComposition.swift")
        let hostCLIWorkflowFile = sourcesRoot
            .appendingPathComponent("HostCLI/Runtime/RuntimeLifecycle+Workflows.swift")
        let hostCLISupportFile = sourcesRoot
            .appendingPathComponent("HostCLI/Runtime/RuntimeLifecycle+Support.swift")
        let files: [(workflow: String, legacy: String?, declaration: String, alias: String?)] = [
            (
                "Workflow/RuntimeShared/RuntimeWorkflowStatusReporter.swift",
                "RuntimeWorkflow/Shared/RuntimeWorkflowStatusReporter.swift",
                "public struct RuntimeWorkflowStatusReporter",
                nil
            ),
            (
                "Workflow/RuntimeShared/RuntimeStatusReporter.swift",
                "HostCLI/Runtime/RuntimeStatusReporter.swift",
                "public struct RuntimeStatusReporter",
                "typealias RuntimeStatusReporter = Workflow.RuntimeStatusReporter"
            ),
            (
                "Workflow/RuntimeShared/RuntimeStatusReporter.swift",
                "HostCLI/Runtime/RuntimeStatusReporter.swift",
                "public enum RuntimeStatusReporterError",
                "typealias RuntimeStatusReporterError = Workflow.RuntimeStatusReporterError"
            ),
            (
                "Workflow/RuntimeShared/RuntimeStatusWriter.swift",
                "HostCLI/Runtime/RuntimeStatusWriter.swift",
                "public struct RuntimeStatusWriter",
                "typealias RuntimeStatusWriter = Workflow.RuntimeStatusWriter"
            ),
            (
                "Workflow/RuntimeShared/RuntimeEventFactory.swift",
                "HostCLI/Runtime/RuntimeEventFactory.swift",
                "public struct RuntimeEventFactory",
                "typealias RuntimeEventFactory = Workflow.RuntimeEventFactory"
            ),
            (
                "Workflow/RuntimeShared/RuntimeObservationRecorder.swift",
                "HostCLI/Runtime/RuntimeObservationRecorder.swift",
                "public struct RuntimeObservationRecorder",
                "typealias RuntimeObservationRecorder = Workflow.RuntimeObservationRecorder"
            ),
            (
                "Workflow/RuntimeShared/RuntimeEventPublisher.swift",
                "HostCLI/Runtime/RuntimeEventPublisher.swift",
                "public struct RuntimeEventPublisher",
                "typealias RuntimeEventPublisher = Workflow.RuntimeEventPublisher"
            ),
            (
                "Workflow/RuntimeShared/RuntimeObservedEventPublisher.swift",
                "HostCLI/Runtime/RuntimeObservedEventPublisher.swift",
                "public struct RuntimeObservedEventPublisher",
                "typealias RuntimeObservedEventPublisher = Workflow.RuntimeObservedEventPublisher"
            ),
            (
                "Workflow/RuntimeShared/RuntimeObservedStatusPublisher.swift",
                "HostCLI/Runtime/RuntimeObservedStatusPublisher.swift",
                "public struct RuntimeObservedStatusPublisher",
                "typealias RuntimeObservedStatusPublisher = Workflow.RuntimeObservedStatusPublisher"
            ),
            (
                "Workflow/RuntimeShared/RuntimeVitalDBObservationProjector.swift",
                "HostCLI/Runtime/RuntimeVitalDBObservationProjector.swift",
                "public struct RuntimeVitalDBObservationProjector",
                "typealias RuntimeVitalDBObservationProjector = Workflow.RuntimeVitalDBObservationProjector"
            ),
            (
                "Workflow/RuntimeShared/RuntimeCommandExecutor.swift",
                "HostCLI/Runtime/RuntimeCommandExecutor.swift",
                "public enum RuntimeCommandExecutionError",
                "typealias RuntimeCommandExecutionError = Workflow.RuntimeCommandExecutionError"
            ),
            (
                "Workflow/RuntimeShared/RuntimeCommandExecutor.swift",
                "HostCLI/Runtime/RuntimeCommandExecutor.swift",
                "public struct RuntimeCommandExecutor",
                "typealias RuntimeCommandExecutor = Workflow.RuntimeCommandExecutor"
            ),
            (
                "Workflow/RuntimeShared/RuntimeWorkflowBestEffortRecording.swift",
                "HostCLI/Runtime/RuntimeBestEffortRecording.swift",
                "public func writeRuntimeStatusBestEffort",
                nil
            ),
            (
                "Workflow/RuntimeShared/RuntimeWorkflowBestEffortRecording.swift",
                "HostCLI/Runtime/RuntimeBestEffortRecording.swift",
                "public func writeRuntimeProgressBestEffort",
                nil
            ),
            (
                "Workflow/RuntimeShared/RuntimeWorkflowBestEffortRecording.swift",
                "HostCLI/Runtime/RuntimeBestEffortRecording.swift",
                "public func recordRuntimeObservedEventBestEffort",
                nil
            ),
            (
                "Workflow/RuntimeHealth/RuntimeGuestRuntimeStateObservationReader.swift",
                "HostCLI/Runtime/RuntimeGuestRuntimeStateObservationReader.swift",
                "public struct RuntimeGuestRuntimeStateObservation",
                "typealias RuntimeGuestRuntimeStateObservation = Workflow.RuntimeGuestRuntimeStateObservation"
            ),
            (
                "Workflow/RuntimeHealth/RuntimeGuestRuntimeStateObservationReader.swift",
                "HostCLI/Runtime/RuntimeGuestRuntimeStateObservationReader.swift",
                "public struct RuntimeGuestRuntimeStateObservationReader",
                "typealias RuntimeGuestRuntimeStateObservationReader = Workflow.RuntimeGuestRuntimeStateObservationReader"
            ),
        ]

        for file in files {
            let workflowFile = sourcesRoot.appendingPathComponent(file.workflow)
            assertFileExists(workflowFile, "\(file.declaration) must live in final Workflow shared layer")

            let contents = try String(contentsOf: workflowFile, encoding: .utf8)
            XCTAssertTrue(contents.contains(file.declaration))
            XCTAssertFalse(contents.contains("import Core"))
            XCTAssertFalse(contents.contains("import RuntimeWorkflow"))
            XCTAssertFalse(contents.contains("import HostCLI"))

            guard let legacy = file.legacy else {
                continue
            }
            let legacyFile = sourcesRoot.appendingPathComponent(legacy)
            if let alias = file.alias {
                assertFileExists(legacyFile, "\(alias) shim must remain explicit while legacy target is transitional")
                let legacyContents = try String(contentsOf: legacyFile, encoding: .utf8)
                XCTAssertTrue(legacyContents.contains(alias), "\(legacy) must point to Workflow")
                XCTAssertFalse(legacyContents.contains(file.declaration), "\(legacy) must not retain implementation")
            } else {
                XCTAssertFalse(
                    FileManager.default.fileExists(atPath: legacyFile.path),
                    "\(file.declaration) must not remain in transitional RuntimeWorkflow"
                )
            }
        }

        assertFileExists(
            bootstrapCompositionFile,
            "RuntimeWorkflowStatusReporterComposition must live in Bootstrap"
        )
        assertFileExists(
            hostCLICompositionShimFile,
            "RuntimeWorkflowStatusReporterComposition HostCLI shim must remain explicit"
        )
        assertFileExists(statusWriterCompositionFile, "RuntimeStatusWriterComposition must live in Bootstrap")
        assertFileExists(
            hostCLIStatusWriterCompositionShimFile,
            "RuntimeStatusWriterComposition HostCLI shim must remain explicit"
        )

        let bootstrapCompositionContents = try String(contentsOf: bootstrapCompositionFile, encoding: .utf8)
        let hostCLICompositionShimContents = try String(contentsOf: hostCLICompositionShimFile, encoding: .utf8)
        let statusWriterCompositionContents = try String(contentsOf: statusWriterCompositionFile, encoding: .utf8)
        let hostCLIStatusWriterCompositionShimContents = try String(
            contentsOf: hostCLIStatusWriterCompositionShimFile,
            encoding: .utf8
        )
        let hostCLIWorkflowContents = try String(contentsOf: hostCLIWorkflowFile, encoding: .utf8)
        let hostCLISupportContents = try String(contentsOf: hostCLISupportFile, encoding: .utf8)
        guard let statusReporterStart = hostCLIWorkflowContents.range(of: "func runtimeWorkflowStatusReporter"),
              let statusReporterEnd = hostCLIWorkflowContents.range(
                  of: "func runtimeStatusWriterAction",
                  range: statusReporterStart.upperBound..<hostCLIWorkflowContents.endIndex
              )
        else {
            XCTFail("HostCLI runtime workflow status reporter helper must remain discoverable")
            return
        }
        let hostCLIStatusReporterContents = String(
            hostCLIWorkflowContents[statusReporterStart.lowerBound..<statusReporterEnd.lowerBound]
        )
        guard let statusWriterStart = hostCLISupportContents.range(of: "func runtimeStatusWriter"),
              let statusWriterEnd = hostCLISupportContents.range(
                  of: "func runtimeObservedStatusPublisher",
                  range: statusWriterStart.upperBound..<hostCLISupportContents.endIndex
              )
        else {
            XCTFail("HostCLI runtime status writer helper must remain discoverable")
            return
        }
        let hostCLIStatusWriterContents = String(
            hostCLISupportContents[statusWriterStart.lowerBound..<statusWriterEnd.lowerBound]
        )

        XCTAssertTrue(
            bootstrapCompositionContents.contains("public enum RuntimeWorkflowStatusReporterComposition")
        )
        XCTAssertTrue(bootstrapCompositionContents.contains("RuntimeWorkflowStatusReporter("))
        XCTAssertFalse(bootstrapCompositionContents.contains("import HostCLI"))
        XCTAssertFalse(bootstrapCompositionContents.contains("import Core"))
        XCTAssertFalse(bootstrapCompositionContents.contains("import HostInfrastructure"))
        XCTAssertTrue(
            hostCLICompositionShimContents.contains(
                "typealias RuntimeWorkflowStatusReporterComposition = Bootstrap.RuntimeWorkflowStatusReporterComposition"
            )
        )
        XCTAssertFalse(
            hostCLICompositionShimContents.contains("enum RuntimeWorkflowStatusReporterComposition"),
            "HostCLI must not retain workflow status reporter composition implementation"
        )
        XCTAssertTrue(hostCLIStatusReporterContents.contains("RuntimeWorkflowStatusReporterComposition.make"))
        XCTAssertFalse(
            hostCLIStatusReporterContents.contains("RuntimeWorkflowStatusReporter("),
            "HostCLI must not assemble RuntimeWorkflowStatusReporter directly"
        )
        XCTAssertTrue(statusWriterCompositionContents.contains("public struct RuntimeStatusWriterCompositionOperations"))
        XCTAssertTrue(statusWriterCompositionContents.contains("public enum RuntimeStatusWriterComposition"))
        XCTAssertTrue(statusWriterCompositionContents.contains("RuntimeStatusWriter("))
        XCTAssertFalse(statusWriterCompositionContents.contains("import HostCLI"))
        XCTAssertFalse(statusWriterCompositionContents.contains("import Core"))
        XCTAssertFalse(statusWriterCompositionContents.contains("import HostInfrastructure"))
        XCTAssertTrue(
            hostCLIStatusWriterCompositionShimContents.contains(
                "typealias RuntimeStatusWriterCompositionOperations = Bootstrap.RuntimeStatusWriterCompositionOperations"
            )
        )
        XCTAssertTrue(
            hostCLIStatusWriterCompositionShimContents.contains(
                "typealias RuntimeStatusWriterComposition = Bootstrap.RuntimeStatusWriterComposition"
            )
        )
        XCTAssertFalse(hostCLIStatusWriterCompositionShimContents.contains("enum RuntimeStatusWriterComposition"))
        XCTAssertTrue(hostCLIStatusWriterContents.contains("RuntimeStatusWriterComposition.make"))
        XCTAssertFalse(
            hostCLIStatusWriterContents.contains("RuntimeStatusWriter("),
            "HostCLI must not assemble RuntimeStatusWriter directly"
        )
    }

    func testGuestUpdateWaitPoliciesLiveInDomainWithCoreAliasesOnly() throws {
        let sourcesRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources")
        let domainActivation = sourcesRoot.appendingPathComponent("Domain/Policies/GuestActivationEvaluator.swift")
        let domainShutdown = sourcesRoot.appendingPathComponent("Domain/Policies/GuestShutdownEvaluator.swift")
        let domainDatastoreRepair = sourcesRoot.appendingPathComponent("Domain/Policies/DatastoreRepairEvaluator.swift")
        let coreActivation = sourcesRoot.appendingPathComponent("Core/Guest/GuestActivationEvaluator.swift")
        let coreShutdown = sourcesRoot.appendingPathComponent("Core/Guest/GuestShutdownEvaluator.swift")
        let coreDatastoreRepair = sourcesRoot.appendingPathComponent("Core/Guest/DatastoreRepairEvaluator.swift")

        assertFileExists(domainActivation, "GuestActivationEvaluator implementation must live in Domain")
        assertFileExists(domainShutdown, "GuestShutdownEvaluator implementation must live in Domain")
        assertFileExists(domainDatastoreRepair, "DatastoreRepairEvaluator implementation must live in Domain")

        let domainActivationContents = try String(contentsOf: domainActivation, encoding: .utf8)
        let domainShutdownContents = try String(contentsOf: domainShutdown, encoding: .utf8)
        let domainDatastoreRepairContents = try String(contentsOf: domainDatastoreRepair, encoding: .utf8)
        XCTAssertTrue(domainActivationContents.contains("public enum GuestActivationEvaluator"))
        XCTAssertTrue(domainShutdownContents.contains("public enum GuestShutdownEvaluator"))
        XCTAssertTrue(domainDatastoreRepairContents.contains("public enum DatastoreRepairEvaluator"))
        XCTAssertFalse(domainActivationContents.contains("import Core"))
        XCTAssertFalse(domainShutdownContents.contains("import Core"))
        XCTAssertFalse(domainDatastoreRepairContents.contains("import Core"))

        let coreActivationContents = try String(contentsOf: coreActivation, encoding: .utf8)
        let coreShutdownContents = try String(contentsOf: coreShutdown, encoding: .utf8)
        let coreDatastoreRepairContents = try String(contentsOf: coreDatastoreRepair, encoding: .utf8)
        XCTAssertTrue(coreActivationContents.contains("public typealias GuestActivationEvaluator = Domain.GuestActivationEvaluator"))
        XCTAssertTrue(coreShutdownContents.contains("public typealias GuestShutdownEvaluator = Domain.GuestShutdownEvaluator"))
        XCTAssertTrue(coreDatastoreRepairContents.contains("public typealias DatastoreRepairEvaluator = Domain.DatastoreRepairEvaluator"))
        XCTAssertFalse(coreActivationContents.contains("public enum GuestActivationEvaluator"))
        XCTAssertFalse(coreShutdownContents.contains("public enum GuestShutdownEvaluator"))
        XCTAssertFalse(coreDatastoreRepairContents.contains("public enum DatastoreRepairEvaluator"))
    }

    func testWatchdogRecoveryPolicyLivesInDomainWithCoreAliasesOnly() throws {
        let sourcesRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources")
        let domainRecoveryPlanner = sourcesRoot.appendingPathComponent("Domain/Policies/RuntimeRecoveryPlanner.swift")
        let domainWatchdogPolicy = sourcesRoot.appendingPathComponent("Domain/Policies/RuntimeWatchdogRecoveryPolicy.swift")
        let coreRecoveryPlanner = sourcesRoot.appendingPathComponent("Core/Health/RuntimeRecoveryPlanner.swift")
        let coreWatchdogPolicy = sourcesRoot.appendingPathComponent("Core/Health/RuntimeWatchdogRecoveryPolicy.swift")

        assertFileExists(domainRecoveryPlanner, "RuntimeRecoveryPlanner implementation must live in Domain")
        assertFileExists(domainWatchdogPolicy, "RuntimeWatchdogRecoveryPolicy implementation must live in Domain")

        let domainPlannerContents = try String(contentsOf: domainRecoveryPlanner, encoding: .utf8)
        let domainPolicyContents = try String(contentsOf: domainWatchdogPolicy, encoding: .utf8)
        XCTAssertTrue(domainPlannerContents.contains("public enum RuntimeRecoveryPlanner"))
        XCTAssertTrue(domainPolicyContents.contains("public enum RuntimeWatchdogRecoveryPolicy"))
        XCTAssertFalse(domainPlannerContents.contains("import Core"))
        XCTAssertFalse(domainPolicyContents.contains("import Core"))

        let corePlannerContents = try String(contentsOf: coreRecoveryPlanner, encoding: .utf8)
        let corePolicyContents = try String(contentsOf: coreWatchdogPolicy, encoding: .utf8)
        XCTAssertTrue(corePlannerContents.contains("public typealias RuntimeRecoveryPlanner = Domain.RuntimeRecoveryPlanner"))
        XCTAssertTrue(corePolicyContents.contains("public typealias RuntimeWatchdogRecoveryPolicy = Domain.RuntimeWatchdogRecoveryPolicy"))
        XCTAssertFalse(corePlannerContents.contains("public enum RuntimeRecoveryPlanner"))
        XCTAssertFalse(corePolicyContents.contains("public enum RuntimeWatchdogRecoveryPolicy"))
    }

    func testWatchdogRunnerLivesInFinalWorkflowLayer() throws {
        let sourcesRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources")
        let files: [(workflow: String, legacy: String, declaration: String, alias: String?)] = [
            (
                "Workflow/RuntimeWatchdog/RuntimeWatchdogRunner.swift",
                "RuntimeWorkflow/Watchdog/RuntimeWatchdogRunner.swift",
                "public struct RuntimeWatchdogRunner",
                nil
            ),
            (
                "Workflow/RuntimeWatchdog/RuntimeManagedOperationGuard.swift",
                "HostCLI/Runtime/RuntimeManagedOperationGuard.swift",
                "public struct RuntimeGuestBootstrapOperation",
                "typealias RuntimeGuestBootstrapOperation = Workflow.RuntimeGuestBootstrapOperation"
            ),
            (
                "Workflow/RuntimeWatchdog/RuntimeManagedOperationGuard.swift",
                "HostCLI/Runtime/RuntimeManagedOperationGuard.swift",
                "public struct RuntimeManagedOperationGuard",
                "typealias RuntimeManagedOperationGuard = Workflow.RuntimeManagedOperationGuard"
            ),
        ]

        for file in files {
            let workflowFile = sourcesRoot.appendingPathComponent(file.workflow)
            let legacyFile = sourcesRoot.appendingPathComponent(file.legacy)
            assertFileExists(workflowFile, "\(file.declaration) must live in final Workflow")

            let contents = try String(contentsOf: workflowFile, encoding: .utf8)
            XCTAssertTrue(contents.contains(file.declaration))
            XCTAssertFalse(contents.contains("import Core"))
            XCTAssertFalse(contents.contains("import RuntimeWorkflow"))
            XCTAssertFalse(contents.contains("import HostCLI"))

            if let alias = file.alias {
                assertFileExists(legacyFile, "\(alias) HostCLI shim must remain explicit")
                let legacyContents = try String(contentsOf: legacyFile, encoding: .utf8)
                XCTAssertTrue(legacyContents.contains(alias), "\(file.legacy) must point to Workflow")
                XCTAssertFalse(legacyContents.contains(file.declaration), "\(file.legacy) must not retain implementation")
            } else {
                XCTAssertFalse(
                    FileManager.default.fileExists(atPath: legacyFile.path),
                    "\(file.declaration) must not remain in transitional RuntimeWorkflow"
                )
            }
        }
    }

    func testRuntimeManagedOperationGuardCompositionLivesInBootstrapWithHostCLIAliasOnly() throws {
        let sourcesRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources")
        let bootstrapFile = sourcesRoot.appendingPathComponent(
            "Bootstrap/Composition/RuntimeManagedOperationGuardComposition.swift"
        )
        let hostCLIShimFile = sourcesRoot.appendingPathComponent(
            "HostCLI/Runtime/RuntimeManagedOperationGuardComposition.swift"
        )
        let hostCLIWorkflowFile = sourcesRoot.appendingPathComponent("HostCLI/Runtime/RuntimeLifecycle+Workflows.swift")

        assertFileExists(bootstrapFile, "managed-operation guard composition must live in Bootstrap")
        assertFileExists(hostCLIShimFile, "RuntimeManagedOperationGuardComposition HostCLI shim must remain explicit")

        let bootstrapContents = try String(contentsOf: bootstrapFile, encoding: .utf8)
        let hostCLIShimContents = try String(contentsOf: hostCLIShimFile, encoding: .utf8)
        let hostCLIWorkflowContents = try String(contentsOf: hostCLIWorkflowFile, encoding: .utf8)
        guard let guardStart = hostCLIWorkflowContents.range(of: "func runtimeManagedOperationGuard()"),
              let guardEnd = hostCLIWorkflowContents.range(
                  of: "func runtimeWatchdogRunner()",
                  range: guardStart.upperBound..<hostCLIWorkflowContents.endIndex
              )
        else {
            XCTFail("HostCLI runtimeManagedOperationGuard and runtimeWatchdogRunner functions must remain discoverable")
            return
        }
        let hostCLIGuardContents = String(hostCLIWorkflowContents[guardStart.lowerBound..<guardEnd.lowerBound])

        XCTAssertTrue(bootstrapContents.contains("public enum RuntimeManagedOperationGuardComposition"))
        XCTAssertTrue(bootstrapContents.contains("public static func make"))
        XCTAssertTrue(bootstrapContents.contains("RuntimeManagedOperationGuard("))
        XCTAssertTrue(bootstrapContents.contains("loadBootstrapResultDocument"))
        XCTAssertTrue(bootstrapContents.contains("loadRuntimeStateDocument"))
        XCTAssertTrue(bootstrapContents.contains("watchdogManagedOperationGraceSeconds"))
        XCTAssertTrue(bootstrapContents.contains("ISO8601DateFormatter"))
        XCTAssertFalse(bootstrapContents.contains("import HostCLI"))
        XCTAssertFalse(bootstrapContents.contains("import Core"))
        XCTAssertFalse(bootstrapContents.contains("import HostInfrastructure"))
        XCTAssertTrue(hostCLIShimContents.contains(
            "typealias RuntimeManagedOperationGuardComposition = Bootstrap.RuntimeManagedOperationGuardComposition"
        ))
        XCTAssertFalse(hostCLIShimContents.contains("enum RuntimeManagedOperationGuardComposition"))
        XCTAssertTrue(hostCLIGuardContents.contains("RuntimeManagedOperationGuardComposition.make"))
        XCTAssertFalse(hostCLIGuardContents.contains("RuntimeManagedOperationGuard("))
        XCTAssertFalse(hostCLIGuardContents.contains("loadBootstrapResultDocument"))
        XCTAssertFalse(hostCLIGuardContents.contains("loadRuntimeStateDocument"))
        XCTAssertFalse(hostCLIGuardContents.contains("watchdogManagedOperationGraceSeconds"))
        XCTAssertFalse(hostCLIGuardContents.contains("ISO8601DateFormatter"))
    }

    func testRuntimeWatchdogRunnerCompositionLivesInBootstrapWithHostCLIAliasesOnly() throws {
        let sourcesRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources")
        let bootstrapFile = sourcesRoot.appendingPathComponent(
            "Bootstrap/Composition/RuntimeWatchdogRunnerComposition.swift"
        )
        let hostCLIShimFile = sourcesRoot.appendingPathComponent(
            "HostCLI/Runtime/RuntimeWatchdogRunnerComposition.swift"
        )
        let hostCLIWorkflowFile = sourcesRoot.appendingPathComponent("HostCLI/Runtime/RuntimeLifecycle+Workflows.swift")

        assertFileExists(bootstrapFile, "watchdog runner composition must live in Bootstrap")
        assertFileExists(hostCLIShimFile, "RuntimeWatchdogRunnerComposition HostCLI shim must remain explicit")

        let bootstrapContents = try String(contentsOf: bootstrapFile, encoding: .utf8)
        let hostCLIShimContents = try String(contentsOf: hostCLIShimFile, encoding: .utf8)
        let hostCLIWorkflowContents = try String(contentsOf: hostCLIWorkflowFile, encoding: .utf8)
        guard let watchdogStart = hostCLIWorkflowContents.range(of: "func runtimeWatchdogRunner()"),
              let watchdogEnd = hostCLIWorkflowContents.range(
                  of: "func runtimeConfigureRunner()",
                  range: watchdogStart.upperBound..<hostCLIWorkflowContents.endIndex
              )
        else {
            XCTFail("HostCLI runtimeWatchdogRunner and runtimeConfigureRunner functions must remain discoverable")
            return
        }
        let hostCLIWatchdogContents = String(hostCLIWorkflowContents[watchdogStart.lowerBound..<watchdogEnd.lowerBound])

        XCTAssertTrue(bootstrapContents.contains("public struct RuntimeWatchdogRunnerCompositionContext"))
        XCTAssertTrue(bootstrapContents.contains("public struct RuntimeWatchdogRunnerCompositionOperations"))
        XCTAssertTrue(bootstrapContents.contains("public enum RuntimeWatchdogRunnerComposition"))
        XCTAssertTrue(bootstrapContents.contains("RuntimeWatchdogRunner("))
        XCTAssertTrue(bootstrapContents.contains("RuntimeWatchdogContext("))
        XCTAssertTrue(bootstrapContents.contains("RuntimeWatchdogActions("))
        XCTAssertTrue(bootstrapContents.contains("watchdogRecoveryWaitSeconds"))
        XCTAssertTrue(bootstrapContents.contains("proxyLivenessURL"))
        XCTAssertTrue(bootstrapContents.contains("RuntimeVMLifecycleStore("))
        XCTAssertTrue(bootstrapContents.contains("recordObservedStatus"))
        XCTAssertTrue(bootstrapContents.contains("watchdog log directory preparation failed"))
        XCTAssertFalse(bootstrapContents.contains("import HostCLI"))
        XCTAssertFalse(bootstrapContents.contains("import Core"))
        XCTAssertFalse(bootstrapContents.contains("import HostInfrastructure"))
        XCTAssertTrue(hostCLIShimContents.contains(
            "typealias RuntimeWatchdogRunnerCompositionContext = Bootstrap.RuntimeWatchdogRunnerCompositionContext"
        ))
        XCTAssertTrue(hostCLIShimContents.contains(
            "typealias RuntimeWatchdogRunnerCompositionOperations = Bootstrap.RuntimeWatchdogRunnerCompositionOperations"
        ))
        XCTAssertTrue(hostCLIShimContents.contains(
            "typealias RuntimeWatchdogRunnerComposition = Bootstrap.RuntimeWatchdogRunnerComposition"
        ))
        XCTAssertFalse(hostCLIShimContents.contains("struct RuntimeWatchdogRunnerCompositionContext"))
        XCTAssertTrue(hostCLIWatchdogContents.contains("RuntimeWatchdogRunnerComposition.make"))
        XCTAssertFalse(hostCLIWatchdogContents.contains("RuntimeWatchdogRunner("))
        XCTAssertFalse(hostCLIWatchdogContents.contains("RuntimeWatchdogContext("))
        XCTAssertFalse(hostCLIWatchdogContents.contains("RuntimeWatchdogActions("))
        XCTAssertFalse(hostCLIWatchdogContents.contains("watchdogRecoveryWaitSeconds"))
        XCTAssertFalse(hostCLIWatchdogContents.contains("proxyLivenessURL"))
        XCTAssertFalse(hostCLIWatchdogContents.contains("RuntimeVMLifecycleStore("))
        XCTAssertFalse(hostCLIWatchdogContents.contains("watchdog log directory preparation failed"))
    }

    func testRuntimeProcessResultLivesInContractsWithCoreAliasOnly() throws {
        let sourcesRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources")
        let contractResult = sourcesRoot.appendingPathComponent("Contracts/RuntimeProcessResult.swift")
        let contractGuestLoadResult = sourcesRoot.appendingPathComponent("Contracts/RuntimeGuestDocumentLoadResult.swift")
        let contractProxyPIDResult = sourcesRoot.appendingPathComponent("Contracts/RuntimeProxyNginxPIDReadResult.swift")
        let coreCommandRunner = sourcesRoot.appendingPathComponent("Core/Ports/RuntimeCommandRunner.swift")
        let coreGuestGateway = sourcesRoot.appendingPathComponent("Core/Ports/RuntimeGuestGateway.swift")
        let uninstallWorkflow = sourcesRoot.appendingPathComponent("Workflow/RuntimeUninstallLifecycle/RuntimeUninstallWorkflow.swift")

        assertFileExists(contractResult, "RuntimeProcessResult must live in Contracts as a shared process result contract")
        assertFileExists(
            contractGuestLoadResult,
            "RuntimeGuestDocumentLoadResult must live in Contracts as a shared guest document load contract"
        )
        assertFileExists(
            contractProxyPIDResult,
            "RuntimeProxyNginxPIDReadResult must live in Contracts as a shared host proxy PID read contract"
        )

        let contractContents = try String(contentsOf: contractResult, encoding: .utf8)
        XCTAssertTrue(contractContents.contains("public struct RuntimeProcessResult"))
        XCTAssertFalse(contractContents.contains("import Core"))
        let guestLoadContents = try String(contentsOf: contractGuestLoadResult, encoding: .utf8)
        XCTAssertTrue(guestLoadContents.contains("public enum RuntimeGuestDocumentLoadResult"))
        XCTAssertFalse(guestLoadContents.contains("import Core"))
        let proxyPIDContents = try String(contentsOf: contractProxyPIDResult, encoding: .utf8)
        XCTAssertTrue(proxyPIDContents.contains("public enum RuntimeProxyNginxPIDReadResult"))
        XCTAssertFalse(proxyPIDContents.contains("import Core"))

        let coreContents = try String(contentsOf: coreCommandRunner, encoding: .utf8)
        XCTAssertTrue(coreContents.contains("public typealias RuntimeProcessResult = Contracts.RuntimeProcessResult"))
        XCTAssertFalse(coreContents.contains("public struct RuntimeProcessResult"))
        let coreGuestGatewayContents = try String(contentsOf: coreGuestGateway, encoding: .utf8)
        XCTAssertTrue(
            coreGuestGatewayContents.contains(
                "public typealias RuntimeGuestDocumentLoadResult<Document> = Contracts.RuntimeGuestDocumentLoadResult<Document>"
            )
        )
        XCTAssertFalse(coreGuestGatewayContents.contains("public enum RuntimeGuestDocumentLoadResult"))

        let uninstallContents = try String(contentsOf: uninstallWorkflow, encoding: .utf8)
        XCTAssertFalse(uninstallContents.contains("import Core"))
    }

    func testRuntimePortsLiveInApplicationWithCoreAliasesOnly() throws {
        let sourcesRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources")
        let files: [(application: String, core: String, declaration: String, alias: String)] = [
            (
                "Application/Ports/RuntimeCommandRunner.swift",
                "Core/Ports/RuntimeCommandRunner.swift",
                "public protocol RuntimeCommandRunner",
                "public typealias RuntimeCommandRunner = Application.RuntimeCommandRunner"
            ),
            (
                "Application/Ports/RuntimeGuestGateway.swift",
                "Core/Ports/RuntimeGuestGateway.swift",
                "public protocol RuntimeGuestGateway",
                "public typealias RuntimeGuestGateway = Application.RuntimeGuestGateway"
            ),
            (
                "Application/Ports/RuntimeFileStore.swift",
                "Core/Ports/RuntimeFileStore.swift",
                "public protocol RuntimeFileStore",
                "public typealias RuntimeFileStore = Application.RuntimeFileStore"
            ),
            (
                "Application/Ports/RuntimeStorageUsageProvider.swift",
                "Core/Ports/RuntimeStorageUsageProvider.swift",
                "public protocol RuntimeStorageUsageProviding",
                "public typealias RuntimeStorageUsageProviding = Application.RuntimeStorageUsageProviding"
            ),
            (
                "Application/Ports/RuntimeTiming.swift",
                "Core/Ports/RuntimeTiming.swift",
                "public protocol RuntimeClock",
                "public typealias RuntimeClock = Application.RuntimeClock"
            ),
            (
                "Application/Ports/RuntimeHTTPProber.swift",
                "Core/Ports/RuntimeHTTPProber.swift",
                "public protocol RuntimeHTTPProber",
                "public typealias RuntimeHTTPProber = Application.RuntimeHTTPProber"
            ),
            (
                "Application/Ports/RuntimeServiceManager.swift",
                "Core/Ports/RuntimeServiceManager.swift",
                "public protocol RuntimeServiceManager",
                "public typealias RuntimeServiceManager = Application.RuntimeServiceManager"
            ),
            (
                "Application/Ports/RuntimeStatusRepository.swift",
                "Core/Ports/RuntimeStatusRepository.swift",
                "public protocol RuntimeStatusRepository",
                "public typealias RuntimeStatusRepository = Application.RuntimeStatusRepository"
            ),
            (
                "Application/Ports/RuntimeEventRepository.swift",
                "Core/Ports/RuntimeEventRepository.swift",
                "public protocol RuntimeEventRepository",
                "public typealias RuntimeEventRepository = Application.RuntimeEventRepository"
            ),
        ]

        for file in files {
            let applicationFile = sourcesRoot.appendingPathComponent(file.application)
            let coreFile = sourcesRoot.appendingPathComponent(file.core)
            assertFileExists(applicationFile, "\(file.declaration) must live in Application/Ports")
            assertFileExists(coreFile, "\(file.alias) shim must remain explicit while Core is transitional")

            let applicationContents = try String(contentsOf: applicationFile, encoding: .utf8)
            let coreContents = try String(contentsOf: coreFile, encoding: .utf8)
            XCTAssertTrue(applicationContents.contains(file.declaration), "\(file.application) must own the port")
            XCTAssertFalse(applicationContents.contains("import Core"), "\(file.application) must not import Core")
            XCTAssertTrue(coreContents.contains(file.alias), "\(file.core) must point to Application")
            XCTAssertFalse(coreContents.contains(file.declaration), "\(file.core) must not retain the protocol")
        }
    }

    func testHostInfrastructureImplementationsLiveInInfrastructureWithHostInfrastructureAliasesOnly() throws {
        let sourcesRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources")
        let files: [(infrastructure: String, legacy: String, declaration: String, alias: String)] = [
            (
                "Infrastructure/FileSystem/SystemRuntimeFileStore.swift",
                "HostInfrastructure/SystemRuntimeFileStore.swift",
                "public struct SystemRuntimeFileStore",
                "public typealias SystemRuntimeFileStore = Infrastructure.SystemRuntimeFileStore"
            ),
            (
                "Infrastructure/FileSystem/SystemRuntimeStorageUsageProvider.swift",
                "HostInfrastructure/SystemRuntimeStorageUsageProvider.swift",
                "public struct SystemRuntimeStorageUsageProvider",
                "public typealias SystemRuntimeStorageUsageProvider = Infrastructure.SystemRuntimeStorageUsageProvider"
            ),
            (
                "Infrastructure/FileSystem/InstalledRuntimePaths.swift",
                "HostInfrastructure/InstalledRuntimePaths.swift",
                "public struct InstalledRuntimePaths",
                "public typealias InstalledRuntimePaths = Infrastructure.InstalledRuntimePaths"
            ),
            (
                "Infrastructure/Repositories/JSONFileRuntimeStatusRepository.swift",
                "HostInfrastructure/JSONFileRuntimeStatusRepository.swift",
                "public struct JSONFileRuntimeStatusRepository",
                "public typealias JSONFileRuntimeStatusRepository = Infrastructure.JSONFileRuntimeStatusRepository"
            ),
            (
                "Infrastructure/Repositories/JSONFileRuntimeGuestGateway.swift",
                "HostInfrastructure/JSONFileRuntimeGuestGateway.swift",
                "public struct JSONFileRuntimeGuestGateway",
                "public typealias JSONFileRuntimeGuestGateway = Infrastructure.JSONFileRuntimeGuestGateway"
            ),
            (
                "Infrastructure/Repositories/JSONLRuntimeEventRepository.swift",
                "HostInfrastructure/JSONLRuntimeEventRepository.swift",
                "public struct JSONLRuntimeEventRepository",
                "public typealias JSONLRuntimeEventRepository = Infrastructure.JSONLRuntimeEventRepository"
            ),
            (
                "Infrastructure/Repositories/CompositeRuntimeEventRepository.swift",
                "HostInfrastructure/CompositeRuntimeEventRepository.swift",
                "public struct CompositeRuntimeEventRepository",
                "public typealias CompositeRuntimeEventRepository = Infrastructure.CompositeRuntimeEventRepository"
            ),
            (
                "Infrastructure/Repositories/SQLiteRuntimeEventRepository.swift",
                "HostInfrastructure/SQLiteRuntimeEventRepository.swift",
                "public struct SQLiteRuntimeEventRepository",
                "public typealias SQLiteRuntimeEventRepository = Infrastructure.SQLiteRuntimeEventRepository"
            ),
            (
                "Infrastructure/Repositories/RuntimeEventSQLiteProjectionCatchUp.swift",
                "HostInfrastructure/RuntimeEventSQLiteProjectionCatchUp.swift",
                "public struct RuntimeEventSQLiteProjectionCatchUp",
                "public typealias RuntimeEventSQLiteProjectionCatchUp = Infrastructure.RuntimeEventSQLiteProjectionCatchUp"
            ),
            (
                "Infrastructure/ObservabilityStore/SQLiteRuntimeObservabilityStore.swift",
                "HostInfrastructure/SQLiteRuntimeObservabilityStore.swift",
                "public struct SQLiteRuntimeObservabilityStore",
                "public typealias SQLiteRuntimeObservabilityStore = Infrastructure.SQLiteRuntimeObservabilityStore"
            ),
            (
                "Infrastructure/ObservabilityStore/SQLiteVitalDBObservationRepository.swift",
                "HostInfrastructure/SQLiteVitalDBObservationRepository.swift",
                "public struct SQLiteVitalDBObservationRepository",
                "public typealias SQLiteVitalDBObservationRepository = Infrastructure.SQLiteVitalDBObservationRepository"
            ),
            (
                "Infrastructure/ObservabilityStore/VitalDBRelationshipProjectionPlanner.swift",
                "HostInfrastructure/VitalDBRelationshipProjectionPlanner.swift",
                "public struct VitalDBRelationshipProjectionPlanner",
                "public typealias VitalDBRelationshipProjectionPlanner = Infrastructure.VitalDBRelationshipProjectionPlanner"
            ),
        ]

        for file in files {
            let infrastructureFile = sourcesRoot.appendingPathComponent(file.infrastructure)
            let legacyFile = sourcesRoot.appendingPathComponent(file.legacy)
            assertFileExists(infrastructureFile, "\(file.declaration) must live in Infrastructure")
            assertFileExists(legacyFile, "\(file.alias) shim must remain explicit while HostInfrastructure is transitional")

            let infrastructureContents = try String(contentsOf: infrastructureFile, encoding: .utf8)
            let legacyContents = try String(contentsOf: legacyFile, encoding: .utf8)
            XCTAssertTrue(infrastructureContents.contains(file.declaration), "\(file.infrastructure) must own the implementation")
            XCTAssertFalse(infrastructureContents.contains("import Core"), "\(file.infrastructure) must not import Core")
            XCTAssertFalse(infrastructureContents.contains("import HostInfrastructure"), "\(file.infrastructure) must not import HostInfrastructure")
            XCTAssertTrue(legacyContents.contains(file.alias), "\(file.legacy) must point to Infrastructure")
            XCTAssertFalse(legacyContents.contains(file.declaration), "\(file.legacy) must not retain implementation")
        }
    }

    func testHostCLIPackageReceiptReaderLivesInInfrastructureWithHostCLIAliasOnly() throws {
        let sourcesRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources")
        let infrastructureFile = sourcesRoot
            .appendingPathComponent("Infrastructure/PackageReceipts/RuntimePackageReceiptStateReader.swift")
        let hostCLIFile = sourcesRoot
            .appendingPathComponent("HostCLI/Runtime/RuntimePackageReceiptStateReader.swift")

        assertFileExists(infrastructureFile, "RuntimePackageReceiptStateReader must live in Infrastructure")
        assertFileExists(hostCLIFile, "RuntimePackageReceiptStateReader HostCLI shim must remain explicit")

        let infrastructureContents = try String(contentsOf: infrastructureFile, encoding: .utf8)
        let hostCLIContents = try String(contentsOf: hostCLIFile, encoding: .utf8)
        XCTAssertTrue(infrastructureContents.contains("public enum RuntimePackageReceiptStateReader"))
        XCTAssertFalse(infrastructureContents.contains("import Core"))
        XCTAssertFalse(infrastructureContents.contains("import HostCLI"))
        XCTAssertTrue(
            hostCLIContents.contains(
                "typealias RuntimePackageReceiptStateReader = Infrastructure.RuntimePackageReceiptStateReader"
            )
        )
        XCTAssertFalse(hostCLIContents.contains("enum RuntimePackageReceiptStateReader"))
    }

    func testHostCLIRuntimeStateStoresLiveInInfrastructureWithHostCLIAliasesOnly() throws {
        let sourcesRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources")
        let files: [(infrastructure: String, hostCLI: String, declaration: String, alias: String)] = [
            (
                "Infrastructure/Repositories/RuntimeInstallStateStore.swift",
                "HostCLI/Runtime/RuntimeInstallStateStore.swift",
                "public struct RuntimeInstallStateStore",
                "typealias RuntimeInstallStateStore = Infrastructure.RuntimeInstallStateStore"
            ),
            (
                "Infrastructure/Repositories/RuntimeUninstallStateStore.swift",
                "HostCLI/Runtime/RuntimeUninstallStateStore.swift",
                "public struct RuntimeUninstallStateStore",
                "typealias RuntimeUninstallStateStore = Infrastructure.RuntimeUninstallStateStore"
            ),
            (
                "Infrastructure/Repositories/RuntimeVersionStore.swift",
                "HostCLI/Runtime/RuntimeVersionStore.swift",
                "public struct RuntimeVersionStore",
                "typealias RuntimeVersionStore = Infrastructure.RuntimeVersionStore"
            ),
            (
                "Infrastructure/Repositories/RuntimeVersionStore.swift",
                "HostCLI/Runtime/RuntimeVersionStore.swift",
                "public struct RuntimeVersionStoreMetadata",
                "typealias RuntimeVersionStoreMetadata = Infrastructure.RuntimeVersionStoreMetadata"
            ),
            (
                "Infrastructure/Repositories/RuntimeVersionStore.swift",
                "HostCLI/Runtime/RuntimeVersionStore.swift",
                "public enum RuntimeVersionReadResult",
                "typealias RuntimeVersionReadResult = Infrastructure.RuntimeVersionReadResult"
            ),
            (
                "Infrastructure/Repositories/RuntimeBackupStore.swift",
                "HostCLI/Runtime/RuntimeBackupStore.swift",
                "public struct RuntimeBackupStore",
                "typealias RuntimeBackupStore = Infrastructure.RuntimeBackupStore"
            ),
            (
                "Infrastructure/Repositories/RuntimeBackupStore.swift",
                "HostCLI/Runtime/RuntimeBackupStore.swift",
                "public struct RuntimeBackupStorePaths",
                "typealias RuntimeBackupStorePaths = Infrastructure.RuntimeBackupStorePaths"
            ),
            (
                "Infrastructure/Repositories/RuntimeBackupStore.swift",
                "HostCLI/Runtime/RuntimeBackupStore.swift",
                "public struct RuntimeBackupStoreMetadata",
                "typealias RuntimeBackupStoreMetadata = Infrastructure.RuntimeBackupStoreMetadata"
            ),
            (
                "Infrastructure/Repositories/RuntimeBackupStore.swift",
                "HostCLI/Runtime/RuntimeBackupStore.swift",
                "public enum RuntimeBackupStoreError",
                "typealias RuntimeBackupStoreError = Infrastructure.RuntimeBackupStoreError"
            ),
            (
                "Infrastructure/Repositories/RuntimeBackupStore.swift",
                "HostCLI/Runtime/RuntimeBackupStore.swift",
                "public enum RuntimeManagedBackupArtifact",
                "typealias RuntimeManagedBackupArtifact = Infrastructure.RuntimeManagedBackupArtifact"
            ),
            (
                "Infrastructure/Repositories/RuntimeVMLifecycleStore.swift",
                "HostCLI/Runtime/RuntimeVMLifecycleStore.swift",
                "public struct RuntimeVMLifecycleStore",
                "typealias RuntimeVMLifecycleStore = Infrastructure.RuntimeVMLifecycleStore"
            ),
            (
                "Infrastructure/Repositories/RedisBackupResultReader.swift",
                "HostCLI/Runtime/RedisBackupResultReader.swift",
                "public enum RedisBackupResultReader",
                "typealias RedisBackupResultReader = Infrastructure.RedisBackupResultReader"
            ),
            (
                "Infrastructure/Health/RuntimeHealthChecker.swift",
                "HostCLI/Runtime/RuntimeHealthChecker.swift",
                "public struct RuntimeHealthCheckerContext",
                "typealias RuntimeHealthCheckerContext = Infrastructure.RuntimeHealthCheckerContext"
            ),
            (
                "Infrastructure/Health/RuntimeHealthChecker.swift",
                "HostCLI/Runtime/RuntimeHealthChecker.swift",
                "public struct RuntimeHealthChecker",
                "typealias RuntimeHealthChecker = Infrastructure.RuntimeHealthChecker"
            ),
        ]

        for file in files {
            let infrastructureFile = sourcesRoot.appendingPathComponent(file.infrastructure)
            let hostCLIFile = sourcesRoot.appendingPathComponent(file.hostCLI)
            assertFileExists(infrastructureFile, "\(file.declaration) must live in Infrastructure")
            assertFileExists(hostCLIFile, "\(file.alias) shim must remain explicit")

            let infrastructureContents = try String(contentsOf: infrastructureFile, encoding: .utf8)
            let hostCLIContents = try String(contentsOf: hostCLIFile, encoding: .utf8)
            XCTAssertTrue(infrastructureContents.contains(file.declaration))
            XCTAssertFalse(infrastructureContents.contains("import Core"))
            XCTAssertFalse(infrastructureContents.contains("import HostCLI"))
            XCTAssertFalse(infrastructureContents.contains("Constants."))
            XCTAssertTrue(hostCLIContents.contains(file.alias), "\(file.hostCLI) must point to Infrastructure")
            XCTAssertFalse(hostCLIContents.contains(file.declaration), "\(file.hostCLI) must not retain implementation")
        }
    }

    func testRuntimeRepositoryCompositionsLiveInBootstrapWithHostCLIAliasesOnly() throws {
        let sourcesRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources")
        let backupCompositionFile = sourcesRoot
            .appendingPathComponent("Bootstrap/Composition/RuntimeBackupStoreComposition.swift")
        let versionCompositionFile = sourcesRoot
            .appendingPathComponent("Bootstrap/Composition/RuntimeVersionStoreComposition.swift")
        let backupHostCLIShimFile = sourcesRoot
            .appendingPathComponent("HostCLI/Runtime/RuntimeBackupStoreComposition.swift")
        let versionHostCLIShimFile = sourcesRoot
            .appendingPathComponent("HostCLI/Runtime/RuntimeVersionStoreComposition.swift")
        let hostCLISupportFile = sourcesRoot
            .appendingPathComponent("HostCLI/Runtime/RuntimeLifecycle+Support.swift")

        assertFileExists(backupCompositionFile, "RuntimeBackupStoreComposition must live in Bootstrap")
        assertFileExists(versionCompositionFile, "RuntimeVersionStoreComposition must live in Bootstrap")
        assertFileExists(backupHostCLIShimFile, "RuntimeBackupStoreComposition HostCLI shim must remain explicit")
        assertFileExists(versionHostCLIShimFile, "RuntimeVersionStoreComposition HostCLI shim must remain explicit")

        let backupCompositionContents = try String(contentsOf: backupCompositionFile, encoding: .utf8)
        let versionCompositionContents = try String(contentsOf: versionCompositionFile, encoding: .utf8)
        let backupHostCLIShimContents = try String(contentsOf: backupHostCLIShimFile, encoding: .utf8)
        let versionHostCLIShimContents = try String(contentsOf: versionHostCLIShimFile, encoding: .utf8)
        let hostCLISupportContents = try String(contentsOf: hostCLISupportFile, encoding: .utf8)
        guard let backupStoreStart = hostCLISupportContents.range(of: "func backupStore"),
              let backupStoreEnd = hostCLISupportContents.range(
                  of: "func runtimeVersionStore",
                  range: backupStoreStart.upperBound..<hostCLISupportContents.endIndex
              ),
              let runtimeVersionStoreEnd = hostCLISupportContents.range(
                  of: "func writeRuntimeVersion",
                  range: backupStoreEnd.upperBound..<hostCLISupportContents.endIndex
              )
        else {
            XCTFail("HostCLI repository helpers must remain discoverable")
            return
        }
        let hostCLIBackupStoreContents = String(
            hostCLISupportContents[backupStoreStart.lowerBound..<backupStoreEnd.lowerBound]
        )
        let hostCLIRuntimeVersionStoreContents = String(
            hostCLISupportContents[backupStoreEnd.lowerBound..<runtimeVersionStoreEnd.lowerBound]
        )

        XCTAssertTrue(backupCompositionContents.contains("public struct RuntimeBackupStoreCompositionContext"))
        XCTAssertTrue(backupCompositionContents.contains("public struct RuntimeBackupStoreCompositionOperations"))
        XCTAssertTrue(backupCompositionContents.contains("public enum RuntimeBackupStoreComposition"))
        XCTAssertTrue(backupCompositionContents.contains("RuntimeBackupStore("))
        XCTAssertTrue(backupCompositionContents.contains("RuntimeBackupStorePaths("))
        XCTAssertTrue(backupCompositionContents.contains("RuntimeBackupStoreMetadata("))
        XCTAssertFalse(backupCompositionContents.contains("import HostCLI"))
        XCTAssertFalse(backupCompositionContents.contains("import Core"))
        XCTAssertFalse(backupCompositionContents.contains("import HostInfrastructure"))

        XCTAssertTrue(versionCompositionContents.contains("public struct RuntimeVersionStoreCompositionContext"))
        XCTAssertTrue(versionCompositionContents.contains("public struct RuntimeVersionStoreCompositionOperations"))
        XCTAssertTrue(versionCompositionContents.contains("public enum RuntimeVersionStoreComposition"))
        XCTAssertTrue(versionCompositionContents.contains("RuntimeVersionStore("))
        XCTAssertTrue(versionCompositionContents.contains("RuntimeVersionStoreMetadata("))
        XCTAssertFalse(versionCompositionContents.contains("import HostCLI"))
        XCTAssertFalse(versionCompositionContents.contains("import Core"))
        XCTAssertFalse(versionCompositionContents.contains("import HostInfrastructure"))

        XCTAssertTrue(
            backupHostCLIShimContents.contains(
                "typealias RuntimeBackupStoreCompositionContext = Bootstrap.RuntimeBackupStoreCompositionContext"
            )
        )
        XCTAssertTrue(
            backupHostCLIShimContents.contains(
                "typealias RuntimeBackupStoreCompositionOperations = Bootstrap.RuntimeBackupStoreCompositionOperations"
            )
        )
        XCTAssertTrue(
            backupHostCLIShimContents.contains(
                "typealias RuntimeBackupStoreComposition = Bootstrap.RuntimeBackupStoreComposition"
            )
        )
        XCTAssertFalse(backupHostCLIShimContents.contains("struct RuntimeBackupStoreComposition"))
        XCTAssertTrue(
            versionHostCLIShimContents.contains(
                "typealias RuntimeVersionStoreCompositionContext = Bootstrap.RuntimeVersionStoreCompositionContext"
            )
        )
        XCTAssertTrue(
            versionHostCLIShimContents.contains(
                "typealias RuntimeVersionStoreCompositionOperations = Bootstrap.RuntimeVersionStoreCompositionOperations"
            )
        )
        XCTAssertTrue(
            versionHostCLIShimContents.contains(
                "typealias RuntimeVersionStoreComposition = Bootstrap.RuntimeVersionStoreComposition"
            )
        )
        XCTAssertFalse(versionHostCLIShimContents.contains("struct RuntimeVersionStoreComposition"))

        XCTAssertTrue(hostCLIBackupStoreContents.contains("RuntimeBackupStoreComposition.make"))
        XCTAssertFalse(hostCLIBackupStoreContents.contains("RuntimeBackupStore("))
        XCTAssertFalse(hostCLIBackupStoreContents.contains("RuntimeBackupStorePaths("))
        XCTAssertFalse(hostCLIBackupStoreContents.contains("RuntimeBackupStoreMetadata("))
        XCTAssertFalse(hostCLIBackupStoreContents.contains("Constants.Artifacts"))
        XCTAssertTrue(hostCLIRuntimeVersionStoreContents.contains("RuntimeVersionStoreComposition.make"))
        XCTAssertFalse(hostCLIRuntimeVersionStoreContents.contains("RuntimeVersionStore("))
        XCTAssertFalse(hostCLIRuntimeVersionStoreContents.contains("RuntimeVersionStoreMetadata("))
        XCTAssertFalse(hostCLIRuntimeVersionStoreContents.contains("Constants.Artifacts"))
    }

    func testHostCLIFileSystemMaintenanceLivesInInfrastructureWithHostCLIAliasesOnly() throws {
        let sourcesRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources")
        let files: [(infrastructure: String, hostCLI: String, declaration: String, alias: String)] = [
            (
                "Infrastructure/FileSystem/RuntimeLogRotator.swift",
                "HostCLI/Runtime/RuntimeLogRotator.swift",
                "public struct RuntimeLogRotationConfiguration",
                "typealias RuntimeLogRotationConfiguration = Infrastructure.RuntimeLogRotationConfiguration"
            ),
            (
                "Infrastructure/FileSystem/RuntimeLogRotator.swift",
                "HostCLI/Runtime/RuntimeLogRotator.swift",
                "public struct RuntimeLogRotator",
                "typealias RuntimeLogRotator = Infrastructure.RuntimeLogRotator"
            ),
            (
                "Infrastructure/FileSystem/RuntimeStorageMaintenance.swift",
                "HostCLI/Runtime/RuntimeStorageMaintenance.swift",
                "public struct RuntimeStorageMaintenanceConfiguration",
                "typealias RuntimeStorageMaintenanceConfiguration = Infrastructure.RuntimeStorageMaintenanceConfiguration"
            ),
            (
                "Infrastructure/FileSystem/RuntimeStorageMaintenance.swift",
                "HostCLI/Runtime/RuntimeStorageMaintenance.swift",
                "public enum RuntimeStorageMaintenanceError",
                "typealias RuntimeStorageMaintenanceError = Infrastructure.RuntimeStorageMaintenanceError"
            ),
            (
                "Infrastructure/FileSystem/RuntimeStorageMaintenance.swift",
                "HostCLI/Runtime/RuntimeStorageMaintenance.swift",
                "public struct RuntimeStorageMaintenance",
                "typealias RuntimeStorageMaintenance = Infrastructure.RuntimeStorageMaintenance"
            ),
            (
                "Infrastructure/FileSystem/RuntimeGuestLogCollector.swift",
                "HostCLI/Runtime/RuntimeGuestLogCollector.swift",
                "public struct RuntimeGuestLogCollector",
                "typealias RuntimeGuestLogCollector = Infrastructure.RuntimeGuestLogCollector"
            ),
            (
                "Infrastructure/FileSystem/RuntimeGuestConfigWriter.swift",
                "HostCLI/Runtime/RuntimeGuestConfigWriter.swift",
                "public struct RuntimeGuestConfigWriter",
                "typealias RuntimeGuestConfigWriter = Infrastructure.RuntimeGuestConfigWriter"
            ),
            (
                "Infrastructure/FileSystem/RuntimeGuestConfigDocumentReader.swift",
                "HostCLI/Runtime/RuntimeDocuments.swift",
                "public enum RuntimeGuestConfigDocumentReadError",
                "typealias RuntimeGuestConfigDocumentReadError = Infrastructure.RuntimeGuestConfigDocumentReadError"
            ),
            (
                "Infrastructure/FileSystem/RuntimeGuestConfigDocumentReader.swift",
                "HostCLI/Runtime/RuntimeDocuments.swift",
                "public enum RuntimeGuestConfigDocumentReader",
                "typealias RuntimeGuestConfigDocumentReader = Infrastructure.RuntimeGuestConfigDocumentReader"
            ),
            (
                "Infrastructure/FileSystem/RuntimeFreshInstallStateReaders.swift",
                "HostCLI/Runtime/RuntimeFreshInstallPreflightRunner.swift",
                "public enum RuntimeInstallSettingsStateReader",
                "typealias RuntimeInstallSettingsStateReader = Infrastructure.RuntimeInstallSettingsStateReader"
            ),
            (
                "Infrastructure/FileSystem/RuntimeFreshInstallStateReaders.swift",
                "HostCLI/Runtime/RuntimeFreshInstallPreflightRunner.swift",
                "public enum RuntimeInstallArtifactStateReader",
                "typealias RuntimeInstallArtifactStateReader = Infrastructure.RuntimeInstallArtifactStateReader"
            ),
        ]

        for file in files {
            let infrastructureFile = sourcesRoot.appendingPathComponent(file.infrastructure)
            let hostCLIFile = sourcesRoot.appendingPathComponent(file.hostCLI)
            assertFileExists(infrastructureFile, "\(file.declaration) must live in Infrastructure")
            assertFileExists(hostCLIFile, "\(file.alias) HostCLI shim must remain explicit")

            let infrastructureContents = try String(contentsOf: infrastructureFile, encoding: .utf8)
            let hostCLIContents = try String(contentsOf: hostCLIFile, encoding: .utf8)
            XCTAssertFalse(infrastructureContents.contains("import Core"))
            XCTAssertFalse(infrastructureContents.contains("import HostCLI"))
            XCTAssertFalse(infrastructureContents.contains("LauncherError"))
            XCTAssertFalse(infrastructureContents.contains("Constants."))
            XCTAssertTrue(infrastructureContents.contains(file.declaration))
            XCTAssertTrue(hostCLIContents.contains(file.alias))
            XCTAssertFalse(hostCLIContents.contains(file.declaration), "HostCLI must not retain filesystem maintenance implementation")
        }
    }

    func testHostCLIInterfaceValuesLiveInInterfacesWithHostCLIAliasesOnly() throws {
        let sourcesRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources")
        let files: [(declaration: String, alias: String)] = [
            (
                "public enum Command",
                "typealias Command = Interfaces.Command"
            ),
            (
                "public enum LauncherError",
                "typealias LauncherError = Interfaces.LauncherError"
            ),
            (
                "public struct RuntimeConfigFlagValues",
                "typealias RuntimeConfigFlagValues = Interfaces.RuntimeConfigFlagValues"
            ),
            (
                "public struct RuntimeConfigFlagReader",
                "typealias RuntimeConfigFlagReader = Interfaces.RuntimeConfigFlagReader"
            ),
            (
                "public enum RuntimeInstallSettingsError",
                "typealias RuntimeInstallSettingsError = Interfaces.RuntimeInstallSettingsError"
            ),
            (
                "public struct RuntimeInstallSettingsDefaults",
                "typealias RuntimeInstallSettingsDefaults = Interfaces.RuntimeInstallSettingsDefaults"
            ),
            (
                "public struct RuntimeInstallSettings",
                "typealias InstallSettings = Interfaces.RuntimeInstallSettings"
            ),
            (
                "public enum RuntimeServiceControlCommand",
                "typealias RuntimeServiceControlCommand = Interfaces.RuntimeServiceControlCommand"
            ),
            (
                "public struct RuntimeConfigureCommand",
                "typealias RuntimeConfigureCommand = Interfaces.RuntimeConfigureCommand"
            ),
            (
                "public enum RuntimeConfigureChange",
                "typealias RuntimeConfigureChange = Interfaces.RuntimeConfigureChange"
            ),
            (
                "public enum RuntimeLifecycleCommand",
                "typealias RuntimeLifecycleCommand = Interfaces.RuntimeLifecycleCommand"
            ),
            (
                "public enum RuntimeLifecycleCommandParseError",
                "typealias RuntimeLifecycleCommandParseError = Interfaces.RuntimeLifecycleCommandParseError"
            ),
            (
                "public struct RuntimeStatusPrinter",
                "typealias RuntimeStatusPrinter = Interfaces.RuntimeStatusPrinter"
            ),
            (
                "public enum RuntimeHealthCheckRunnerError",
                "typealias RuntimeHealthCheckRunnerError = Interfaces.RuntimeHealthCheckRunnerError"
            ),
            (
                "public struct RuntimeHealthCheckRunner",
                "typealias RuntimeHealthCheckRunner = Interfaces.RuntimeHealthCheckRunner"
            ),
            (
                "public enum RuntimeHealthWaitRunnerError",
                "typealias RuntimeHealthWaitRunnerError = Interfaces.RuntimeHealthWaitRunnerError"
            ),
            (
                "public struct RuntimeHealthWaitRunner",
                "typealias RuntimeHealthWaitRunner = Interfaces.RuntimeHealthWaitRunner"
            ),
            (
                "public struct RuntimeServiceControlRunner",
                "typealias RuntimeServiceControlRunner = Interfaces.RuntimeServiceControlRunner"
            ),
        ]
        let interfaceFiles = [
            sourcesRoot.appendingPathComponent("Interfaces/HostCLI/Command.swift"),
            sourcesRoot.appendingPathComponent("Interfaces/HostCLI/LauncherError.swift"),
            sourcesRoot.appendingPathComponent("Interfaces/HostCLI/RuntimeConfigFlagReader.swift"),
            sourcesRoot.appendingPathComponent("Interfaces/HostCLI/RuntimeInstallSettings.swift"),
            sourcesRoot.appendingPathComponent("Interfaces/HostCLI/RuntimeServiceControlCommand.swift"),
            sourcesRoot.appendingPathComponent("Interfaces/HostCLI/RuntimeConfigureCommand.swift"),
            sourcesRoot.appendingPathComponent("Interfaces/HostCLI/RuntimeLifecycleCommand.swift"),
            sourcesRoot.appendingPathComponent("Interfaces/HostCLI/RuntimeStatusPrinter.swift"),
            sourcesRoot.appendingPathComponent("Interfaces/HostCLI/RuntimeHealthCheckRunner.swift"),
            sourcesRoot.appendingPathComponent("Interfaces/HostCLI/RuntimeHealthWaitRunner.swift"),
            sourcesRoot.appendingPathComponent("Interfaces/HostCLI/RuntimeServiceControlRunner.swift"),
        ]
        let hostCLIFiles = [
            sourcesRoot.appendingPathComponent("HostCLI/CLI/Command.swift"),
            sourcesRoot.appendingPathComponent("HostCLI/CLI/LauncherError.swift"),
            sourcesRoot.appendingPathComponent("HostCLI/Runtime/RuntimeConfigFlagReader.swift"),
            sourcesRoot.appendingPathComponent("HostCLI/Runtime/InstallSettings.swift"),
            sourcesRoot.appendingPathComponent("HostCLI/Runtime/RuntimeServiceControlCommand.swift"),
            sourcesRoot.appendingPathComponent("HostCLI/Runtime/RuntimeConfigureCommand.swift"),
            sourcesRoot.appendingPathComponent("HostCLI/Runtime/RuntimeLifecycleCommand.swift"),
            sourcesRoot.appendingPathComponent("HostCLI/Runtime/RuntimeStatusPrinter.swift"),
            sourcesRoot.appendingPathComponent("HostCLI/Runtime/RuntimeHealthCheckRunner.swift"),
            sourcesRoot.appendingPathComponent("HostCLI/Runtime/RuntimeHealthWaitRunner.swift"),
            sourcesRoot.appendingPathComponent("HostCLI/Runtime/RuntimeServiceControlRunner.swift"),
        ]

        for interfaceFile in interfaceFiles {
            assertFileExists(interfaceFile, "\(interfaceFile.lastPathComponent) must live in Interfaces/HostCLI")
            let contents = try String(contentsOf: interfaceFile, encoding: .utf8)
            XCTAssertFalse(contents.contains("import HostCLI"))
            XCTAssertFalse(contents.contains("VMRuntimeConfig"))
            XCTAssertFalse(contents.contains("Constants."))
            if interfaceFile.lastPathComponent != "LauncherError.swift" {
                XCTAssertFalse(contents.contains("LauncherError"))
            }
        }
        for hostCLIFile in hostCLIFiles {
            assertFileExists(hostCLIFile, "\(hostCLIFile.lastPathComponent) HostCLI shim must remain explicit")
        }

        let interfacesContents = try interfaceFiles
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")
        let hostCLIContents = try hostCLIFiles
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")

        for file in files {
            XCTAssertTrue(interfacesContents.contains(file.declaration))
            XCTAssertTrue(hostCLIContents.contains(file.alias))
            XCTAssertFalse(hostCLIContents.contains(file.declaration), "HostCLI must not retain interface value implementation")
        }
        XCTAssertTrue(hostCLIContents.contains("typealias NetworkMode = Contracts.RuntimeNetworkMode"))
    }

    func testRuntimeHealthWaitRunnerCompositionLivesInBootstrapWithHostCLIAliasesOnly() throws {
        let sourcesRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources")
        let bootstrapFile = sourcesRoot
            .appendingPathComponent("Bootstrap/Composition/RuntimeHealthWaitRunnerComposition.swift")
        let hostCLIShimFile = sourcesRoot
            .appendingPathComponent("HostCLI/Runtime/RuntimeHealthWaitRunnerComposition.swift")
        let hostCLISupportFile = sourcesRoot
            .appendingPathComponent("HostCLI/Runtime/RuntimeLifecycle+Support.swift")

        assertFileExists(bootstrapFile, "RuntimeHealthWaitRunnerComposition must live in Bootstrap")
        assertFileExists(hostCLIShimFile, "RuntimeHealthWaitRunnerComposition HostCLI shim must remain explicit")

        let bootstrapContents = try String(contentsOf: bootstrapFile, encoding: .utf8)
        let hostCLIShimContents = try String(contentsOf: hostCLIShimFile, encoding: .utf8)
        let hostCLISupportContents = try String(contentsOf: hostCLISupportFile, encoding: .utf8)
        guard let healthWaitStart = hostCLISupportContents.range(of: "func runtimeHealthWaitRunner"),
              let healthWaitEnd = hostCLISupportContents.range(
                  of: "func runtimeUninstallRunner",
                  range: healthWaitStart.upperBound..<hostCLISupportContents.endIndex
              )
        else {
            XCTFail("HostCLI health-wait runner helper must remain discoverable")
            return
        }
        let hostCLIHealthWaitContents = String(
            hostCLISupportContents[healthWaitStart.lowerBound..<healthWaitEnd.lowerBound]
        )

        XCTAssertTrue(bootstrapContents.contains("public struct RuntimeHealthWaitRunnerCompositionOperations"))
        XCTAssertTrue(bootstrapContents.contains("public enum RuntimeHealthWaitRunnerComposition"))
        XCTAssertTrue(bootstrapContents.contains("RuntimeHealthWaitRunner("))
        XCTAssertTrue(bootstrapContents.contains("RuntimeHealthWaitWorkflowConfiguration("))
        XCTAssertTrue(bootstrapContents.contains("writeRuntimeStatusBestEffort("))
        XCTAssertFalse(bootstrapContents.contains("import HostCLI"))
        XCTAssertFalse(bootstrapContents.contains("import Core"))
        XCTAssertFalse(bootstrapContents.contains("import HostInfrastructure"))
        XCTAssertTrue(
            hostCLIShimContents.contains(
                "typealias RuntimeHealthWaitRunnerCompositionOperations = Bootstrap.RuntimeHealthWaitRunnerCompositionOperations"
            )
        )
        XCTAssertTrue(
            hostCLIShimContents.contains(
                "typealias RuntimeHealthWaitRunnerComposition = Bootstrap.RuntimeHealthWaitRunnerComposition"
            )
        )
        XCTAssertFalse(hostCLIShimContents.contains("enum RuntimeHealthWaitRunnerComposition"))
        XCTAssertTrue(hostCLIHealthWaitContents.contains("RuntimeHealthWaitRunnerComposition.make"))
        XCTAssertFalse(hostCLIHealthWaitContents.contains("RuntimeHealthWaitRunner("))
        XCTAssertFalse(hostCLIHealthWaitContents.contains("RuntimeHealthWaitWorkflowConfiguration("))
        XCTAssertFalse(hostCLIHealthWaitContents.contains("writeRuntimeStatusBestEffort("))
    }

    func testRuntimeControlAPIImplementationsLiveInInterfacesWithRuntimeControlAPIAliasesOnly() throws {
        let sourcesRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources")
        let files: [(interfaces: String, declaration: String, alias: String)] = [
            (
                "Interfaces/RuntimeControlAPI/Boundary/RuntimeControlAPI.swift",
                "public enum RuntimeControlAPIEndpoint",
                "public typealias RuntimeControlAPIEndpoint = Interfaces.RuntimeControlAPIEndpoint"
            ),
            (
                "Interfaces/RuntimeControlAPI/Boundary/RuntimeControlHTTPBoundary.swift",
                "public struct RuntimeControlAPIRouter",
                "public typealias RuntimeControlAPIRouter = Interfaces.RuntimeControlAPIRouter"
            ),
            (
                "Interfaces/RuntimeControlAPI/Transport/RuntimeControlLocalHTTPServer.swift",
                "public final class RuntimeControlLocalHTTPServer",
                "public typealias RuntimeControlLocalHTTPServer = Interfaces.RuntimeControlLocalHTTPServer"
            ),
            (
                "Interfaces/RuntimeControlAPI/Testing/RuntimeTestKitAPIRouter.swift",
                "public struct RuntimeTestKitAPIRouter",
                "public typealias RuntimeTestKitAPIRouter = Interfaces.RuntimeTestKitAPIRouter"
            ),
        ]
        let legacyCompatibility = sourcesRoot.appendingPathComponent("RuntimeControlAPI/RuntimeControlAPICompatibility.swift")

        assertFileExists(legacyCompatibility, "RuntimeControlAPI compatibility aliases must remain explicit")
        let legacyContents = try String(contentsOf: legacyCompatibility, encoding: .utf8)

        for file in files {
            let interfacesFile = sourcesRoot.appendingPathComponent(file.interfaces)
            assertFileExists(interfacesFile, "\(file.declaration) must live in Interfaces")

            let interfacesContents = try String(contentsOf: interfacesFile, encoding: .utf8)
            XCTAssertTrue(interfacesContents.contains(file.declaration), "\(file.interfaces) must own the implementation")
            XCTAssertFalse(interfacesContents.contains("import RuntimeControlAPI"), "\(file.interfaces) must not import RuntimeControlAPI")
            XCTAssertTrue(legacyContents.contains(file.alias), "RuntimeControlAPI compatibility file must point to Interfaces")
            XCTAssertFalse(legacyContents.contains(file.declaration), "RuntimeControlAPI target must not retain implementation")
        }

        let legacySwiftFiles = try swiftFiles(in: sourcesRoot.appendingPathComponent("RuntimeControlAPI"))
        XCTAssertEqual(
            legacySwiftFiles.map(\.lastPathComponent),
            ["RuntimeControlAPICompatibility.swift"],
            "RuntimeControlAPI target must contain only the compatibility surface"
        )
    }

    func testConcreteHostAdaptersLiveInHostAdaptersWithHostCLIAliasesOnly() throws {
        let sourcesRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources")
        let files: [(adapter: String, legacy: String, declaration: String, alias: String)] = [
            (
                "HostAdapters/Process/SystemRuntimeCommandRunner.swift",
                "HostCLI/Runtime/SystemRuntimeCommandRunner.swift",
                "public struct SystemRuntimeCommandRunner",
                "typealias SystemRuntimeCommandRunner = HostAdapters.SystemRuntimeCommandRunner"
            ),
            (
                "HostAdapters/Process/CurlRuntimeHTTPProber.swift",
                "HostCLI/Runtime/CurlRuntimeHTTPProber.swift",
                "public struct CurlRuntimeHTTPProber",
                "typealias CurlRuntimeHTTPProber = HostAdapters.CurlRuntimeHTTPProber"
            ),
            (
                "HostAdapters/Launchd/LaunchdRuntimeServiceManager.swift",
                "HostCLI/Runtime/LaunchdRuntimeServiceManager.swift",
                "public struct LaunchdRuntimeServiceManager",
                "typealias LaunchdRuntimeServiceManager = HostAdapters.LaunchdRuntimeServiceManager"
            ),
            (
                "HostAdapters/Launchd/RuntimeServiceController.swift",
                "HostCLI/Runtime/RuntimeServiceController.swift",
                "public enum RuntimeServiceControllerError",
                "typealias RuntimeServiceControllerError = HostAdapters.RuntimeServiceControllerError"
            ),
            (
                "HostAdapters/Launchd/RuntimeServiceController.swift",
                "HostCLI/Runtime/RuntimeServiceController.swift",
                "public struct RuntimeServiceController",
                "typealias RuntimeServiceController = HostAdapters.RuntimeServiceController"
            ),
            (
                "HostAdapters/Process/SystemRuntimeTiming.swift",
                "HostCLI/Runtime/SystemRuntimeTiming.swift",
                "public struct SystemRuntimeClock",
                "typealias SystemRuntimeClock = HostAdapters.SystemRuntimeClock"
            ),
            (
                "HostAdapters/Process/ProcessState.swift",
                "HostCLI/Runtime/ProcessState.swift",
                "public enum ProcessStateError",
                "typealias ProcessStateError = HostAdapters.ProcessStateError"
            ),
            (
                "HostAdapters/Process/ProcessState.swift",
                "HostCLI/Runtime/ProcessState.swift",
                "public enum ProcessState",
                "typealias ProcessState = HostAdapters.ProcessState"
            ),
            (
                "Contracts/RuntimeProxyNginxPIDReadResult.swift",
                "HostCLI/Runtime/RuntimeHostProxyPortCleaner.swift",
                "public enum RuntimeProxyNginxPIDReadResult",
                "typealias RuntimeProxyNginxPIDReadResult = HostAdapters.RuntimeProxyNginxPIDReadResult"
            ),
            (
                "HostAdapters/Process/RuntimeHostProxyPortCleaner.swift",
                "HostCLI/Runtime/RuntimeHostProxyPortCleaner.swift",
                "public enum RuntimeHostProxyPortCleanerError",
                "typealias RuntimeHostProxyPortCleanerError = HostAdapters.RuntimeHostProxyPortCleanerError"
            ),
            (
                "HostAdapters/Process/RuntimeHostProxyPortCleaner.swift",
                "HostCLI/Runtime/RuntimeHostProxyPortCleaner.swift",
                "public struct RuntimeHostProxyPortCleaner",
                "typealias RuntimeHostProxyPortCleaner = HostAdapters.RuntimeHostProxyPortCleaner"
            ),
            (
                "HostAdapters/Process/RuntimeHostProxyPortStateReader.swift",
                "HostCLI/Runtime/RuntimeFreshInstallPreflightRunner.swift",
                "public enum RuntimeHostProxyPortStateReader",
                "typealias RuntimeHostProxyPortStateReader = HostAdapters.RuntimeHostProxyPortStateReader"
            ),
            (
                "HostAdapters/VirtualMachine/VMRuntimeConfig.swift",
                "HostCLI/VirtualMachine/VMRuntimeConfig.swift",
                "public enum VMRuntimeConfigReadError",
                "typealias VMRuntimeConfigReadError = HostAdapters.VMRuntimeConfigReadError"
            ),
            (
                "HostAdapters/VirtualMachine/VMRuntimeConfig.swift",
                "HostCLI/VirtualMachine/VMRuntimeConfig.swift",
                "public enum VMRuntimeBootFileValidationError",
                "typealias VMRuntimeBootFileValidationError = HostAdapters.VMRuntimeBootFileValidationError"
            ),
            (
                "HostAdapters/VirtualMachine/VMRuntimeConfig.swift",
                "HostCLI/VirtualMachine/VMRuntimeConfig.swift",
                "public struct VMRuntimeConfig",
                "typealias VMRuntimeConfig = HostAdapters.VMRuntimeConfig"
            ),
            (
                "HostAdapters/VirtualMachine/VMRuntimeConfig.swift",
                "HostCLI/VirtualMachine/VMRuntimeConfig.swift",
                "public struct NetworkConfig",
                "typealias NetworkConfig = HostAdapters.NetworkConfig"
            ),
            (
                "HostAdapters/VirtualMachine/VMRuntimeConfig.swift",
                "HostCLI/VirtualMachine/VMRuntimeConfig.swift",
                "public struct SharedDirectoryConfig",
                "typealias SharedDirectoryConfig = HostAdapters.SharedDirectoryConfig"
            ),
            (
                "HostAdapters/VirtualMachine/VMConfigurationFactory.swift",
                "HostCLI/VirtualMachine/VMConfigurationFactory.swift",
                "public enum VMConfigurationFactoryError",
                "typealias VMConfigurationFactoryError = HostAdapters.VMConfigurationFactoryError"
            ),
            (
                "HostAdapters/VirtualMachine/VMConfigurationFactory.swift",
                "HostCLI/VirtualMachine/VMConfigurationFactory.swift",
                "public final class VMConfigurationFactory",
                "typealias VMConfigurationFactory = HostAdapters.VMConfigurationFactory"
            ),
            (
                "HostAdapters/VirtualMachine/VirtualMachineDelegate.swift",
                "HostCLI/VirtualMachine/VirtualMachineDelegate.swift",
                "public final class VirtualMachineDelegate",
                "typealias VirtualMachineDelegate = HostAdapters.VirtualMachineDelegate"
            ),
            (
                "HostAdapters/VirtualMachine/VirtualMachineTerminationHandler.swift",
                "HostCLI/VirtualMachine/VirtualMachineTerminationHandler.swift",
                "public final class VirtualMachineTerminationHandler",
                "typealias VirtualMachineTerminationHandler = HostAdapters.VirtualMachineTerminationHandler"
            ),
        ]

        for file in files {
            let adapterFile = sourcesRoot.appendingPathComponent(file.adapter)
            let legacyFile = sourcesRoot.appendingPathComponent(file.legacy)
            assertFileExists(adapterFile, "\(file.declaration) must live in HostAdapters")
            assertFileExists(legacyFile, "\(file.alias) shim must remain explicit while HostCLI is transitional")

            let adapterContents = try String(contentsOf: adapterFile, encoding: .utf8)
            let legacyContents = try String(contentsOf: legacyFile, encoding: .utf8)
            XCTAssertTrue(adapterContents.contains(file.declaration), "\(file.adapter) must own the implementation")
            XCTAssertFalse(adapterContents.contains("import HostCLI"), "\(file.adapter) must not import HostCLI")
            XCTAssertFalse(adapterContents.contains("import Core"), "\(file.adapter) must not import Core")
            XCTAssertFalse(adapterContents.contains("import HostInfrastructure"), "\(file.adapter) must not import HostInfrastructure")
            XCTAssertFalse(adapterContents.contains("LauncherError"), "\(file.adapter) must not throw HostCLI LauncherError")
            XCTAssertTrue(legacyContents.contains(file.alias), "\(file.legacy) must point to HostAdapters")
            XCTAssertFalse(legacyContents.contains(file.declaration), "\(file.legacy) must not retain implementation")
        }
    }

    func testMacRuntimeControlAppReadModelPoliciesLiveInInterfacesWithAppAliasesOnly() throws {
        let sourcesRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources")
        let files: [(interfaces: String, app: String, declaration: String, alias: String)] = [
            (
                "Interfaces/MacRuntimeControlApp/RuntimeControlStatusAnnotator.swift",
                "MacRuntimeControlApp/Composition/RuntimeControlStatusAnnotator.swift",
                "public struct RuntimeControlStatusAnnotator",
                "typealias RuntimeControlStatusAnnotator = Interfaces.RuntimeControlStatusAnnotator"
            ),
            (
                "Interfaces/MacRuntimeControlApp/RuntimeActiveOperationPolicy.swift",
                "MacRuntimeControlApp/Presentation/Policies/RuntimeActiveOperationPolicy.swift",
                "public struct RuntimeActiveOperationPolicy",
                "typealias RuntimeActiveOperationPolicy = Interfaces.RuntimeActiveOperationPolicy"
            ),
            (
                "Interfaces/MacRuntimeControlApp/RuntimeBackupSelectionPolicy.swift",
                "MacRuntimeControlApp/Presentation/Policies/RuntimeBackupSelectionPolicy.swift",
                "public struct RuntimeBackupSelectionPolicy",
                "typealias RuntimeBackupSelectionPolicy = Interfaces.RuntimeBackupSelectionPolicy"
            ),
            (
                "Interfaces/MacRuntimeControlApp/RuntimeViewModelBackupActionPlanner.swift",
                "MacRuntimeControlApp/Presentation/ViewModels/RuntimeViewModelBackupActionPlanner.swift",
                "public struct RuntimeViewModelBackupActionPlan",
                "typealias RuntimeViewModelBackupActionPlan = Interfaces.RuntimeViewModelBackupActionPlan"
            ),
            (
                "Interfaces/MacRuntimeControlApp/RuntimeViewModelBackupActionPlanner.swift",
                "MacRuntimeControlApp/Presentation/ViewModels/RuntimeViewModelBackupActionPlanner.swift",
                "public enum RuntimeViewModelBackupActionPlanFailure",
                "typealias RuntimeViewModelBackupActionPlanFailure = Interfaces.RuntimeViewModelBackupActionPlanFailure"
            ),
            (
                "Interfaces/MacRuntimeControlApp/RuntimeViewModelBackupActionPlanner.swift",
                "MacRuntimeControlApp/Presentation/ViewModels/RuntimeViewModelBackupActionPlanner.swift",
                "public struct RuntimeViewModelBackupActionPlanner",
                "typealias RuntimeViewModelBackupActionPlanner = Interfaces.RuntimeViewModelBackupActionPlanner"
            ),
            (
                "Interfaces/MacRuntimeControlApp/RuntimeViewModelTestKitStatePolicy.swift",
                "MacRuntimeControlApp/Presentation/ViewModels/RuntimeViewModelTestKitStatePolicy.swift",
                "public struct RuntimeViewModelTestKitStartInput",
                "typealias RuntimeViewModelTestKitStartInput = Interfaces.RuntimeViewModelTestKitStartInput"
            ),
            (
                "Interfaces/MacRuntimeControlApp/RuntimeViewModelTestKitStatePolicy.swift",
                "MacRuntimeControlApp/Presentation/ViewModels/RuntimeViewModelTestKitStatePolicy.swift",
                "public struct RuntimeViewModelTestKitStatePolicy",
                "typealias RuntimeViewModelTestKitStatePolicy = Interfaces.RuntimeViewModelTestKitStatePolicy"
            ),
            (
                "Interfaces/MacRuntimeControlApp/RuntimeViewModelObservabilityRefresher.swift",
                "MacRuntimeControlApp/Presentation/ViewModels/RuntimeViewModelObservabilityRefresher.swift",
                "public protocol RuntimeViewModelObservabilitySnapshotLoading",
                "typealias RuntimeViewModelObservabilitySnapshotLoading = Interfaces.RuntimeViewModelObservabilitySnapshotLoading"
            ),
            (
                "Interfaces/MacRuntimeControlApp/RuntimeViewModelObservabilityRefresher.swift",
                "MacRuntimeControlApp/Presentation/ViewModels/RuntimeViewModelObservabilityRefresher.swift",
                "public struct RuntimeViewModelRuntimeEventRefreshResult",
                "typealias RuntimeViewModelRuntimeEventRefreshResult = Interfaces.RuntimeViewModelRuntimeEventRefreshResult"
            ),
            (
                "Interfaces/MacRuntimeControlApp/RuntimeViewModelObservabilityRefresher.swift",
                "MacRuntimeControlApp/Presentation/ViewModels/RuntimeViewModelObservabilityRefresher.swift",
                "public struct RuntimeViewModelVitalObservabilityRefreshResult",
                "typealias RuntimeViewModelVitalObservabilityRefreshResult = Interfaces.RuntimeViewModelVitalObservabilityRefreshResult"
            ),
            (
                "Interfaces/MacRuntimeControlApp/RuntimeViewModelObservabilityRefresher.swift",
                "MacRuntimeControlApp/Presentation/ViewModels/RuntimeViewModelObservabilityRefresher.swift",
                "public struct RuntimeViewModelObservabilityRefresher",
                "typealias RuntimeViewModelObservabilityRefresher = Interfaces.RuntimeViewModelObservabilityRefresher"
            ),
            (
                "Interfaces/MacRuntimeControlApp/RuntimeEventPeriodOption.swift",
                "MacRuntimeControlApp/Presentation/ViewModels/RuntimeEventPeriodOption.swift",
                "public enum RuntimeEventPeriodOption",
                "typealias RuntimeEventPeriodOption = Interfaces.RuntimeEventPeriodOption"
            ),
            (
                "Interfaces/MacRuntimeControlApp/RuntimeRecorderActivityChartDataBuilder.swift",
                "MacRuntimeControlApp/Presentation/Views/RuntimeRecorderActivityChartDataBuilder.swift",
                "public struct RuntimeRecorderActivityChartDataBuilder",
                "typealias RuntimeRecorderActivityChartDataBuilder = Interfaces.RuntimeRecorderActivityChartDataBuilder"
            ),
            (
                "Interfaces/MacRuntimeControlApp/RuntimeRecorderActivityChartDataBuilder.swift",
                "MacRuntimeControlApp/Presentation/Views/RuntimeRecorderActivityChartDataBuilder.swift",
                "public struct RuntimeRecorderActivityDisplay",
                "typealias RuntimeRecorderActivityDisplay = Interfaces.RuntimeRecorderActivityDisplay"
            ),
            (
                "Interfaces/MacRuntimeControlApp/RuntimeRecorderActivityChartDataBuilder.swift",
                "MacRuntimeControlApp/Presentation/Views/RuntimeRecorderActivityChartDataBuilder.swift",
                "public enum RuntimeRecorderActivityDisplayState",
                "typealias RuntimeRecorderActivityDisplayState = Interfaces.RuntimeRecorderActivityDisplayState"
            ),
            (
                "Interfaces/MacRuntimeControlApp/RuntimeRecorderActivityChartDataBuilder.swift",
                "MacRuntimeControlApp/Presentation/Views/RuntimeRecorderActivityChartDataBuilder.swift",
                "public enum RecorderActivityBucketInterval",
                "typealias RecorderActivityBucketInterval = Interfaces.RecorderActivityBucketInterval"
            ),
            (
                "Interfaces/MacRuntimeControlApp/RuntimeRecorderActivityChartDataBuilder.swift",
                "MacRuntimeControlApp/Presentation/Views/RuntimeRecorderActivityChartDataBuilder.swift",
                "public enum RecorderActivityPeriod",
                "typealias RecorderActivityPeriod = Interfaces.RecorderActivityPeriod"
            ),
            (
                "Interfaces/MacRuntimeControlApp/RuntimeRecorderActivityChartDataBuilder.swift",
                "MacRuntimeControlApp/Presentation/Views/RuntimeRecorderActivityChartDataBuilder.swift",
                "public struct RecorderActivityChartBucket",
                "typealias RecorderActivityChartBucket = Interfaces.RecorderActivityChartBucket"
            ),
            (
                "Interfaces/MacRuntimeControlApp/RuntimeRecorderActivityChartDataBuilder.swift",
                "MacRuntimeControlApp/Presentation/Views/RuntimeRecorderActivityChartDataBuilder.swift",
                "public struct RecorderActivityChartBucketBuilder",
                "typealias RecorderActivityChartBucketBuilder = Interfaces.RecorderActivityChartBucketBuilder"
            ),
            (
                "Interfaces/MacRuntimeControlApp/RuntimeRecorderActivityChartDataBuilder.swift",
                "MacRuntimeControlApp/Presentation/Views/RuntimeRecorderActivityChartDataBuilder.swift",
                "public enum RuntimeRecorderActivityDateParser",
                "typealias RuntimeRecorderActivityDateParser = Interfaces.RuntimeRecorderActivityDateParser"
            ),
            (
                "Interfaces/MacRuntimeControlApp/RuntimeViewModelStatusRefresher.swift",
                "MacRuntimeControlApp/Presentation/ViewModels/RuntimeViewModelStatusRefresher.swift",
                "public protocol RuntimeViewModelStatusSnapshotLoading",
                "typealias RuntimeViewModelStatusSnapshotLoading = Interfaces.RuntimeViewModelStatusSnapshotLoading"
            ),
            (
                "Interfaces/MacRuntimeControlApp/RuntimeViewModelStatusRefresher.swift",
                "MacRuntimeControlApp/Presentation/ViewModels/RuntimeViewModelStatusRefresher.swift",
                "public protocol RuntimeViewModelStatusPresentationFormatting",
                "typealias RuntimeViewModelStatusPresentationFormatting = Interfaces.RuntimeViewModelStatusPresentationFormatting"
            ),
            (
                "Interfaces/MacRuntimeControlApp/RuntimeViewModelStatusRefresher.swift",
                "MacRuntimeControlApp/Presentation/ViewModels/RuntimeViewModelStatusRefresher.swift",
                "public struct RuntimeViewModelStatusRefreshResult",
                "typealias RuntimeViewModelStatusRefreshResult = Interfaces.RuntimeViewModelStatusRefreshResult"
            ),
            (
                "Interfaces/MacRuntimeControlApp/RuntimeViewModelStatusRefresher.swift",
                "MacRuntimeControlApp/Presentation/ViewModels/RuntimeViewModelStatusRefresher.swift",
                "public struct RuntimeViewModelStatusRefresher",
                "typealias RuntimeViewModelStatusRefresher = Interfaces.RuntimeViewModelStatusRefresher"
            ),
            (
                "Interfaces/MacRuntimeControlApp/RuntimeHealthNotificationState.swift",
                "MacRuntimeControlApp/Presentation/ViewModels/RuntimeHealthNotificationCoordinator.swift",
                "public enum RuntimeHealthNotificationState",
                "typealias RuntimeHealthNotificationState = Interfaces.RuntimeHealthNotificationState"
            ),
            (
                "Interfaces/MacRuntimeControlApp/RuntimeEventDisplayPolicy.swift",
                "MacRuntimeControlApp/Presentation/Policies/RuntimeEventDisplayPolicy.swift",
                "public protocol RuntimeEventDisplayVocabulary",
                "typealias RuntimeEventDisplayVocabulary = Interfaces.RuntimeEventDisplayVocabulary"
            ),
            (
                "Interfaces/MacRuntimeControlApp/RuntimeEventDisplayPolicy.swift",
                "MacRuntimeControlApp/Presentation/Policies/RuntimeEventDisplayPolicy.swift",
                "public struct RuntimeEventDisplayPolicy",
                "typealias RuntimeEventDisplayPolicy = Interfaces.RuntimeEventDisplayPolicy"
            ),
            (
                "Interfaces/MacRuntimeControlApp/RuntimeStatusUptimeFormatter.swift",
                "MacRuntimeControlApp/Presentation/Policies/RuntimeStatusDisplayPolicy.swift",
                "public struct RuntimeStatusUptimeFormatter",
                "RuntimeStatusVitalServerAvailabilityPolicy("
            ),
            (
                "Interfaces/MacRuntimeControlApp/RuntimeStatusReachabilityPolicy.swift",
                "MacRuntimeControlApp/Presentation/Policies/RuntimeStatusDisplayPolicy.swift",
                "public struct RuntimeStatusReachabilityPolicy",
                "RuntimeStatusVitalServerAvailabilityPolicy("
            ),
            (
                "Interfaces/MacRuntimeControlApp/RuntimeStatusRemoteConsoleAvailabilityPolicy.swift",
                "MacRuntimeControlApp/Presentation/Policies/RuntimeStatusDisplayPolicy.swift",
                "public protocol RuntimeStatusRemoteConsoleAvailabilityVocabulary",
                "AppRuntimeStatusRemoteConsoleAvailabilityVocabulary: RuntimeStatusRemoteConsoleAvailabilityVocabulary"
            ),
            (
                "Interfaces/MacRuntimeControlApp/RuntimeStatusRemoteConsoleAvailabilityPolicy.swift",
                "MacRuntimeControlApp/Presentation/Policies/RuntimeStatusDisplayPolicy.swift",
                "public struct RuntimeStatusRemoteConsoleAvailabilityValue",
                "RuntimeStatusRemoteConsoleAvailabilityValue"
            ),
            (
                "Interfaces/MacRuntimeControlApp/RuntimeStatusRemoteConsoleAvailabilityPolicy.swift",
                "MacRuntimeControlApp/Presentation/Policies/RuntimeStatusDisplayPolicy.swift",
                "public struct RuntimeStatusRemoteConsoleAvailabilityPolicy",
                "RuntimeStatusRemoteConsoleAvailabilityPolicy("
            ),
            (
                "Interfaces/MacRuntimeControlApp/RuntimeStatusVMStatePolicy.swift",
                "MacRuntimeControlApp/Presentation/Policies/RuntimeStatusDisplayPolicy.swift",
                "public protocol RuntimeStatusVMStateVocabulary",
                "AppRuntimeStatusVMStateVocabulary: RuntimeStatusVMStateVocabulary"
            ),
            (
                "Interfaces/MacRuntimeControlApp/RuntimeStatusVMStatePolicy.swift",
                "MacRuntimeControlApp/Presentation/Policies/RuntimeStatusDisplayPolicy.swift",
                "public struct RuntimeStatusVMStateValue",
                "RuntimeStatusVMStateValue"
            ),
            (
                "Interfaces/MacRuntimeControlApp/RuntimeStatusVMStatePolicy.swift",
                "MacRuntimeControlApp/Presentation/Policies/RuntimeStatusDisplayPolicy.swift",
                "public struct RuntimeStatusVMStatePolicy",
                "RuntimeStatusVMStatePolicy("
            ),
            (
                "Interfaces/MacRuntimeControlApp/RuntimeStatusOverallHealthPolicy.swift",
                "MacRuntimeControlApp/Presentation/Policies/RuntimeStatusDisplayPolicy.swift",
                "public protocol RuntimeStatusOverallHealthVocabulary",
                "AppRuntimeStatusOverallHealthVocabulary: RuntimeStatusOverallHealthVocabulary"
            ),
            (
                "Interfaces/MacRuntimeControlApp/RuntimeStatusOverallHealthPolicy.swift",
                "MacRuntimeControlApp/Presentation/Policies/RuntimeStatusDisplayPolicy.swift",
                "public struct RuntimeStatusOverallHealthValue",
                "RuntimeStatusOverallHealthValue"
            ),
            (
                "Interfaces/MacRuntimeControlApp/RuntimeStatusOverallHealthPolicy.swift",
                "MacRuntimeControlApp/Presentation/Policies/RuntimeStatusDisplayPolicy.swift",
                "public struct RuntimeStatusOverallHealthPolicy",
                "RuntimeStatusOverallHealthPolicy("
            ),
            (
                "Interfaces/MacRuntimeControlApp/RuntimeStatusReachabilityLabelPolicy.swift",
                "MacRuntimeControlApp/Presentation/Policies/RuntimeStatusDisplayPolicy.swift",
                "public protocol RuntimeStatusReachabilityLabelVocabulary",
                "RuntimeStatusVitalServerAvailabilityVocabulary"
            ),
            (
                "Interfaces/MacRuntimeControlApp/RuntimeStatusReachabilityLabelPolicy.swift",
                "MacRuntimeControlApp/Presentation/Policies/RuntimeStatusDisplayPolicy.swift",
                "public struct RuntimeStatusReachabilityLabelPolicy",
                "RuntimeStatusVitalServerAvailabilityPolicy("
            ),
            (
                "Interfaces/MacRuntimeControlApp/RuntimeStatusServiceValuePolicy.swift",
                "MacRuntimeControlApp/Presentation/Policies/RuntimeStatusDisplayPolicy.swift",
                "public protocol RuntimeStatusServiceValueVocabulary",
                "RuntimeStatusAdvancedServiceHealthVocabulary"
            ),
            (
                "Interfaces/MacRuntimeControlApp/RuntimeStatusServiceValuePolicy.swift",
                "MacRuntimeControlApp/Presentation/Policies/RuntimeStatusDisplayPolicy.swift",
                "public struct RuntimeStatusServiceValue",
                "RuntimeStatusAdvancedServiceHealthValue"
            ),
            (
                "Interfaces/MacRuntimeControlApp/RuntimeStatusServiceValuePolicy.swift",
                "MacRuntimeControlApp/Presentation/Policies/RuntimeStatusDisplayPolicy.swift",
                "public struct RuntimeStatusServiceValuePolicy",
                "RuntimeStatusAdvancedServiceHealthPolicy("
            ),
            (
                "Interfaces/MacRuntimeControlApp/RuntimeStatusHTTPValuePolicy.swift",
                "MacRuntimeControlApp/Presentation/Policies/RuntimeStatusDisplayPolicy.swift",
                "public protocol RuntimeStatusHTTPValueVocabulary",
                "RuntimeStatusAdvancedServiceHealthVocabulary"
            ),
            (
                "Interfaces/MacRuntimeControlApp/RuntimeStatusHTTPValuePolicy.swift",
                "MacRuntimeControlApp/Presentation/Policies/RuntimeStatusDisplayPolicy.swift",
                "public struct RuntimeStatusHTTPValue",
                "RuntimeStatusAdvancedServiceHealthValue"
            ),
            (
                "Interfaces/MacRuntimeControlApp/RuntimeStatusHTTPValuePolicy.swift",
                "MacRuntimeControlApp/Presentation/Policies/RuntimeStatusDisplayPolicy.swift",
                "public struct RuntimeStatusHTTPValuePolicy",
                "RuntimeStatusAdvancedServiceHealthPolicy("
            ),
            (
                "Interfaces/MacRuntimeControlApp/RuntimeStatusComposeServiceValuePolicy.swift",
                "MacRuntimeControlApp/Presentation/Policies/RuntimeStatusDisplayPolicy.swift",
                "public protocol RuntimeStatusComposeServiceValueVocabulary",
                "RuntimeStatusAdvancedServiceHealthVocabulary"
            ),
            (
                "Interfaces/MacRuntimeControlApp/RuntimeStatusComposeServiceValuePolicy.swift",
                "MacRuntimeControlApp/Presentation/Policies/RuntimeStatusDisplayPolicy.swift",
                "public struct RuntimeStatusComposeServiceValue",
                "RuntimeStatusAdvancedServiceHealthValue"
            ),
            (
                "Interfaces/MacRuntimeControlApp/RuntimeStatusComposeServiceValuePolicy.swift",
                "MacRuntimeControlApp/Presentation/Policies/RuntimeStatusDisplayPolicy.swift",
                "public struct RuntimeStatusComposeServiceValuePolicy",
                "RuntimeStatusAdvancedServiceHealthPolicy("
            ),
            (
                "Interfaces/MacRuntimeControlApp/RuntimeStatusHealthDetailsPolicy.swift",
                "MacRuntimeControlApp/Presentation/Policies/RuntimeStatusDisplayPolicy.swift",
                "public protocol RuntimeStatusHealthDetailsVocabulary",
                "AppRuntimeStatusHealthDetailsVocabulary: RuntimeStatusHealthDetailsVocabulary"
            ),
            (
                "Interfaces/MacRuntimeControlApp/RuntimeStatusHealthDetailsPolicy.swift",
                "MacRuntimeControlApp/Presentation/Policies/RuntimeStatusDisplayPolicy.swift",
                "public struct RuntimeStatusHealthDetailValue",
                "RuntimeStatusHealthDetailValue"
            ),
            (
                "Interfaces/MacRuntimeControlApp/RuntimeStatusHealthDetailsPolicy.swift",
                "MacRuntimeControlApp/Presentation/Policies/RuntimeStatusDisplayPolicy.swift",
                "public struct RuntimeStatusHealthDetailItem",
                "RuntimeStatusHealthDetailItem"
            ),
            (
                "Interfaces/MacRuntimeControlApp/RuntimeStatusHealthDetailsPolicy.swift",
                "MacRuntimeControlApp/Presentation/Policies/RuntimeStatusDisplayPolicy.swift",
                "public struct RuntimeStatusHealthDetailsPolicy",
                "RuntimeStatusHealthDetailsPolicy("
            ),
            (
                "Interfaces/MacRuntimeControlApp/RuntimeStatusAdvancedServiceHealthPolicy.swift",
                "MacRuntimeControlApp/Presentation/Policies/RuntimeStatusDisplayPolicy.swift",
                "public enum RuntimeStatusServiceActionID",
                "RuntimeStatusServiceActionID"
            ),
            (
                "Interfaces/MacRuntimeControlApp/RuntimeStatusAdvancedServiceHealthPolicy.swift",
                "MacRuntimeControlApp/Presentation/Policies/RuntimeStatusDisplayPolicy.swift",
                "public protocol RuntimeStatusAdvancedServiceHealthVocabulary",
                "AppRuntimeStatusAdvancedServiceHealthVocabulary: RuntimeStatusAdvancedServiceHealthVocabulary"
            ),
            (
                "Interfaces/MacRuntimeControlApp/RuntimeStatusAdvancedServiceHealthPolicy.swift",
                "MacRuntimeControlApp/Presentation/Policies/RuntimeStatusDisplayPolicy.swift",
                "public struct RuntimeStatusAdvancedServiceHealthValue",
                "RuntimeStatusAdvancedServiceHealthValue"
            ),
            (
                "Interfaces/MacRuntimeControlApp/RuntimeStatusAdvancedServiceHealthPolicy.swift",
                "MacRuntimeControlApp/Presentation/Policies/RuntimeStatusDisplayPolicy.swift",
                "public struct RuntimeStatusAdvancedServiceHealthItem",
                "RuntimeStatusAdvancedServiceHealthItem"
            ),
            (
                "Interfaces/MacRuntimeControlApp/RuntimeStatusAdvancedServiceHealthPolicy.swift",
                "MacRuntimeControlApp/Presentation/Policies/RuntimeStatusDisplayPolicy.swift",
                "public struct RuntimeStatusAdvancedServiceHealthPolicy",
                "RuntimeStatusAdvancedServiceHealthPolicy("
            ),
            (
                "Interfaces/MacRuntimeControlApp/RuntimeStatusVitalServerAvailabilityPolicy.swift",
                "MacRuntimeControlApp/Presentation/Policies/RuntimeStatusDisplayPolicy.swift",
                "public protocol RuntimeStatusVitalServerAvailabilityVocabulary",
                "AppRuntimeStatusVitalServerAvailabilityVocabulary: RuntimeStatusVitalServerAvailabilityVocabulary"
            ),
            (
                "Interfaces/MacRuntimeControlApp/RuntimeStatusVitalServerAvailabilityPolicy.swift",
                "MacRuntimeControlApp/Presentation/Policies/RuntimeStatusDisplayPolicy.swift",
                "public struct RuntimeStatusVitalServerAvailabilityValue",
                "RuntimeStatusVitalServerAvailabilityValue"
            ),
            (
                "Interfaces/MacRuntimeControlApp/RuntimeStatusVitalServerAvailabilityPolicy.swift",
                "MacRuntimeControlApp/Presentation/Policies/RuntimeStatusDisplayPolicy.swift",
                "public struct RuntimeStatusVitalServerAvailabilityPolicy",
                "RuntimeStatusVitalServerAvailabilityPolicy("
            ),
            (
                "Interfaces/MacRuntimeControlApp/RuntimeVitalRecorderDisplayPolicy.swift",
                "MacRuntimeControlApp/Presentation/Views/RuntimeVitalRecorderDisplayPolicy.swift",
                "public struct RuntimeVitalRecorderDisplayPolicy",
                "typealias RuntimeVitalRecorderDisplayPolicy = Interfaces.RuntimeVitalRecorderDisplayPolicy"
            ),
            (
                "Interfaces/MacRuntimeControlApp/RuntimeStatusActionNeededPolicy.swift",
                "MacRuntimeControlApp/Presentation/Policies/RuntimeStatusDisplayPolicy.swift",
                "public protocol RuntimeStatusActionNeededVocabulary",
                "AppRuntimeStatusActionNeededVocabulary: RuntimeStatusActionNeededVocabulary"
            ),
            (
                "Interfaces/MacRuntimeControlApp/RuntimeStatusActionNeededPolicy.swift",
                "MacRuntimeControlApp/Presentation/Policies/RuntimeStatusDisplayPolicy.swift",
                "public struct RuntimeStatusActionNeededDecision",
                "RuntimeStatusActionNeededDecision"
            ),
            (
                "Interfaces/MacRuntimeControlApp/RuntimeStatusActionNeededPolicy.swift",
                "MacRuntimeControlApp/Presentation/Policies/RuntimeStatusDisplayPolicy.swift",
                "public struct RuntimeStatusActionNeededPolicy",
                "RuntimeStatusActionNeededPolicy("
            ),
            (
                "Interfaces/MacRuntimeControlApp/RuntimeStatusRecorderSummaryPolicy.swift",
                "MacRuntimeControlApp/Presentation/Policies/RuntimeStatusDisplayPolicy.swift",
                "public protocol RuntimeStatusRecorderSummaryVocabulary",
                "AppRuntimeStatusRecorderSummaryVocabulary: RuntimeStatusRecorderSummaryVocabulary"
            ),
            (
                "Interfaces/MacRuntimeControlApp/RuntimeStatusRecorderSummaryPolicy.swift",
                "MacRuntimeControlApp/Presentation/Policies/RuntimeStatusDisplayPolicy.swift",
                "public struct RuntimeStatusRecorderSummary",
                "typealias RecorderSummary = RuntimeStatusRecorderSummary"
            ),
            (
                "Interfaces/MacRuntimeControlApp/RuntimeStatusRecorderSummaryPolicy.swift",
                "MacRuntimeControlApp/Presentation/Policies/RuntimeStatusDisplayPolicy.swift",
                "public struct RuntimeStatusRecorderSummaryPolicy",
                "RuntimeStatusRecorderSummaryPolicy("
            ),
            (
                "Interfaces/MacRuntimeControlApp/RuntimeProcessMessageFormatter.swift",
                "MacRuntimeControlApp/Presentation/Formatting/RuntimeProcessMessageFormatter.swift",
                "public struct RuntimeProcessMessageFormatter",
                "typealias RuntimeProcessMessageFormatter = Interfaces.RuntimeProcessMessageFormatter"
            ),
            (
                "Interfaces/MacRuntimeControlApp/RuntimePresentationFormatter.swift",
                "MacRuntimeControlApp/Presentation/Formatting/RuntimePresentationFormatter.swift",
                "public protocol RuntimePresentationVocabulary",
                "typealias RuntimePresentationVocabulary = Interfaces.RuntimePresentationVocabulary"
            ),
            (
                "Interfaces/MacRuntimeControlApp/RuntimePresentationFormatter.swift",
                "MacRuntimeControlApp/Presentation/Formatting/RuntimePresentationFormatter.swift",
                "public struct RuntimePresentationFormatter",
                "typealias RuntimePresentationFormatter = Interfaces.RuntimePresentationFormatter"
            ),
            (
                "Interfaces/MacRuntimeControlApp/RuntimeVitalFilesDirectoryPolicy.swift",
                "MacRuntimeControlApp/Presentation/Policies/RuntimeVitalFilesDirectoryPolicy.swift",
                "public struct RuntimeVitalFilesDirectoryPolicy",
                "typealias RuntimeVitalFilesDirectoryPolicy = Interfaces.RuntimeVitalFilesDirectoryPolicy"
            ),
            (
                "Interfaces/MacRuntimeControlApp/RuntimeSection.swift",
                "MacRuntimeControlApp/Presentation/Policies/RuntimeSection.swift",
                "public enum RuntimeSection",
                "typealias RuntimeSection = Interfaces.RuntimeSection"
            ),
            (
                "Interfaces/MacRuntimeControlApp/RuntimeSettingsValidator.swift",
                "MacRuntimeControlApp/Presentation/Policies/RuntimeSettingsValidator.swift",
                "public struct RuntimeSettingsValidator",
                "typealias RuntimeSettingsValidator = Interfaces.RuntimeSettingsValidator"
            ),
            (
                "Interfaces/MacRuntimeControlApp/RuntimeSettingsValidator.swift",
                "MacRuntimeControlApp/Presentation/Policies/RuntimeSettingsValidator.swift",
                "public enum RuntimeSettingsValidationResult",
                "typealias RuntimeSettingsValidationResult = Interfaces.RuntimeSettingsValidationResult"
            ),
        ]

        for file in files {
            let interfacesFile = sourcesRoot.appendingPathComponent(file.interfaces)
            let appFile = sourcesRoot.appendingPathComponent(file.app)
            assertFileExists(
                interfacesFile,
                "\(file.declaration) implementation must live in Interfaces/MacRuntimeControlApp"
            )
            assertFileExists(
                appFile,
                "\(file.alias) shim must remain explicit while the app target is transitional"
            )

            let interfacesContents = try String(contentsOf: interfacesFile, encoding: .utf8)
            let appContents = try String(contentsOf: appFile, encoding: .utf8)
            XCTAssertTrue(
                interfacesContents.contains(file.declaration),
                "\(file.interfaces) must own the implementation"
            )
            XCTAssertFalse(
                interfacesContents.contains("import MacRuntimeControlApp"),
                "\(file.interfaces) must not import the app target"
            )
            XCTAssertTrue(
                appContents.contains(file.alias),
                "\(file.app) must point to Interfaces"
            )
            XCTAssertFalse(
                appContents.contains(file.declaration),
                "\(file.app) must not retain implementation"
            )
        }
    }

    func testLogExportDestinationRulesLiveInInterfacesWhileAppOwnsFilesystemReadAdapter() throws {
        let sourcesRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources")
        let interfacesFile = sourcesRoot
            .appendingPathComponent("Interfaces/MacRuntimeControlApp/RuntimeLogExportDestinationPolicy.swift")
        let appFile = sourcesRoot
            .appendingPathComponent("MacRuntimeControlApp/Presentation/Policies/RuntimeLogExportDestinationPolicy.swift")

        assertFileExists(interfacesFile, "Runtime log export destination rule implementation must live in Interfaces")
        assertFileExists(appFile, "Runtime log export destination app adapter must remain explicit while app is transitional")

        let interfacesContents = try String(contentsOf: interfacesFile, encoding: .utf8)
        let appContents = try String(contentsOf: appFile, encoding: .utf8)

        XCTAssertTrue(interfacesContents.contains("public struct RuntimeLogExportDestinationPolicy"))
        XCTAssertTrue(interfacesContents.contains("public struct RuntimeLogExportDestinationFacts"))
        XCTAssertTrue(interfacesContents.contains("public enum RuntimeLogExportDestinationValidationResult"))
        XCTAssertFalse(interfacesContents.contains("FileManager"))
        XCTAssertFalse(interfacesContents.contains("RuntimePathPermissionFileManaging"))
        XCTAssertFalse(interfacesContents.contains("AppConstants"))

        XCTAssertTrue(appContents.contains("RuntimePathPermissionFileManaging"))
        XCTAssertTrue(appContents.contains("extension FileManager: RuntimePathPermissionFileManaging"))
        XCTAssertTrue(appContents.contains("Interfaces.RuntimeLogExportDestinationPolicy()"))
        XCTAssertTrue(appContents.contains("typealias RuntimeLogExportDestinationFacts = Interfaces.RuntimeLogExportDestinationFacts"))
        XCTAssertTrue(appContents.contains("typealias RuntimeLogExportDestinationValidationResult = Interfaces.RuntimeLogExportDestinationValidationResult"))
    }

    func testFinalWorkflowLayerDoesNotImportOuterLayersOrOwnConcreteHostEffects() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/Workflow")
        let forbiddenImports = [
            "Core",
            "RuntimeWorkflow",
            "Infrastructure",
            "HostAdapters",
            "Interfaces",
            "Bootstrap",
            "HostInfrastructure",
            "HostCLI",
            "MacHostRuntimeAdapter",
            "MacRuntimeControlApp",
            "RuntimeControl",
            "RuntimeControlAPI",
        ]
        let forbiddenSymbols = [
            "FileManager.default",
            "Process()",
            "launchctl",
            "pkgutil",
            "hdiutil",
            "Virtualization",
        ]

        let swiftFiles = try swiftFiles(in: root)

        XCTAssertFalse(swiftFiles.isEmpty)
        for file in swiftFiles {
            let contents = try String(contentsOf: file, encoding: .utf8)
            for forbiddenImport in forbiddenImports {
                XCTAssertFalse(
                    contents.contains("import \(forbiddenImport)"),
                    "\(file.path) must not import \(forbiddenImport)"
                )
            }
            for forbiddenSymbol in forbiddenSymbols {
                XCTAssertFalse(
                    contents.contains(forbiddenSymbol),
                    "\(file.path) must not own concrete host effect: \(forbiddenSymbol)"
                )
            }
        }
    }

    func testApplicationDoesNotImportWorkflowOrOuterLayers() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/Application")
        let forbiddenImports = [
            "Core",
            "RuntimeWorkflow",
            "HostInfrastructure",
            "HostCLI",
            "MacHostRuntimeAdapter",
            "MacRuntimeControlApp",
            "RuntimeControl",
            "RuntimeControlAPI",
        ]

        let swiftFiles = try swiftFiles(in: root)

        XCTAssertFalse(swiftFiles.isEmpty)
        for file in swiftFiles {
            let contents = try String(contentsOf: file, encoding: .utf8)
            for forbiddenImport in forbiddenImports {
                XCTAssertFalse(
                    contents.contains("import \(forbiddenImport)"),
                    "\(file.path) must not import \(forbiddenImport)"
                )
            }
        }
    }

    func testFutureIdealLayerRootsPreserveDependencyDirectionWhenPresent() throws {
        let sourcesRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources")
        let layerRules: [(root: String, forbiddenImports: [String])] = [
            (
                "Domain",
                [
                    "Application",
                    "Core",
                    "Workflow",
                    "Infrastructure",
                    "HostAdapters",
                    "Interfaces",
                    "Bootstrap",
                    "HostCLI",
                    "HostInfrastructure",
                    "MacHostRuntimeAdapter",
                    "MacRuntimeControlApp",
                    "RuntimeControl",
                    "RuntimeControlAPI",
                ]
            ),
            (
                "Application",
                [
                    "Workflow",
                    "Infrastructure",
                    "HostAdapters",
                    "Interfaces",
                    "Bootstrap",
                    "HostCLI",
                    "HostInfrastructure",
                    "MacHostRuntimeAdapter",
                    "MacRuntimeControlApp",
                    "RuntimeControl",
                    "RuntimeControlAPI",
                ]
            ),
            (
                "Workflow",
                [
                    "Infrastructure",
                    "HostAdapters",
                    "Interfaces",
                    "Bootstrap",
                    "HostCLI",
                    "HostInfrastructure",
                    "MacHostRuntimeAdapter",
                    "MacRuntimeControlApp",
                    "RuntimeControl",
                    "RuntimeControlAPI",
                ]
            ),
            (
                "Infrastructure",
                [
                    "Interfaces",
                    "Bootstrap",
                    "HostCLI",
                    "MacRuntimeControlApp",
                    "RuntimeControlAPI",
                ]
            ),
            (
                "HostAdapters",
                [
                    "Interfaces",
                    "Bootstrap",
                    "HostCLI",
                    "MacRuntimeControlApp",
                    "RuntimeControlAPI",
                ]
            ),
            (
                "Interfaces",
                [
                    "Bootstrap",
                    "HostAdapters",
                    "Infrastructure",
                ]
            ),
        ]

        for rule in layerRules {
            let root = sourcesRoot.appendingPathComponent(rule.root)
            for file in try swiftFiles(in: root) {
                let contents = try String(contentsOf: file, encoding: .utf8)
                for forbiddenImport in rule.forbiddenImports {
                    XCTAssertFalse(
                        contents.contains("import \(forbiddenImport)"),
                        "\(file.path) must not import \(forbiddenImport) from the future ideal layer root \(rule.root)"
                    )
                }
            }
        }
    }

    private func swiftFiles(in root: URL) throws -> [URL] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory) else {
            return []
        }
        guard isDirectory.boolValue else {
            return root.pathExtension == "swift" ? [root] : []
        }

        return try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil
        ).flatMap { try swiftFiles(in: $0) }
    }

    private func assertDirectoryExists(_ url: URL, _ message: String) {
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), message)
        XCTAssertTrue(isDirectory.boolValue, "\(url.path) must be a directory")
    }

    private func assertFileExists(_ url: URL, _ message: String) {
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), message)
        XCTAssertFalse(isDirectory.boolValue, "\(url.path) must be a file")
    }

    private func assertTarget(
        _ target: String,
        in manifest: String,
        includesDependencies: [String],
        excludesDependencies: [String]
    ) {
        let declaration = targetDeclaration(target, in: manifest)
        XCTAssertNotNil(declaration, "Package.swift must declare target \(target)")
        guard let declaration else {
            return
        }

        for dependency in includesDependencies {
            XCTAssertTrue(
                declaration.contains("\"\(dependency)\""),
                "target \(target) must depend inward on \(dependency)"
            )
        }
        for dependency in excludesDependencies {
            XCTAssertFalse(
                declaration.contains("\"\(dependency)\""),
                "target \(target) must not depend outward on \(dependency)"
            )
        }
    }

    private func targetDeclaration(_ target: String, in manifest: String) -> String? {
        guard let nameRange = manifest.range(of: "name: \"\(target)\"") else {
            return nil
        }
        let prefix = manifest[..<nameRange.lowerBound]
        guard let targetStart = prefix.range(of: ".target(", options: .backwards)?.lowerBound else {
            return nil
        }
        let suffix = manifest[nameRange.upperBound...]
        guard let nextTarget = suffix.range(of: ".target(")?.lowerBound
            ?? suffix.range(of: ".executableTarget(")?.lowerBound
            ?? suffix.range(of: ".testTarget(")?.lowerBound else {
            return String(manifest[targetStart...])
        }
        return String(manifest[targetStart..<nextTarget])
    }
}
