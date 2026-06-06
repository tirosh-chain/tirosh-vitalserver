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
}
