import SwiftUI

struct RuntimeUpdatePanel: View {
    @ObservedObject var viewModel: RuntimeViewModel
    @Binding var showingUpdateConfirmation: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                updateSourceCard
                bundleVerificationCard
                applyUpdateCard
            }
            .frame(maxWidth: 900, alignment: .leading)
            .padding(16)
        }
    }

    private var updateSourceCard: some View {
        updateCard(AppConstants.Labels.sectionUpdateSource) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Text(AppConstants.Labels.offlineBundle)
                        .fontWeight(.medium)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.accentColor.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    Text(AppConstants.Labels.onlineUpdate)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color(nsColor: .quaternaryLabelColor).opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                Text(AppConstants.Labels.updateSourceHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(AppConstants.Labels.onlineUpdateUnavailable)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 10) {
                    statusRow(AppConstants.Labels.selectedBundle) {
                        Text(viewModel.selectedBundlePath.isEmpty ? AppConstants.Labels.noUpdateBundleSelected : viewModel.selectedBundlePath)
                            .fontWeight(.medium)
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }
                }
                Button(AppConstants.Actions.chooseBundle) {
                    Task { await viewModel.chooseUpdateBundle() }
                }
                .disabled(viewModel.isBusy || !viewModel.capabilities.canApplyBundle)
            }
        }
    }

    private var bundleVerificationCard: some View {
        updateCard(AppConstants.Labels.sectionBundleVerification) {
            VStack(alignment: .leading, spacing: 12) {
                Text(AppConstants.Labels.bundleVerificationHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !viewModel.selectedBundleSummary.isEmpty {
                    scrollableMonospacedText(viewModel.selectedBundleSummary, maxHeight: 120)
                }
                if !viewModel.selectedBundleVerification.isEmpty {
                    scrollableMonospacedText(
                        viewModel.selectedBundleVerification,
                        maxHeight: 180,
                        foregroundColor: viewModel.selectedBundleVerified ? .green : .red
                    )
                }
                Button(AppConstants.Actions.verifyBundle) {
                    Task { await viewModel.verifySelectedBundle() }
                }
                .disabled(
                    viewModel.isBusy
                        || viewModel.selectedBundlePath.isEmpty
                        || !viewModel.capabilities.canApplyBundle
                )
            }
        }
    }

    private var applyUpdateCard: some View {
        updateCard(AppConstants.Labels.sectionApplyUpdate) {
            VStack(alignment: .leading, spacing: 12) {
                Text(AppConstants.Labels.applyUpdateHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                applyBundleActionRow
                if viewModel.isBusy {
                    Text(AppConstants.Labels.updateProgressLog)
                        .font(.caption)
                        .fontWeight(.medium)
                    scrollableMonospacedText(viewModel.logText, maxHeight: 220)
                }
            }
        }
    }

    private var applyBundleActionRow: some View {
        HStack(spacing: 12) {
            Button(AppConstants.Actions.applyBundle) {
                showingUpdateConfirmation = true
            }
            .disabled(
                viewModel.isBusy
                    || viewModel.selectedBundlePath.isEmpty
                    || !viewModel.selectedBundleVerified
                    || !viewModel.status.runtimeInstalled
                    || !viewModel.capabilities.canApplyBundle
            )

            if viewModel.isBusy {
                ProgressView()
                    .controlSize(.small)
                Text(viewModel.operationDetail.isEmpty ? viewModel.message : viewModel.operationDetail)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 420, alignment: .leading)
            }

            Spacer()
        }
    }

    private func updateCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func statusRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func scrollableMonospacedText(
        _ text: String,
        maxHeight: CGFloat,
        foregroundColor: Color = .primary
    ) -> some View {
        ScrollView {
            Text(text)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(foregroundColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .frame(maxHeight: maxHeight)
        .padding(10)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
