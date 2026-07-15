import Contracts
import Domain
import XCTest

final class RuntimePackageInstallPreflightPolicyTests: XCTestCase {
    func testAllowsFreshInstallWhenFreshPreflightPassed() {
        XCTAssertEqual(
            RuntimePackageInstallPreflightPolicy.disposition(document: document()),
            .fresh
        )
    }

    func testTreatsExistingReceiptAsReinstallInsteadOfBlockingOnOwnedArtifactsAndServices() {
        XCTAssertEqual(
            RuntimePackageInstallPreflightPolicy.disposition(document: document(
                passed: false,
                blockers: [
                    "install-artifact-present:path=/Applications/VitalServer Helper.app",
                    "launchd-service-loaded:label=ai.tirosh.vitalserver.helper.vm",
                ],
                artifactStates: [.present(path: "/Applications/VitalServer Helper.app")],
                receiptStates: [.present(identifier: "ai.tirosh.vitalserver.helper")]
            )),
            .reinstall
        )
    }

    func testBlocksReinstallWhenArtifactInspectionFailed() {
        XCTAssertEqual(
            RuntimePackageInstallPreflightPolicy.disposition(document: document(
                passed: false,
                blockers: [],
                artifactStates: [.inspectFailed(path: "/Library/Application Support/VitalServerHelper", reason: "permission denied")],
                receiptStates: [.present(identifier: "ai.tirosh.vitalserver.helper")]
            )),
            .blocked([
                "install-artifact-inspect-failed:path=/Library/Application Support/VitalServerHelper reason=permission denied",
            ])
        )
    }

    func testBlocksWhenReceiptStateCannotBeRead() {
        XCTAssertEqual(
            RuntimePackageInstallPreflightPolicy.disposition(document: document(
                passed: false,
                blockers: [],
                receiptStates: [.readFailed(identifier: "ai.tirosh.vitalserver.helper", reason: "pkgutil failed")]
            )),
            .blocked([
                "package-receipt-read-failed:identifier=ai.tirosh.vitalserver.helper reason=pkgutil failed",
            ])
        )
    }

    private func document(
        passed: Bool = true,
        blockers: [String] = [],
        artifactStates: [RuntimeInstallArtifactState] = [.absent(path: "/Applications/VitalServer Helper.app")],
        receiptStates: [RuntimePackageReceiptState] = [.absent(identifier: "ai.tirosh.vitalserver.helper")]
    ) -> RuntimeFreshInstallPreflightDocument {
        RuntimeFreshInstallPreflightDocument(
            passed: passed,
            proxyPort: 80,
            blockers: blockers,
            settingsState: .loaded(path: "/private/tmp/install.json", proxyPort: 80),
            artifactStates: artifactStates,
            serviceStates: [],
            packageReceiptStates: receiptStates,
            proxyPortState: .clear(port: 80)
        )
    }
}
