import SwiftUI

struct RuntimeDangerZonePanel: View {
    @ObservedObject var viewModel: RuntimeViewModel
    @Binding var showingDeleteBackupConfirmation: Bool
    @Binding var showingUninstallConfirmation: Bool
    @Binding var showingCleanUninstallConfirmation: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(AppConstants.Labels.dangerZoneSummary)
                        .font(.headline)
                    Text(AppConstants.Labels.dangerZoneDescription)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                backupDeletionCard
                destructiveOperationsCard
            }
            .frame(maxWidth: 900, alignment: .leading)
            .padding(16)
        }
    }

    private var backupDeletionCard: some View {
        advancedCard(AppConstants.Actions.deleteBackup) {
            VStack(alignment: .leading, spacing: 12) {
                Text(AppConstants.StatusText.deleteBackupConfirmation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !viewModel.backups.isEmpty {
                    Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 10) {
                        settingRow(AppConstants.Labels.rollbackBackup) {
                            Picker("", selection: $viewModel.selectedBackupPath) {
                                ForEach(viewModel.backups) { backup in
                                    Text("\(backup.name) (\(viewModel.presentationFormatter.backupSizeText(backup)))")
                                        .tag(backup.path)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: 520)
                        }
                        if let selectedBackup = viewModel.selectedBackup {
                            statusRow(AppConstants.Labels.selectedBackup) {
                                Text(selectedBackup.path)
                                    .font(.system(.body, design: .monospaced))
                                    .lineLimit(2)
                                    .truncationMode(.middle)
                                    .textSelection(.enabled)
                            }
                            statusRow(
                                AppConstants.Labels.backupSize,
                                viewModel.presentationFormatter.backupSizeText(selectedBackup)
                            )
                        }
                    }
                } else if let latestBackup = viewModel.status.latestBackup {
                    Text("\(AppConstants.Labels.latestBackup): \(latestBackup)")
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                Button(AppConstants.Actions.deleteBackup, role: .destructive) {
                    showingDeleteBackupConfirmation = true
                }
                .disabled(
                    viewModel.isBusy
                        || viewModel.selectedBackupPath.isEmpty
                        || !viewModel.capabilities.canRollback
                )
            }
        }
    }

    private var destructiveOperationsCard: some View {
        advancedCard(AppConstants.Labels.sectionDestructiveOperations) {
            VStack(alignment: .leading, spacing: 12) {
                Text(AppConstants.Labels.destructiveOperationsHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Menu(AppConstants.Actions.uninstall) {
                    Button(AppConstants.Actions.standardUninstall, role: .destructive) {
                        showingUninstallConfirmation = true
                    }
                    Button(AppConstants.Actions.cleanUninstall, role: .destructive) {
                        showingCleanUninstallConfirmation = true
                    }
                }
                .foregroundStyle(.red)
                .disabled(
                    viewModel.isBusy
                        || !viewModel.status.runtimeInstalled
                        || !viewModel.capabilities.canUninstallRuntime
                )
                .fixedSize()
            }
        }
    }

    private func advancedCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
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

    private func statusRow(_ label: String, _ value: String) -> some View {
        statusRow(label) {
            Text(value)
                .fontWeight(.medium)
        }
    }

    private func statusRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func settingRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 160, alignment: .leading)
            content()
            Spacer()
        }
    }
}
