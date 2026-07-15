import Contracts

public enum RuntimePackageInstallDisposition: Equatable, Sendable {
    case fresh
    case reinstall
    case blocked([String])
}

public enum RuntimePackageInstallPreflightPolicy {
    public static func disposition(
        document: RuntimeFreshInstallPreflightDocument
    ) -> RuntimePackageInstallDisposition {
        var receiptFailures: [String] = []
        var hasExistingReceipt = false

        for state in document.packageReceiptStates {
            switch state {
            case .present:
                hasExistingReceipt = true
            case .absent:
                continue
            case .readFailed(let identifier, let reason):
                receiptFailures.append("package-receipt-read-failed:identifier=\(identifier) reason=\(reason)")
            case .forgetFailed(let identifier, let reason):
                receiptFailures.append("package-receipt-state-invalid:identifier=\(identifier) reason=\(reason)")
            case .unknown(let value):
                receiptFailures.append("package-receipt-state-unknown:value=\(value)")
            }
        }

        if !receiptFailures.isEmpty {
            return .blocked(receiptFailures)
        }
        if hasExistingReceipt {
            let inspectionFailures = document.artifactStates.compactMap { state -> String? in
                switch state {
                case .inspectFailed(let path, let reason):
                    return "install-artifact-inspect-failed:path=\(path) reason=\(reason)"
                case .unknown(let value):
                    return "install-artifact-state-unknown:value=\(value)"
                case .present, .absent:
                    return nil
                }
            }
            return inspectionFailures.isEmpty ? .reinstall : .blocked(inspectionFailures)
        }
        return document.passed ? .fresh : .blocked(document.blockers)
    }
}
