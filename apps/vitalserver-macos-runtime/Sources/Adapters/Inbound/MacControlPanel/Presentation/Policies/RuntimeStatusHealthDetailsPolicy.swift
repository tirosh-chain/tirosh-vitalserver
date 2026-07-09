import Foundation
import Contracts
import RuntimeControl
import Errors

public protocol RuntimeStatusHealthDetailsVocabulary: RuntimeStatusVMStateVocabulary,
    RuntimeStatusHTTPValueVocabulary,
    RuntimeStatusServiceValueVocabulary,
    RuntimeStatusContainerStateVocabulary {
    var runtimeInstallationLabel: String { get }
    var vmStateLabel: String { get }
    var vmErrorsLabel: String { get }
    var failureReasonsLabel: String { get }
    var statusReadIssuesLabel: String { get }
    var vmIPAddressLabel: String { get }
    var vitalServerName: String { get }
    var hostProxyName: String { get }
    var redisName: String { get }
    var vitalDBObserverLabel: String { get }
    var guestProductServicesLabel: String { get }
    var recorderIngressQueueLabel: String { get }
    var watchdogLabel: String { get }
    var waitingText: String { get }
    var guestStateStaleText: String { get }

    func installStateText(_ state: RuntimeFileState) -> String
    func recorderIngressStatusReadStateText(_ state: RuntimeRecorderIngressStatusReadState) -> String
    func vmErrorText(_ error: RuntimeVMError) -> String
    func domainErrorText(_ reason: RuntimeFailureReason) -> String
}

public struct RuntimeStatusHealthDetailValue: Equatable, Sendable {
    public let text: String
    public let severity: RuntimeStatusReachabilityPolicy.Severity
    public let uptimeText: String?

    public init(
        text: String,
        severity: RuntimeStatusReachabilityPolicy.Severity,
        uptimeText: String?
    ) {
        self.text = text
        self.severity = severity
        self.uptimeText = uptimeText
    }
}

public struct RuntimeStatusHealthDetailItem: Equatable, Sendable {
    public let label: String
    public let value: RuntimeStatusHealthDetailValue

    public init(label: String, value: RuntimeStatusHealthDetailValue) {
        self.label = label
        self.value = value
    }
}

public struct RuntimeStatusHealthDetailsPolicy {
    private let reachabilityPolicy = RuntimeStatusReachabilityPolicy()
    private let reachabilityLabelPolicy: RuntimeStatusReachabilityLabelPolicy
    private let vmStatePolicy: RuntimeStatusVMStatePolicy
    private let serviceValuePolicy: RuntimeStatusServiceValuePolicy
    private let httpValuePolicy: RuntimeStatusHTTPValuePolicy
    private let guestReadinessPolicy = RuntimeStatusGuestReadinessPresentationPolicy()
    private let vocabulary: any RuntimeStatusHealthDetailsVocabulary

    public init(vocabulary: any RuntimeStatusHealthDetailsVocabulary) {
        self.vocabulary = vocabulary
        self.reachabilityLabelPolicy = RuntimeStatusReachabilityLabelPolicy(vocabulary: vocabulary)
        self.vmStatePolicy = RuntimeStatusVMStatePolicy(vocabulary: vocabulary)
        self.serviceValuePolicy = RuntimeStatusServiceValuePolicy(vocabulary: vocabulary)
        self.httpValuePolicy = RuntimeStatusHTTPValuePolicy(vocabulary: vocabulary)
    }

    public func healthDetails(
        status: RuntimeStatus,
        operationState: RuntimeOperationState,
        recorderIngressStatusRead: RuntimeRecorderIngressStatusReadResult?,
        now: Date
    ) -> [RuntimeStatusHealthDetailItem] {
        makeHealthDetails(
            status: status,
            operationState: operationState,
            recorderIngressStatusRead: recorderIngressStatusRead,
            now: now
        )
    }

