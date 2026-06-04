import Foundation
import RuntimeWorkflow
import XCTest

final class RuntimeInstallVMDiskProvisionerTests: XCTestCase {
    func testProvisionCreatesMissingDiskFromRootfsAndTruncatesToRequestedSize() throws {
        let events = EventLog()
        let rootfs = URL(fileURLWithPath: "/runtime/rootfs.raw.gz")
        let vmDisk = URL(fileURLWithPath: "/runtime/vm.img")
        let temporary = URL(fileURLWithPath: "/runtime/.vm.img.tmp")
        var existingFiles: Set<URL> = [rootfs, temporary]
        let provisioner = makeProvisioner(
            rootfs: rootfs,
            vmDisk: vmDisk,
            existingFiles: { existingFiles },
            events: events,
            moveItem: { source, destination in
                existingFiles.remove(source)
                existingFiles.insert(destination)
            }
        )

        try provisioner.provision(diskGiB: 64)

        XCTAssertEqual(events.values, [
            "free-space:/runtime:1568:provision-vm-disk",
            "remove:/runtime/.vm.img.tmp",
            "run-to-file:/usr/bin/gunzip -c /runtime/rootfs.raw.gz -> /runtime/.vm.img.tmp",
            "move:/runtime/.vm.img.tmp:/runtime/vm.img",
            "log:created vm disk path=/runtime/vm.img source=rootfs.raw.gz",
            "run:/usr/bin/truncate -s 64G /runtime/vm.img",
        ])
    }

    func testProvisionExistingDiskOnlyTruncates() throws {
        let events = EventLog()
        let rootfs = URL(fileURLWithPath: "/runtime/rootfs.raw.gz")
        let vmDisk = URL(fileURLWithPath: "/runtime/vm.img")
        let provisioner = makeProvisioner(
            rootfs: rootfs,
            vmDisk: vmDisk,
            existingFiles: { [rootfs, vmDisk] },
            events: events
        )

        try provisioner.provision(diskGiB: 128)

        XCTAssertEqual(events.values, [
            "run:/usr/bin/truncate -s 128G /runtime/vm.img",
        ])
    }

    func testProvisionFailsWhenDiskAndRootfsAreMissing() {
        let events = EventLog()
        let rootfs = URL(fileURLWithPath: "/runtime/rootfs.raw.gz")
        let vmDisk = URL(fileURLWithPath: "/runtime/vm.img")
        let provisioner = makeProvisioner(
            rootfs: rootfs,
            vmDisk: vmDisk,
            existingFiles: { [] },
            events: events
        )

        XCTAssertThrowsError(try provisioner.provision(diskGiB: 64)) { error in
            XCTAssertEqual(String(describing: error), "missing file: /runtime/rootfs.raw.gz")
        }
        XCTAssertEqual(events.values, [])
    }

    private func makeProvisioner(
        rootfs: URL,
        vmDisk: URL,
        existingFiles: @escaping () -> Set<URL>,
        events: EventLog,
        moveItem: @escaping (URL, URL) throws -> Void = { _, _ in }
    ) -> RuntimeInstallVMDiskProvisioner {
        RuntimeInstallVMDiskProvisioner(
            context: RuntimeInstallVMDiskProvisioningContext(
                rootfsBase: rootfs,
                vmDisk: vmDisk,
                gunzipExecutable: "/usr/bin/gunzip",
                truncateExecutable: "/usr/bin/truncate",
                freeSpaceMarginBytes: 128
            ),
            operations: RuntimeInstallVMDiskProvisioningOperations(
                fileExists: { url in
                    existingFiles().contains(url)
                },
                fileSize: { _ in
                    240
                },
                requireFreeSpace: { url, bytes, operation in
                    events.append("free-space:\(url.path):\(bytes):\(operation)")
                },
                removeItem: { url in
                    events.append("remove:\(url.path)")
                },
                runProcessToFile: { executable, arguments, output in
                    events.append("run-to-file:\(executable) \(arguments.joined(separator: " ")) -> \(output.path)")
                },
                moveItem: { source, destination in
                    events.append("move:\(source.path):\(destination.path)")
                    try moveItem(source, destination)
                },
                runRequired: { executable, arguments in
                    events.append("run:\(executable) \(arguments.joined(separator: " "))")
                },
                log: { message in
                    events.append("log:\(message)")
                }
            )
        )
    }

    private final class EventLog {
        private(set) var values: [String] = []

        func append(_ value: String) {
            values.append(value)
        }
    }
}
