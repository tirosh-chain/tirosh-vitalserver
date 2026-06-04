import XCTest

final class RuntimeWorkflowBoundaryTests: XCTestCase {
    func testCoreUsesExplicitResponsibilityFoldersInsteadOfApplicationFolder() {
        let coreRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/Core")
        let ambiguousApplicationFolder = coreRoot.appendingPathComponent("Application")

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: ambiguousApplicationFolder.path),
            "Core must not use an ambiguous Application folder; workflow orchestration belongs to RuntimeWorkflow"
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

    func testRuntimeWorkflowDoesNotImportOuterLayers() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/RuntimeWorkflow")
        let forbiddenImports = [
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
}
