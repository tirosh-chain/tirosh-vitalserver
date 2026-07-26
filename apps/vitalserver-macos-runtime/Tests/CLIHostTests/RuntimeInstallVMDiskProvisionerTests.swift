import Foundation
import Contracts
import OutboundAdapters
import XCTest
import Errors

final class RuntimeInstallVMDiskProvisionerTests: XCTestCase {
    func testProvisionCreatesMissingDiskFromRootfsAndTruncatesToRequestedSize() throws {
        let events = EventLog()
        let rootfs = URL(fileURLWithPath: "/runtime/rootfs.raw.gz")
        let vmDisk = URL(fileURLWithPath: "/runtime/vm.img")
        let temporary = URL(fileURLWithPath: "/runtime/.vm.img.tmp")
        let runtimeDataDisk = URL(fileURLWithPath: "/runtime/runtime-data.img")
        var existingFiles: Set<URL> = [rootfs, temporary]
        let provisioner = makeProvisioner(
            rootfs: rootfs,
            vmDisk: vmDisk,
            runtimeDataDisk: runtimeDataDisk,
            existingFiles: { existingFiles },
            events: events,
            moveItem: { source, destination in
                existingFiles.remove(source)
                existingFiles.insert(destination)
            }
        )

        try provisioner.provision(diskGiB: 64)

        XCTAssertEqual(events.values, [
            "free-space:/runtime:17179870880:provision-vm-and-runtime-data-disks",
            "remove:/runtime/.vm.img.tmp",
            "run-to-file:/usr/bin/gunzip -c /runtime/rootfs.raw.gz -> /runtime/.vm.img.tmp",
            "move:/runtime/.vm.img.tmp:/runtime/vm.img",
            "log:created vm disk path=/runtime/vm.img source=rootfs.raw.gz",
            "run:/usr/bin/truncate -s 64G /runtime/vm.img",
            "run:/usr/bin/truncate -s 16G /runtime/runtime-data.img",
            "log:created runtime data disk path=/runtime/runtime-data.img size=16G",
        ])
    }

    func testProvisionPreservesExistingVMDiskWithoutResizingIt() throws {
        let events = EventLog()
        let rootfs = URL(fileURLWithPath: "/runtime/rootfs.raw.gz")
        let vmDisk = URL(fileURLWithPath: "/runtime/vm.img")
        let runtimeDataDisk = URL(fileURLWithPath: "/runtime/runtime-data.img")
        let provisioner = makeProvisioner(
            rootfs: rootfs,
            vmDisk: vmDisk,
            runtimeDataDisk: runtimeDataDisk,
            existingFiles: { [rootfs, vmDisk, runtimeDataDisk] },
            events: events
        )

        try provisioner.provision(diskGiB: 128)

        XCTAssertEqual(events.values, [
            "log:preserved vm disk path=/runtime/vm.img",
            "log:preserved runtime data disk path=/runtime/runtime-data.img",
        ])
    }

    func testProvisionCreatesMissingRuntimeDataDiskWhenConfigured() throws {
        let events = EventLog()
        let rootfs = URL(fileURLWithPath: "/runtime/rootfs.raw.gz")
        let vmDisk = URL(fileURLWithPath: "/runtime/vm.img")
        let runtimeDataDisk = URL(fileURLWithPath: "/runtime/runtime-data.img")
        let provisioner = makeProvisioner(
            rootfs: rootfs,
            vmDisk: vmDisk,
            runtimeDataDisk: runtimeDataDisk,
            existingFiles: { [rootfs, vmDisk] },
            events: events
        )

        try provisioner.provision(diskGiB: 64, runtimeDataDiskGiB: 16)

        XCTAssertEqual(events.values, [
            "free-space:/runtime:17179869312:provision-runtime-data-disk",
            "log:preserved vm disk path=/runtime/vm.img",
            "run:/usr/bin/truncate -s 16G /runtime/runtime-data.img",
            "log:created runtime data disk path=/runtime/runtime-data.img size=16G",
        ])
    }

