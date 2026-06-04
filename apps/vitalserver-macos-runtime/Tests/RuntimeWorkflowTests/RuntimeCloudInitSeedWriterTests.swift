import Foundation
import RuntimeWorkflow
import XCTest

final class RuntimeCloudInitSeedWriterTests: XCTestCase {
    func testCreateReplacesSeedDirectoryWritesCloudInitDocumentsAndBuildsISO() throws {
        let runtimeDirectory = URL(fileURLWithPath: "/runtime")
        let seedDirectory = runtimeDirectory.appendingPathComponent("cloud-init-seed")
        let seedISO = runtimeDirectory.appendingPathComponent("seed.iso")
        let events = EventLog()
        let writer = makeWriter(
            runtimeDirectory: runtimeDirectory,
            existingDirectories: [seedDirectory],
            existingFiles: [seedISO],
            events: events
        )

        try writer.create(hostname: "vitalserver")

        XCTAssertEqual(events.values, [
            "remove:/runtime/cloud-init-seed",
            "mkdir:/runtime/cloud-init-seed:true",
            "write:/runtime/cloud-init-seed/meta-data:true",
            "write:/runtime/cloud-init-seed/user-data:true",
            "remove:/runtime/seed.iso",
            "run:/usr/bin/hdiutil makehybrid -iso -joliet -default-volume-name cidata -o /runtime/seed.iso /runtime/cloud-init-seed",
        ])
        XCTAssertEqual(events.writes["/runtime/cloud-init-seed/meta-data"], """
        instance-id: tirosh-instance-1
        local-hostname: vitalserver

        """)
        XCTAssertTrue(events.writes["/runtime/cloud-init-seed/user-data"]?.contains("hostname: vitalserver") == true)
        XCTAssertTrue(events.writes["/runtime/cloud-init-seed/user-data"]?.contains("bootstrap.sh > /mnt/tirosh/run/bootstrap.log 2>&1") == true)
    }

    func testCreateDoesNotRemoveAbsentSeedDirectoryOrISO() throws {
        let runtimeDirectory = URL(fileURLWithPath: "/runtime")
        let events = EventLog()
        let writer = makeWriter(
            runtimeDirectory: runtimeDirectory,
            existingDirectories: [],
            existingFiles: [],
            events: events
        )

        try writer.create(hostname: "vitalserver")

        XCTAssertFalse(events.values.contains("remove:/runtime/cloud-init-seed"))
        XCTAssertFalse(events.values.contains("remove:/runtime/seed.iso"))
    }

    private func makeWriter(
        runtimeDirectory: URL,
        existingDirectories: Set<URL>,
        existingFiles: Set<URL>,
        events: EventLog
    ) -> RuntimeCloudInitSeedWriter {
        RuntimeCloudInitSeedWriter(
            context: RuntimeCloudInitSeedContext(
                runtimeDirectory: runtimeDirectory,
                seedImageName: "seed.iso",
                seedVolumeName: "cidata",
                hdiutilExecutable: "/usr/bin/hdiutil"
            ),
            operations: RuntimeCloudInitSeedOperations(
                directoryExists: { url in
                    existingDirectories.contains(url)
                },
                fileExists: { url in
                    existingFiles.contains(url)
                },
                removeItem: { url in
                    events.append("remove:\(url.path)")
                },
                createDirectory: { url, withIntermediateDirectories in
                    events.append("mkdir:\(url.path):\(withIntermediateDirectories)")
                },
                writeData: { data, url, options in
                    events.append("write:\(url.path):\(options.contains(.atomic))")
                    events.writes[url.path] = String(decoding: data, as: UTF8.self)
                },
                runRequired: { executable, arguments in
                    events.append("run:\(executable) \(arguments.joined(separator: " "))")
                },
                instanceID: {
                    "tirosh-instance-1"
                }
            )
        )
    }

    private final class EventLog {
        private(set) var values: [String] = []
        var writes: [String: String] = [:]

        func append(_ value: String) {
            values.append(value)
        }
    }
}
