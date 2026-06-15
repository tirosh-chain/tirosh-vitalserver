import Foundation
import Contracts
import OutboundAdapters
import XCTest
import Errors

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
            "build-seed-image:/runtime/cloud-init-seed:/runtime/seed.iso:cidata",
        ])
        XCTAssertEqual(events.writes["/runtime/cloud-init-seed/meta-data"], """
        instance-id: tirosh-instance-1
        local-hostname: vitalserver

        """)
        let userData = try XCTUnwrap(events.writes["/runtime/cloud-init-seed/user-data"])
        XCTAssertTrue(userData.contains("hostname: vitalserver"))
        XCTAssertTrue(userData.contains("ssh_pwauth: false"))
        XCTAssertTrue(userData.contains("lock_passwd: true"))
        XCTAssertTrue(userData.contains("ssh_authorized_keys: []"))
        XCTAssertTrue(userData.contains("bootstrap.sh > /mnt/tirosh/run/bootstrap.log 2>&1"))
        XCTAssertFalse(userData.contains("ssh_pwauth: true"))
        XCTAssertFalse(userData.contains("chpasswd:"))
        XCTAssertFalse(userData.contains("password: ubuntu"))
    }

    func testCreateWritesExplicitSSHAuthorizedKeysWhenProvided() throws {
        let runtimeDirectory = URL(fileURLWithPath: "/runtime")
        let events = EventLog()
        let writer = makeWriter(
            runtimeDirectory: runtimeDirectory,
            existingDirectories: [],
            existingFiles: [],
            events: events
        )

        try writer.create(
            hostname: "vitalserver",
            sshAuthorizedKeys: [
                "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEexample operator@example.test",
                "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQexample operator's key",
            ]
        )

        let userData = try XCTUnwrap(events.writes["/runtime/cloud-init-seed/user-data"])
        XCTAssertTrue(userData.contains("ssh_authorized_keys:"))
        XCTAssertTrue(userData.contains("- 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEexample operator@example.test'"))
        XCTAssertTrue(userData.contains("- 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQexample operator''s key'"))
        XCTAssertFalse(userData.contains("password: ubuntu"))
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

    func testCreateFailsBeforeWritingWhenSeedDirectoryInspectionFails() {
        let runtimeDirectory = URL(fileURLWithPath: "/runtime")
        let seedDirectory = runtimeDirectory.appendingPathComponent("cloud-init-seed")
        let events = EventLog()
        let writer = makeWriter(
            runtimeDirectory: runtimeDirectory,
            pathStates: [seedDirectory: .inspectFailed("permission denied")],
            events: events
        )

        XCTAssertThrowsError(try writer.create(hostname: "vitalserver")) { error in
            XCTAssertEqual(
                error as? RuntimeCloudInitSeedWriterError,
                .pathInspectionFailed(path: seedDirectory.path, reason: "permission denied")
            )
        }
        XCTAssertTrue(events.values.isEmpty)
    }

    func testCreateFailsBeforeBuildingISOWhenSeedImageInspectionFails() {
        let runtimeDirectory = URL(fileURLWithPath: "/runtime")
        let seedISO = runtimeDirectory.appendingPathComponent("seed.iso")
        let events = EventLog()
        let writer = makeWriter(
            runtimeDirectory: runtimeDirectory,
            pathStates: [seedISO: .inspectFailed("permission denied")],
            events: events
        )

        XCTAssertThrowsError(try writer.create(hostname: "vitalserver")) { error in
            XCTAssertEqual(
                error as? RuntimeCloudInitSeedWriterError,
                .pathInspectionFailed(path: seedISO.path, reason: "permission denied")
            )
        }
        XCTAssertEqual(events.values, [
            "mkdir:/runtime/cloud-init-seed:true",
            "write:/runtime/cloud-init-seed/meta-data:true",
            "write:/runtime/cloud-init-seed/user-data:true",
        ])
        XCTAssertFalse(events.values.contains { $0.hasPrefix("build-seed-image:") })
    }

    private func makeWriter(
        runtimeDirectory: URL,
        existingDirectories: Set<URL>,
        existingFiles: Set<URL>,
        events: EventLog
    ) -> RuntimeCloudInitSeedWriter {
        var pathStates: [URL: RuntimePathState] = [:]
        for directory in existingDirectories {
            pathStates[directory] = .directory
        }
        for file in existingFiles {
            pathStates[file] = .file
        }
        return makeWriter(runtimeDirectory: runtimeDirectory, pathStates: pathStates, events: events)
    }

    private func makeWriter(
        runtimeDirectory: URL,
        pathStates: [URL: RuntimePathState],
        events: EventLog
    ) -> RuntimeCloudInitSeedWriter {
        RuntimeCloudInitSeedWriter(
            context: RuntimeCloudInitSeedContext(
                runtimeDirectory: runtimeDirectory,
                seedImageName: "seed.iso",
                seedVolumeName: "cidata"
            ),
            operations: RuntimeCloudInitSeedOperations(
                pathState: { url in
                    pathStates[url] ?? .missing
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
                buildSeedImage: { request in
                    events.append(
                        "build-seed-image:\(request.sourceDirectory.path):\(request.outputImage.path):\(request.volumeName)"
                    )
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