    private func makeHealthDetails(
        status: RuntimeStatus,
        operationState: RuntimeOperationState,
        recorderIngressStatusRead: RuntimeRecorderIngressStatusReadResult?,
        now _: Date
    ) -> [RuntimeStatusHealthDetailItem] {
        var items = [
            RuntimeStatusHealthDetailItem(
                label: vocabulary.runtimeInstallationLabel,
                value: value(
                    vocabulary.installStateText(
                        status.runtimeInstallationState
                            ?? RuntimeFileState.unknown("runtime-installation-state-unavailable")
                    ),
                    installStateSeverity(
                        status.runtimeInstallationState
                            ?? RuntimeFileState.unknown("runtime-installation-state-unavailable")
                    )
                )
            ),
            RuntimeStatusHealthDetailItem(
                label: vocabulary.vmStateLabel,
                value: value(vmStatePolicy.vmStateValue(status.vmState))
            ),
        ]
        if let vmErrors = status.vmErrors, !vmErrors.isEmpty {
            items.append(RuntimeStatusHealthDetailItem(
                label: vocabulary.vmErrorsLabel,
                value: value(
                    vmErrors.map(vocabulary.vmErrorText).joined(separator: ", "),
                    guestReadinessPolicy.vmErrorSeverity(status: status, vmErrors: vmErrors)
                )
            ))
        }
        if !status.failureReasons.isEmpty {
            items.append(RuntimeStatusHealthDetailItem(
                label: vocabulary.failureReasonsLabel,
                value: value(
                    status.failureReasons.map(vocabulary.domainErrorText).joined(separator: ", "),
                    status.failureReasons.contains { $0.domainSeverity == .critical } ? .critical : .warning
                )
            ))
        }
        if !status.readIssues.isEmpty {
            items.append(RuntimeStatusHealthDetailItem(
                label: vocabulary.statusReadIssuesLabel,
                value: value(
                    status.readIssues.map { "\($0.source): \($0.message)" }.joined(separator: ", "),
                    .warning
                )
            ))
        }
        items.append(contentsOf: [
            RuntimeStatusHealthDetailItem(
                label: vocabulary.vmIPAddressLabel,
                value: value(
                    status.vmIP ?? guestReadinessPolicy.pendingGuestStateText(
                        status: status,
                        waitingText: vocabulary.waitingText,
                        staleText: vocabulary.guestStateStaleText
                    ),
                    status.vmServiceState == .loaded && status.vmIP != nil ? .healthy : .warning
                )
            ),
            RuntimeStatusHealthDetailItem(
                label: vocabulary.vitalServerName,
                value: value(guestHTTPValue(status: status, operationState: operationState))
            ),
            RuntimeStatusHealthDetailItem(
                label: vocabulary.hostProxyName,
                value: RuntimeStatusHealthDetailValue(
                    text: reachabilityLabelPolicy.serviceReachabilityLabel(status.hostProxyHTTP),
                    severity: status.proxyServiceState == .loaded && reachabilityPolicy.isSuccessfulHTTPStatus(status.hostProxyHTTP)
                        ? .healthy
                        : .warning,
                    uptimeText: nil
                )
            ),
        ])
        items.append(contentsOf: guestServiceHealthDetails(status: status))
        if let probeErrorItem = guestStackProbeErrorHealthDetail(status) {
            items.append(probeErrorItem)
        }
        items.append(contentsOf: [
            RuntimeStatusHealthDetailItem(
                label: vocabulary.recorderIngressQueueLabel,
                value: recorderIngressQueueValue(recorderIngressStatusRead: recorderIngressStatusRead)
            ),
            RuntimeStatusHealthDetailItem(
                label: vocabulary.watchdogLabel,
                value: value(serviceValuePolicy.serviceValue(
                    state: status.watchdogServiceState
                ))
            ),
        ])
        return items
    }

    private func guestStackProbeErrorHealthDetail(_ status: RuntimeStatus) -> RuntimeStatusHealthDetailItem? {
        guard !status.guestStackProbeErrors.isEmpty else {
            return nil
        }
        return RuntimeStatusHealthDetailItem(
            label: "\(vocabulary.guestProductServicesLabel) probes",
            value: value(
                status.guestStackProbeErrors
                    .map { "\($0.source): \($0.message)" }
                    .joined(separator: ", "),
                .warning
            )
        )
    }

    private func guestHTTPValue(
        status: RuntimeStatus,
        operationState: RuntimeOperationState
    ) -> RuntimeStatusHTTPValue {
        let computedValue = httpValuePolicy.httpValue(status.guestHTTP, uptimeText: nil)
        return guestReadinessPolicy.guestHTTPValue(
            status: status,
            operationState: operationState,
            computedValue: computedValue,
            waitingText: vocabulary.waitingText,
            staleText: vocabulary.guestStateStaleText
        )
    }

    private func guestServiceHealthDetails(status: RuntimeStatus) -> [RuntimeStatusHealthDetailItem] {
        switch status.guestServicesReadState ?? .unavailable {
        case .unavailable:
            return [
                RuntimeStatusHealthDetailItem(
                    label: vocabulary.guestProductServicesLabel,
                    value: value(vocabulary.unavailableText, .warning)
                ),
            ]
        case .failed:
            return [
                RuntimeStatusHealthDetailItem(
                    label: vocabulary.guestProductServicesLabel,
                    value: value(status.guestServicesReadError ?? vocabulary.failedText, .warning)
                ),
            ]
        case .loaded:
            return orderedGuestServiceStatuses(status)
                .filter { $0.service != "redis-relay" }
                .map { serviceStatus in
                    let resource = status.guestServiceResources.first { $0.service == serviceStatus.service }
                    let readIssue = status.guestServiceResourceReadIssues.first { $0.service == serviceStatus.service }
                    return RuntimeStatusHealthDetailItem(
                        label: "\(vocabulary.guestProductServicesLabel): \(serviceStatus.service)",
                        value: RuntimeStatusHealthDetailValue(
                            text: guestServiceText(serviceStatus, resource: resource, readIssue: readIssue),
                            severity: guestServiceSeverity(serviceStatus, readIssue: readIssue),
                            uptimeText: nil
                        )
                    )
                }
        }
    }

