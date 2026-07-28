import Contracts
import RuntimeControl
import SwiftUI

struct RuntimeRecorderHealthSection: View {
    @ObservedObject var viewModel: RuntimeViewModel
    let vrcode: String
    let recorderSummary: RuntimeRecorderObservability?

    private let displayPolicy = RuntimeRecorderObservabilityDisplayPolicy()

    init(
        viewModel: RuntimeViewModel,
        vrcode: String,
        recorderSummary: RuntimeRecorderObservability?
    ) {
        self.viewModel = viewModel
        self.vrcode = vrcode
        self.recorderSummary = recorderSummary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Health report")
            if let detail = viewModel.recorderObservabilityDetails[vrcode] {
                observabilityDetail(detail)
            } else {
                Text("Loading health detail...")
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: vrcode) {
            async let detail: Void = viewModel.refreshRecorderObservabilityDetail(
                vrcode: vrcode
            )
            async let incidents: Void = viewModel.refreshRecorderObservabilityIncidents(
                query: displayPolicy.incidentQuery(vrcode: vrcode)
            )
            _ = await (detail, incidents)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func observabilityDetail(
        _ detail: RuntimeRecorderObservabilityDetail
    ) -> some View {
        if detail.vrcode != vrcode {
            Text("Health detail identity does not match the selected Recorder.")
                .foregroundStyle(.red)
        } else if detail.state == .unavailable {
            Text(
                "Health detail read failed: "
                    + (detail.readError ?? "No failure detail was provided.")
            )
            .foregroundStyle(.red)
        } else {
            if displayPolicy.summaryMismatch(
                detail: detail,
                summary: recorderSummary
            ) {
                Text(
                    "Recorder list and health detail report different "
                        + "support or report states."
                )
                .foregroundStyle(.red)
            }
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 9) {
                detailRow("Support", displayPolicy.detailSupportText(detail))
                detailRow("Report", displayPolicy.detailReportText(detail))
                detailRow(
                    "Last report",
                    viewModel.presentationFormatter.systemTimeText(
                        detail.report.receivedAt
                    )
                )
                detailRow(
                    "Operational health",
                    displayPolicy.operationalHealthText(detail.operationalHealth)
                )
                detailRow(
                    "Evidence health",
                    displayPolicy.evidenceHealthText(detail.evidenceHealth)
                )
                detailRow(
                    "Incident assessment",
                    displayPolicy.incidentStateText(detail.incidentState)
                )
                detailRow(
                    "Temperature",
                    displayPolicy.readingText(
                        detail.readings.temperatureCelsius,
                        suffix: " °C"
                    )
                )
                detailRow(
                    "Memory available",
                    displayPolicy.byteReadingText(
                        detail.readings.memoryAvailableBytes
                    )
                )
                detailRow(
                    "Memory total",
                    displayPolicy.byteReadingText(detail.readings.memoryTotalBytes)
                )
                detailRow(
                    "Root storage used",
                    displayPolicy.readingText(
                        detail.readings.rootUsedPercent,
                        suffix: "%"
                    )
                )
                detailRow(
                    "Data storage used",
                    displayPolicy.readingText(
                        detail.readings.dataUsedPercent,
                        suffix: "%"
                    )
                )
                detailRow(
                    "Recorder service",
                    displayPolicy.readingText(detail.readings.recorderActiveState)
                )
                detailRow(
                    "Publisher",
                    displayPolicy.readingText(detail.readings.publisherActiveState)
                )
                detailRow(
                    "Publisher buffer",
                    displayPolicy.byteReadingText(
                        detail.readings.publisherBufferBytes
                    )
                        + " / "
                        + displayPolicy.byteReadingText(
                            detail.readings.publisherBufferLimitBytes
                        )
                )
                detailRow("Profile", detail.profile.state.rawValue)
                detailRow(
                    "Boot",
                    displayPolicy.bootText(detail) {
                        viewModel.presentationFormatter.systemTimeText($0)
                    }
                )
                detailRow("Read issues", String(detail.report.readIssueCount))
            }
            currentIncidentState(detail.incidentState)
            latestReportedIssues(detail)
            telemetryReadIssues(detail)
            networkInterfaces(detail)
            incidentHistory()
        }
    }

    @ViewBuilder
    private func currentIncidentState(
        _ incidentState: RuntimeRecorderObservabilityIncidentState
    ) -> some View {
        switch incidentState.state {
        case "notReported":
            Text("Current incident assessment has not been reported by this Recorder.")
                .font(RuntimeVitalPresentationTypography.supporting)
                .foregroundStyle(.secondary)
        case "invalid":
            Text("Current incident assessment is invalid.")
                .font(RuntimeVitalPresentationTypography.supporting)
                .foregroundStyle(.red)
        case "reported":
            if incidentState.bootLoopState == "warning"
                || incidentState.bootLoopState == "critical" {
                Text(
                    "Current boot-loop assessment: "
                        + "\(incidentState.bootLoopState ?? "unknown")."
                )
                .font(RuntimeVitalPresentationTypography.supporting)
                .foregroundStyle(
                    incidentState.bootLoopState == "critical" ? Color.red : Color.orange
                )
            }
            if incidentState.repeatedUndervoltageState == "warning"
                || incidentState.repeatedUndervoltageState == "critical" {
                Text(
                    "Current repeated-undervoltage assessment: "
                        + "\(incidentState.repeatedUndervoltageState ?? "unknown")."
                )
                .font(RuntimeVitalPresentationTypography.supporting)
                .foregroundStyle(
                    incidentState.repeatedUndervoltageState == "critical"
                        ? Color.red
                        : Color.orange
                )
            }
        default:
            Text("Current incident assessment state: \(incidentState.state).")
                .font(RuntimeVitalPresentationTypography.supporting)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func latestReportedIssues(
        _ detail: RuntimeRecorderObservabilityDetail
    ) -> some View {
        if !detail.operationalHealth.issues.isEmpty {
            Text("Latest reported issues")
                .font(RuntimeVitalPresentationTypography.sectionTitle)
                .fontWeight(.semibold)
                .padding(.top, 4)
            ForEach(detail.operationalHealth.issues, id: \.code) { issue in
                VStack(alignment: .leading, spacing: 2) {
                    Text(issue.title)
                        .font(RuntimeVitalPresentationTypography.supporting)
                        .fontWeight(.semibold)
                    Text(issue.detail)
                        .font(RuntimeVitalPresentationTypography.supporting)
                }
                .foregroundStyle(
                    issue.severity == .critical ? Color.red : Color.orange
                )
            }
            if detail.report.state != "current" {
                Text(
                    "These issues came from the latest report; "
                        + "current device state is unknown."
                )
                .font(RuntimeVitalPresentationTypography.supporting)
                .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func telemetryReadIssues(
        _ detail: RuntimeRecorderObservabilityDetail
    ) -> some View {
        if !detail.readIssues.isEmpty {
            Text("Telemetry read issues")
                .font(RuntimeVitalPresentationTypography.sectionTitle)
                .fontWeight(.semibold)
                .padding(.top, 4)
        }
        ForEach(Array(detail.readIssues.enumerated()), id: \.offset) { _, issue in
            Text("\(issue.field): \(issue.state) — \(issue.detail)")
                .font(RuntimeVitalPresentationTypography.supporting)
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private func networkInterfaces(
        _ detail: RuntimeRecorderObservabilityDetail
    ) -> some View {
        if !detail.readings.networkInterfaces.isEmpty {
            Text("Network interfaces")
                .font(RuntimeVitalPresentationTypography.sectionTitle)
                .fontWeight(.semibold)
            ForEach(
                detail.readings.networkInterfaces,
                id: \.name
            ) { networkInterface in
                Text(displayPolicy.networkText(networkInterface))
                    .font(RuntimeVitalPresentationTypography.supporting)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func incidentHistory() -> some View {
        let query = displayPolicy.incidentQuery(vrcode: vrcode)
        if let page = viewModel.recorderObservabilityIncidentPage(query: query) {
            Text("Recent reported incidents")
                .font(RuntimeVitalPresentationTypography.sectionTitle)
                .fontWeight(.semibold)
                .padding(.top, 4)
            if page.state == .unavailable {
                Text(
                    "Incident history is unavailable: "
                        + (page.readError ?? "No failure detail was provided.")
                )
                .font(RuntimeVitalPresentationTypography.supporting)
                .foregroundStyle(.red)
            } else if page.incidents.isEmpty {
                Text("No reported incident records in the last 30 days.")
                    .font(RuntimeVitalPresentationTypography.supporting)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(page.incidents, id: \.incidentId) { incident in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(incident.code) — \(incident.severity)")
                            .font(RuntimeVitalPresentationTypography.supporting)
                            .fontWeight(.semibold)
                        Text(incident.summary)
                            .font(RuntimeVitalPresentationTypography.supporting)
                        Text(
                            "Reported "
                                + viewModel.presentationFormatter.systemTimeText(
                                    incident.receivedAt
                                )
                        )
                        .font(RuntimeVitalPresentationTypography.supporting)
                        .foregroundStyle(.secondary)
                    }
                    .foregroundStyle(
                        incident.severity == "critical" ? Color.red : Color.orange
                    )
                }
            }
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(RuntimeVitalPresentationTypography.sectionTitle)
            .fontWeight(.semibold)
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .fontWeight(.semibold)
                .textSelection(.enabled)
        }
        .font(RuntimeVitalPresentationTypography.detailValue)
    }
}
