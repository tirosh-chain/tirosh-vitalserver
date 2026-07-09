import Foundation
import Bootstrap
import Application
import Contracts
import InboundAdapters
import OutboundAdapters
@testable import CLIHost
import XCTest
import Errors

final class RuntimeLifecycleGuestControlURLTests: XCTestCase {
    func testDefaultGuestControlURLUsesInjectedGuestAddressProviderRead() throws {
        let (lifecycle, _, _) = makeLifecycle(
            guestAddressProvider: StubGuestAddressProvider(
                read: .loaded(address: "192.168.64.9", source: .runtimeControlAPI)
            )
        )

        let baseURL = try lifecycle.resolvedGuestControlBaseURL(
            RuntimeGuestServiceControlCommand.defaultGuestControlBaseURL
        )

        XCTAssertEqual(baseURL, "http://192.168.64.9:18330")
    }

    func testDefaultGuestControlURLUsesInjectedGuestAddressProvider() throws {
        let (lifecycle, _, _) = makeLifecycle(
            guestAddressProvider: StubGuestAddressProvider(
                read: .loaded(address: "192.168.64.21", source: .runtimeControlAPI)
            )
        )

        let baseURL = try lifecycle.resolvedGuestControlBaseURL(
            RuntimeGuestServiceControlCommand.defaultGuestControlBaseURL
        )

        XCTAssertEqual(baseURL, "http://192.168.64.21:18330")
    }

    func testDefaultGuestControlURLDoesNotUseRuntimeStatusVMIP() throws {
        let fileStore = RuntimeFileStoreSpy()
        let installedPaths = InstalledRuntimePaths(productRoot: URL(fileURLWithPath: "/guest-control-url"))
        let (lifecycle, _, _) = makeLifecycle(
            installedPaths: installedPaths,
            fileStore: fileStore,
            guestAddressProvider: StubGuestAddressProvider(
                read: .missing("missing-vm-ip")
            )
        )
        fileStore.files[installedPaths.runtimeStatus] = Data("""
        {
          "schemaVersion": 2,
          "product": "VitalServerHelper",
          "status": "healthy",
          "operation": "health",
          "message": "ok",
          "updatedAt": "2026-07-01T00:00:00Z",
          "productRoot": "/tmp/product",
          "runtimeHome": "/tmp/vm",
          "runtimeVersion": "1.0.0",
          "proxyPort": 19090,
          "vmIP": "192.168.64.88",
          "rootfsBase": "present",
          "vmDisk": "present",
          "failureReasons": []
        }
        """.utf8)

        XCTAssertThrowsError(try lifecycle.resolvedGuestControlBaseURL(
            RuntimeGuestServiceControlCommand.defaultGuestControlBaseURL
        )) { error in
            let description = String(describing: error)
            XCTAssertTrue(description.contains("missing-vm-ip"))
            XCTAssertFalse(description.contains("runtime status"))
            XCTAssertFalse(description.contains("192.168.64.88"))
        }
    }

    func testExplicitGuestControlURLBypassesGuestAddressRead() throws {
        let (lifecycle, _, _) = makeLifecycle()

        let baseURL = try lifecycle.resolvedGuestControlBaseURL("http://192.168.64.44:18330")

        XCTAssertEqual(baseURL, "http://192.168.64.44:18330")
    }

    private func makeLifecycle() -> (
        RuntimeLifecycle,
        InstalledRuntimePaths,
        RuntimeFileStoreSpy
    ) {
        makeLifecycle(guestAddressProvider: nil)
    }

    private func makeLifecycle(
        guestAddressProvider: (any RuntimeGuestAddressProvider)?
    ) -> (
        RuntimeLifecycle,
        InstalledRuntimePaths,
        RuntimeFileStoreSpy
    ) {
        let installedPaths = InstalledRuntimePaths(productRoot: URL(fileURLWithPath: "/guest-control-url"))
        return makeLifecycle(
            installedPaths: installedPaths,
            fileStore: RuntimeFileStoreSpy(),
            guestAddressProvider: guestAddressProvider
        )
    }

    private func makeLifecycle(
        installedPaths: InstalledRuntimePaths,
        fileStore: RuntimeFileStoreSpy,
        guestAddressProvider: (any RuntimeGuestAddressProvider)?
    ) -> (
        RuntimeLifecycle,
        InstalledRuntimePaths,
        RuntimeFileStoreSpy
    ) {
        let lifecycle = RuntimeLifecycle(
            paths: LauncherPaths(
                home: installedPaths.runtimeHome,
                installed: installedPaths,
                config: installedPaths.vmConfig,
                pidFile: installedPaths.pidFile
            ),
            runtimeStatusArtifactSink: MissingStatusArtifactSinkForGuestControlURL(),
            guestAddressProvider: guestAddressProvider,
            fileStore: fileStore
        )
        return (lifecycle, installedPaths, fileStore)
    }
}

private struct MissingStatusArtifactSinkForGuestControlURL: RuntimeStatusArtifactSink {
    func save(_: RuntimeStatusDocument) throws {}
}

private struct StubGuestAddressProvider: RuntimeGuestAddressProvider {
    let read: RuntimeGuestAddressReadResult

    func readGuestAddress() -> RuntimeGuestAddressReadResult {
        read
    }
}
