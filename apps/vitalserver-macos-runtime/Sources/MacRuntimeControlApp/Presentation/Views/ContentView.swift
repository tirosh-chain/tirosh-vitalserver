import Foundation
import RuntimeControl
import Contracts
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var viewModel: RuntimeViewModel
    @State private var showingUpdateConfirmation = false
    @State private var showingRollbackConfirmation = false
    @State private var showingDeleteBackupConfirmation = false
    @State private var showingRepairProxyConfirmation = false
    @State private var showingRepairDatastoreConfirmation = false
    @State private var showingStartServicesConfirmation = false
    @State private var showingStopServicesConfirmation = false
    @State private var showingUninstallConfirmation = false
    @State private var showingCleanUninstallConfirmation = false
    @State private var showingApplySettingsConfirmation = false
    @State private var showingHealthDetails = false
    @State private var selectedSection = RuntimeSection.status
    @State private var hoveredServiceLink: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            sectionSelector
            Group {
                switch selectedSection {
                case .status:
                    RuntimeStatusPanel(
                        viewModel: viewModel,
                        showingHealthDetails: $showingHealthDetails
                    )
                case .settings:
                    RuntimeSettingsPanel(
                        viewModel: viewModel,
                        showingApplySettingsConfirmation: $showingApplySettingsConfirmation
                    )
                case .update:
                    RuntimeUpdatePanel(
                        viewModel: viewModel,
                        showingUpdateConfirmation: $showingUpdateConfirmation
                    )
                case .events:
                    RuntimeEventsPanel(viewModel: viewModel)
                case .test:
                    RuntimeTestPanel(viewModel: viewModel)
                case .advanced:
                    RuntimeAdvancedPanel(
                        viewModel: viewModel,
                        showingApplySettingsConfirmation: $showingApplySettingsConfirmation,
                        showingRollbackConfirmation: $showingRollbackConfirmation,
                        showingRepairProxyConfirmation: $showingRepairProxyConfirmation,
                        showingRepairDatastoreConfirmation: $showingRepairDatastoreConfirmation,
                        showingStartServicesConfirmation: $showingStartServicesConfirmation,
                        showingStopServicesConfirmation: $showingStopServicesConfirmation,
                        hoveredServiceLink: $hoveredServiceLink
                    )
                case .info:
                    RuntimeInfoPanel(viewModel: viewModel)
                case .dangerZone:
                    RuntimeDangerZonePanel(
                        viewModel: viewModel,
                        showingDeleteBackupConfirmation: $showingDeleteBackupConfirmation,
                        showingUninstallConfirmation: $showingUninstallConfirmation,
                        showingCleanUninstallConfirmation: $showingCleanUninstallConfirmation
                    )
                case .log:
                    RuntimeLogPanel(viewModel: viewModel)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(24)
        .frame(minWidth: 900, minHeight: 700)
        .alert(AppConstants.Actions.applySettings, isPresented: $showingApplySettingsConfirmation) {
            Button(AppConstants.Actions.cancel, role: .cancel) {}
            Button(AppConstants.Actions.ok) {
                Task { await viewModel.applySettings() }
            }
        } message: {
            Text(viewModel.applySettingsConfirmation)
        }
        .alert(AppConstants.Actions.applyBundle, isPresented: $showingUpdateConfirmation) {
            Button(AppConstants.Actions.cancel, role: .cancel) {}
            Button(AppConstants.Actions.startUpdate) {
                Task { await viewModel.applySelectedBundle() }
            }
        } message: {
            Text(viewModel.selectedBundleConfirmation)
        }
        .alert(AppConstants.Actions.rollback, isPresented: $showingRollbackConfirmation) {
            Button(AppConstants.Actions.cancel, role: .cancel) {}
            Button(AppConstants.Actions.startRollback, role: .destructive) {
                Task { await viewModel.rollbackRuntime() }
            }
        } message: {
            Text(viewModel.selectedBackupPath.isEmpty ? AppConstants.StatusText.latestBackupFallback : viewModel.selectedBackupPath)
        }
        .alert(AppConstants.Actions.deleteBackup, isPresented: $showingDeleteBackupConfirmation) {
            Button(AppConstants.Actions.cancel, role: .cancel) {}
            Button(AppConstants.Actions.deleteBackup, role: .destructive) {
                Task { await viewModel.deleteSelectedBackup() }
            }
        } message: {
            Text([
                AppConstants.StatusText.deleteBackupConfirmation,
                viewModel.selectedBackupPath,
            ].filter { !$0.isEmpty }.joined(separator: "\n\n"))
        }
        .alert(AppConstants.Actions.repairProxyPort, isPresented: $showingRepairProxyConfirmation) {
            Button(AppConstants.Actions.cancel, role: .cancel) {}
            Button(AppConstants.Actions.repairProxy, role: .destructive) {
                Task { await viewModel.repairProxyPort() }
            }
        } message: {
            Text(AppConstants.StatusText.repairProxyConfirmation)
        }
        .alert(AppConstants.Actions.repairDatastore, isPresented: $showingRepairDatastoreConfirmation) {
            Button(AppConstants.Actions.cancel, role: .cancel) {}
            Button(AppConstants.Actions.repairDatastore, role: .destructive) {
                Task { await viewModel.repairDatastore() }
            }
        } message: {
            Text(AppConstants.StatusText.repairDatastoreConfirmation)
        }
        .alert(AppConstants.Actions.startRuntimeServices, isPresented: $showingStartServicesConfirmation) {
            Button(AppConstants.Actions.cancel, role: .cancel) {}
            Button(AppConstants.Actions.startRuntimeServices) {
                Task { await viewModel.startRuntimeServices() }
            }
        } message: {
            Text(AppConstants.StatusText.startRuntimeServicesConfirmation)
        }
        .alert(AppConstants.Actions.stopRuntimeServices, isPresented: $showingStopServicesConfirmation) {
            Button(AppConstants.Actions.cancel, role: .cancel) {}
            Button(AppConstants.Actions.stopRuntimeServices, role: .destructive) {
                Task { await viewModel.stopRuntimeServices() }
            }
        } message: {
            Text(AppConstants.StatusText.stopRuntimeServicesConfirmation)
        }
        .alert(AppConstants.Actions.standardUninstall, isPresented: $showingUninstallConfirmation) {
            Button(AppConstants.Actions.cancel, role: .cancel) {}
            Button(AppConstants.Actions.uninstall, role: .destructive) {
                Task { await viewModel.uninstallRuntime() }
            }
        } message: {
            Text(AppConstants.StatusText.standardUninstallConfirmation)
        }
        .alert(AppConstants.Actions.cleanUninstall, isPresented: $showingCleanUninstallConfirmation) {
            Button(AppConstants.Actions.cancel, role: .cancel) {}
            Button(AppConstants.Actions.cleanUninstall, role: .destructive) {
                Task { await viewModel.uninstallRuntime(clean: true) }
            }
        } message: {
            Text(AppConstants.StatusText.cleanUninstallConfirmation)
        }
        .task {
            await viewModel.refresh()
        }
        .task {
            await pollStatus()
        }
        .task {
            await pollLogs()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(AppConstants.Product.displayName)
                .font(.title)
                .fontWeight(.semibold)
            HStack(spacing: 4) {
                Text(AppConstants.Product.poweredByPrefix)
                    .foregroundStyle(.secondary)
                Button {
                    viewModel.openTiroshWebsite()
                } label: {
                    Text(AppConstants.Product.tiroshName)
                        .underline()
                        .foregroundStyle(
                            hoveredServiceLink == AppConstants.Product.tiroshName
                                ? Color.accentColor
                                : Color.secondary
                        )
                }
                .buttonStyle(.plain)
                .onHover { isHovering in
                    hoveredServiceLink = isHovering ? AppConstants.Product.tiroshName : nil
                }
                .help(AppConstants.Product.tiroshURL)
            }
            .font(.caption)
        }
    }

    private var sectionSelector: some View {
        Picker("", selection: $selectedSection) {
            ForEach(RuntimeSection.visibleSections()) { section in
                Text(section.title).tag(section)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 760)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func pollStatus() async {
        while !Task.isCancelled {
            if !viewModel.isBusy {
                await viewModel.refreshHealthStatus()
            }
            try? await Task.sleep(nanoseconds: 5_000_000_000)
        }
    }

    private func pollLogs() async {
        while !Task.isCancelled {
            await viewModel.refreshLogsIfLive()
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }
}