    func testProvisionCreatesMissingVMDiskAndPreservesExistingRuntimeDataDisk() throws {
        let events = EventLog()
        let rootfs = URL(fileURLWithPath: "/runtime/rootfs.raw.gz")
        let vmDisk = URL(fileURLWithPath: "/runtime/vm.img")
        let runtimeDataDisk = URL(fileURLWithPath: "/runtime/runtime-data.img")
        var existingFiles: Set<URL> = [rootfs, runtimeDataDisk]
        let provisioner = makeProvisioner(
            rootfs: rootfs,
            vmDisk: vmDisk,
            runtimeDataDisk: runtimeDataDisk,
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
            "run-to-file:/usr/bin/gunzip -c /runtime/rootfs.raw.gz -> /runtime/.vm.img.tmp",
            "move:/runtime/.vm.img.tmp:/runtime/vm.img",
            "log:created vm disk path=/runtime/vm.img source=rootfs.raw.gz",
            "run:/usr/bin/truncate -s 64G /runtime/vm.img",
            "log:preserved runtime data disk path=/runtime/runtime-data.img",
        ])
    }

    func testProvisionPreservesExistingRuntimeDataDiskWhenConfigured() throws {
        let events = EventLog()
        let rootfs = URL(fileURLWithPath: "/runtime/rootfs.raw.gz")
        let vmDisk = URL(fileURLWithPath: "/runtime/vm.img")
        let runtimeDataDisk = URL(fileURLWithPath: "/runtime/runtime-data.img")
        let provisioner = makeProvisioner(
            rootfs: rootfs,
            vmDisk: vmDisk,
            runtimeDataDisk: runtimeDataDisk,
            existingFiles: { [rootfs, vmDisk, runtimeDataDisk] },
            events: events
        )

        try provisioner.provision(diskGiB: 64, runtimeDataDiskGiB: 16)

        XCTAssertEqual(events.values, [
            "log:preserved vm disk path=/runtime/vm.img",
            "log:preserved runtime data disk path=/runtime/runtime-data.img",
        ])
    }

    func testProvisionFailsWhenExistingRuntimeDataDiskIsTooSmall() {
        let events = EventLog()
        let rootfs = URL(fileURLWithPath: "/runtime/rootfs.raw.gz")
        let vmDisk = URL(fileURLWithPath: "/runtime/vm.img")
        let runtimeDataDisk = URL(fileURLWithPath: "/runtime/runtime-data.img")
        let provisioner = makeProvisioner(
            rootfs: rootfs,
            vmDisk: vmDisk,
            runtimeDataDisk: runtimeDataDisk,
            existingFiles: { [rootfs, vmDisk, runtimeDataDisk] },
            events: events,
            fileSize: { url in
                url == runtimeDataDisk ? 1024 : 240
            }
        )

        XCTAssertThrowsError(try provisioner.provision(diskGiB: 64, runtimeDataDiskGiB: 16)) { error in
            XCTAssertEqual(
                String(describing: error),
                "runtime data disk is too small: /runtime/runtime-data.img actualBytes=1024 requiredBytes=17179869184"
            )
        }
        XCTAssertEqual(events.values, [
            "log:preserved vm disk path=/runtime/vm.img",
        ])
    }

    func testProvisionFailsWhenDiskAndRootfsAreMissing() {
        let events = EventLog()
        let rootfs = URL(fileURLWithPath: "/runtime/rootfs.raw.gz")
        let vmDisk = URL(fileURLWithPath: "/runtime/vm.img")
        let runtimeDataDisk = URL(fileURLWithPath: "/runtime/runtime-data.img")
        let provisioner = makeProvisioner(
            rootfs: rootfs,
            vmDisk: vmDisk,
            runtimeDataDisk: runtimeDataDisk,
            existingFiles: { [] },
            events: events
        )

        XCTAssertThrowsError(try provisioner.provision(diskGiB: 64)) { error in
            XCTAssertEqual(String(describing: error), "missing file: /runtime/rootfs.raw.gz")
        }
        XCTAssertEqual(events.values, [])
    }

    func testProvisionFailsWhenDiskStateInspectionFails() {
        let events = EventLog()
        let rootfs = URL(fileURLWithPath: "/runtime/rootfs.raw.gz")
        let vmDisk = URL(fileURLWithPath: "/runtime/vm.img")
        let runtimeDataDisk = URL(fileURLWithPath: "/runtime/runtime-data.img")
        let provisioner = makeProvisioner(
            rootfs: rootfs,
            vmDisk: vmDisk,
            runtimeDataDisk: runtimeDataDisk,
            existingFiles: { [rootfs] },
            events: events,
            fileState: { url in
                url == vmDisk ? .inspectFailed("permission denied") : .present
            }
        )

        XCTAssertThrowsError(try provisioner.provision(diskGiB: 64)) { error in
            XCTAssertEqual(
                String(describing: error),
                "file inspection failed: /runtime/vm.img reason=permission denied"
            )
        }
        XCTAssertEqual(events.values, [])
    }

    func testProvisionFailsWhenRootfsStateInspectionFails() {
        let events = EventLog()
        let rootfs = URL(fileURLWithPath: "/runtime/rootfs.raw.gz")
        let vmDisk = URL(fileURLWithPath: "/runtime/vm.img")
        let runtimeDataDisk = URL(fileURLWithPath: "/runtime/runtime-data.img")
        let provisioner = makeProvisioner(
            rootfs: rootfs,
            vmDisk: vmDisk,
            runtimeDataDisk: runtimeDataDisk,
            existingFiles: { [] },
            events: events,
            fileState: { url in
                url == rootfs ? .inspectFailed("permission denied") : .missing
            }
        )

        XCTAssertThrowsError(try provisioner.provision(diskGiB: 64)) { error in
            XCTAssertEqual(
                String(describing: error),
                "file inspection failed: /runtime/rootfs.raw.gz reason=permission denied"
            )
        }
        XCTAssertEqual(events.values, [])
    }

    func testProvisionFailsWhenTemporaryDiskStateInspectionFails() {
        let events = EventLog()
        let rootfs = URL(fileURLWithPath: "/runtime/rootfs.raw.gz")
        let vmDisk = URL(fileURLWithPath: "/runtime/vm.img")
        let temporary = URL(fileURLWithPath: "/runtime/.vm.img.tmp")
        let runtimeDataDisk = URL(fileURLWithPath: "/runtime/runtime-data.img")
        let provisioner = makeProvisioner(
            rootfs: rootfs,
            vmDisk: vmDisk,
            runtimeDataDisk: runtimeDataDisk,
            existingFiles: { [rootfs] },
            events: events,
            fileState: { url in
                if url == rootfs {
                    return .present
                }
                if url == temporary {
                    return .inspectFailed("permission denied")
                }
                return .missing
            }
        )

        XCTAssertThrowsError(try provisioner.provision(diskGiB: 64)) { error in
            XCTAssertEqual(
                String(describing: error),
                "file inspection failed: /runtime/.vm.img.tmp reason=permission denied"
            )
        }
        XCTAssertEqual(events.values, [
            "free-space:/runtime:17179870880:provision-vm-and-runtime-data-disks",
        ])
    }

    func testProvisionDoesNotWriteWhenCombinedFreeSpacePreflightFails() {
        let events = EventLog()
        let rootfs = URL(fileURLWithPath: "/runtime/rootfs.raw.gz")
        let vmDisk = URL(fileURLWithPath: "/runtime/vm.img")
        let runtimeDataDisk = URL(fileURLWithPath: "/runtime/runtime-data.img")
        let provisioner = makeProvisioner(
            rootfs: rootfs,
            vmDisk: vmDisk,
            runtimeDataDisk: runtimeDataDisk,
            existingFiles: { [rootfs] },
            events: events,
            requireFreeSpace: { url, bytes, operation in
                events.append("free-space:\(url.path):\(bytes):\(operation)")
                throw TestError.insufficientFreeSpace
            }
        )

        XCTAssertThrowsError(try provisioner.provision(diskGiB: 64)) { error in
            XCTAssertEqual(error as? TestError, .insufficientFreeSpace)
        }
        XCTAssertEqual(events.values, [
            "free-space:/runtime:17179870880:provision-vm-and-runtime-data-disks",
        ])
    }

    private func makeProvisioner(
        rootfs: URL,
        vmDisk: URL,
        runtimeDataDisk: URL,
        existingFiles: @escaping () -> Set<URL>,
        events: EventLog,
        fileState: ((URL) -> RuntimeFileState)? = nil,
        fileSize: ((URL) throws -> UInt64)? = nil,
        requireFreeSpace: ((URL, UInt64, String) throws -> Void)? = nil,
        moveItem: @escaping (URL, URL) throws -> Void = { _, _ in }
    ) -> RuntimeInstallVMDiskProvisioner {
        RuntimeInstallVMDiskProvisioner(
            context: RuntimeInstallVMDiskProvisioningContext(
                rootfsBase: rootfs,
                vmDisk: vmDisk,
                runtimeDataDisk: runtimeDataDisk,
                gunzipExecutable: "/usr/bin/gunzip",
                truncateExecutable: "/usr/bin/truncate",
                freeSpaceMarginBytes: 128
            ),
            operations: RuntimeInstallVMDiskProvisioningOperations(
                fileState: fileState ?? { url in
                    existingFiles().contains(url) ? .present : .missing
                },
                fileSize: fileSize ?? { url in
                    url == runtimeDataDisk ? UInt64(16) * 1024 * 1024 * 1024 : 240
                },
                requireFreeSpace: requireFreeSpace ?? { url, bytes, operation in
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

    private enum TestError: Error, Equatable {
        case insufficientFreeSpace
    }
}