    private func orderedGuestServiceStatuses(
        _ status: RuntimeStatus
    ) -> [RuntimeGuestControlServiceStatus] {
        var statusesByService: [String: RuntimeGuestControlServiceStatus] = [:]
        for serviceStatus in status.guestServiceStatuses where statusesByService[serviceStatus.service] == nil {
            statusesByService[serviceStatus.service] = serviceStatus
        }
        let orderedServices = status.guestServices ?? []
        var orderedStatuses = orderedServices.compactMap { statusesByService[$0] }
        let orderedServiceSet = Set(orderedServices)
        orderedStatuses.append(contentsOf: status.guestServiceStatuses
            .filter { !orderedServiceSet.contains($0.service) }
            .sorted { $0.service < $1.service })
        return orderedStatuses
    }

    private func guestServiceText(
        _ serviceStatus: RuntimeGuestControlServiceStatus,
        resource: RuntimeGuestServiceResource?,
        readIssue: RuntimeGuestServiceResourceReadIssue?
    ) -> String {
        if let readIssue {
            return "Resource read failed: \(readIssue.message)"
        }
        var parts: [String] = []
        if !serviceStatus.health.isEmpty, serviceStatus.health != "unknown" {
            parts.append(vocabulary.containerHealthText(serviceStatus.health))
        } else if !serviceStatus.state.isEmpty {
            parts.append(vocabulary.containerStateText(serviceStatus.state))
        } else {
            parts.append(vocabulary.notReportedText)
        }
        if let resource {
            parts.append("spec \(resource.spec.state)")
            if let desiredState = resource.spec.desiredState {
                parts.append("desired \(desiredState)")
            }
            parts.append("status \(resource.status.state)")
            if let observedState = resource.status.observedState {
                parts.append("observed \(observedState)")
            }
            if let readError = resource.status.readError {
                parts.append("status read failed \(readError.kind): \(readError.message)")
            }
            let conditionText = resource.conditions
                .map { "\($0.type)=\($0.status) \($0.reason): \($0.message)" }
                .joined(separator: "; ")
            if !conditionText.isEmpty {
                parts.append("conditions \(conditionText)")
            }
            if let lastOperationId = resource.lastOperationId {
                parts.append("last operation \(lastOperationId)")
            }
        }
        return parts.joined(separator: " | ")
    }

    private func guestServiceSeverity(
        _ serviceStatus: RuntimeGuestControlServiceStatus,
        readIssue: RuntimeGuestServiceResourceReadIssue?
    ) -> RuntimeStatusReachabilityPolicy.Severity {
        if readIssue != nil {
            return .warning
        }
        switch serviceStatus.health.lowercased() {
        case "healthy":
            return .healthy
        case "unhealthy":
            return .warning
        default:
            switch serviceStatus.state.lowercased() {
            case "running":
                return .healthy
            case "exited", "dead", "failed":
                return .warning
            default:
                return .neutral
            }
        }
    }

    public func recorderIngressQueueValue(
        recorderIngressStatusRead: RuntimeRecorderIngressStatusReadResult?
    ) -> RuntimeStatusHealthDetailValue {
        guard let recorderIngressStatusRead else {
            return value(vocabulary.notReportedText, .neutral)
        }
        guard recorderIngressStatusRead.readState == .loaded else {
            return value(
                vocabulary.recorderIngressStatusReadStateText(recorderIngressStatusRead.readState),
                .warning
            )
        }
        guard let status = recorderIngressStatusRead.document else {
            return value(vocabulary.notReportedText, .neutral)
        }
        guard status.spool != nil || status.replay != nil else {
            return value(vocabulary.notReportedText, .neutral)
        }

        let spool = status.spool
        let replay = status.replay
        if spool?.status == "disabled" && (replay?.status == nil || replay?.status == "disabled") {
            return value("disabled", .neutral)
        }

        let pending = firstPresent(spool?.pendingItems, replay?.pendingItems)
        let inFlight = replay?.inFlightItems
        let pendingBytes = spool?.pendingBytes
        let writeFailures = spool?.writeFailures
        let rejectedEvents = spool?.rejectedEvents
        let retryableFailures = replay?.retryableFailures
        let deadLetteredEvents = replay?.deadLetteredEvents
        let lastFailure = lastFailureReason(spool: spool, replay: replay)
        let isMirrorOnly = spool?.mode == "mirror_spool"
            && (replay?.status == nil || replay?.status == "disabled")

        let severity: RuntimeStatusReachabilityPolicy.Severity
        let stateText: String
        if (writeFailures ?? 0) > 0 || (deadLetteredEvents ?? 0) > 0 {
            severity = .critical
            stateText = spool?.status == "failed" ? "failed" : "degraded"
        } else if (rejectedEvents ?? 0) > 0 || (retryableFailures ?? 0) > 0 {
            severity = .warning
            stateText = "degraded"
        } else if isMirrorOnly {
            severity = .neutral
            stateText = "mirroring"
        } else if (pending ?? 0) > 0 || (inFlight ?? 0) > 0 {
            severity = .warning
            stateText = "draining"
        } else {
            severity = .healthy
            stateText = "healthy"
        }

        var parts = [stateText]
        if let pending, stateText == "healthy" || pending > 0 {
            parts.append("\(pending) pending")
        }
        if let pendingBytes, pendingBytes > 0 {
            parts.append(formatBytes(pendingBytes))
        }
        if let inFlight, inFlight > 0 {
            parts.append("\(inFlight) in flight")
        }
        if let oldest = spool?.oldestPendingAgeSeconds {
            parts.append("oldest \(durationText(oldest))")
        }
        if let lag = replay?.replayLagSeconds {
            parts.append("replay lag \(durationText(lag))")
        }
        if isMirrorOnly {
            parts.append("replay disabled")
        }
        if let rejectedEvents, rejectedEvents > 0 {
            parts.append("\(rejectedEvents) rejected")
        }
        if let retryableFailures, retryableFailures > 0 {
            parts.append("\(retryableFailures) retryable failures")
        }
        if let deadLetteredEvents, deadLetteredEvents > 0 {
            parts.append("\(deadLetteredEvents) dead letters")
        }
        if let writeFailures, writeFailures > 0 {
            parts.append("\(writeFailures) write failures")
        }
        if let lastFailure {
            parts.append("last failure \(lastFailure)")
        }

        return value(parts.joined(separator: ", "), severity)
    }

    private func firstPresent(_ left: Int?, _ right: Int?) -> Int? {
        if let left {
            return left
        }
        return right
    }

    private func lastFailureReason(
        spool: RuntimeRecorderIngressSpoolStatus?,
        replay: RuntimeRecorderIngressReplayStatus?
    ) -> String? {
        if let reason = replay?.lastFailure?.reason, !reason.isEmpty {
            return reason
        }
        if let reason = spool?.lastFailure?.reason, !reason.isEmpty {
            return reason
        }
        if let message = replay?.lastFailure?.message, !message.isEmpty {
            return message
        }
        if let message = spool?.lastFailure?.message, !message.isEmpty {
            return message
        }
        return nil
    }

    private func durationText(_ seconds: Int) -> String {
        let bounded = max(0, seconds)
        if bounded < 60 {
            return "\(bounded)s"
        }
        let minutes = bounded / 60
        let remainder = bounded % 60
        if minutes < 60 {
            return remainder == 0 ? "\(minutes)m" : "\(minutes)m \(remainder)s"
        }
        let hours = minutes / 60
        let minuteRemainder = minutes % 60
        return minuteRemainder == 0 ? "\(hours)h" : "\(hours)h \(minuteRemainder)m"
    }

    private func formatBytes(_ bytes: Int) -> String {
        if bytes <= 0 {
            return "0 bytes"
        }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    private func value(
        _ text: String,
        _ severity: RuntimeStatusReachabilityPolicy.Severity
    ) -> RuntimeStatusHealthDetailValue {
        RuntimeStatusHealthDetailValue(text: text, severity: severity, uptimeText: nil)
    }

    private func value(_ value: RuntimeStatusVMStateValue) -> RuntimeStatusHealthDetailValue {
        RuntimeStatusHealthDetailValue(
            text: value.text,
            severity: value.severity,
            uptimeText: value.uptimeText
        )
    }

    private func value(_ value: RuntimeStatusServiceValue) -> RuntimeStatusHealthDetailValue {
        RuntimeStatusHealthDetailValue(
            text: value.text,
            severity: value.severity,
            uptimeText: value.uptimeText
        )
    }

    private func value(_ value: RuntimeStatusHTTPValue) -> RuntimeStatusHealthDetailValue {
        RuntimeStatusHealthDetailValue(
            text: value.text,
            severity: value.severity,
            uptimeText: value.uptimeText
        )
    }

    private func installStateSeverity(_ state: RuntimeFileState) -> RuntimeStatusReachabilityPolicy.Severity {
        switch state {
        case .executable:
            .healthy
        case .missing:
            .warning
        case .present, .inspectFailed, .unknown:
            .critical
        }
    }
}
