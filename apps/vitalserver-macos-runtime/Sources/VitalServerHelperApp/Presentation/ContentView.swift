import Foundation
import RuntimeControl
import RuntimeCore
import RuntimeContracts
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var controller: RuntimeController
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
    @State private var selectedTab = ManagerTab.status
    @State private var hoveredServiceLink: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            tabSelector
            Group {
                switch selectedTab {
                case .status:
                    RuntimeStatusPanel(
                        controller: controller,
                        showingHealthDetails: $showingHealthDetails
                    )
                case .settings:
                    RuntimeSettingsPanel(
                        controller: controller,
                        showingApplySettingsConfirmation: $showingApplySettingsConfirmation
                    )
                case .update:
                    RuntimeUpdatePanel(
                        controller: controller,
                        showingUpdateConfirmation: $showingUpdateConfirmation
                    )
                case .advanced:
                    RuntimeAdvancedPanel(
                        controller: controller,
                        showingApplySettingsConfirmation: $showingApplySettingsConfirmation,
                        showingStartServicesConfirmation: $showingStartServicesConfirmation,
                        showingStopServicesConfirmation: $showingStopServicesConfirmation,
                        hoveredServiceLink: $hoveredServiceLink
                    )
                case .info:
                    RuntimeInfoPanel(controller: controller)
                case .dangerZone:
                    RuntimeDangerZonePanel(
                        controller: controller,
                        showingRollbackConfirmation: $showingRollbackConfirmation,
                        showingDeleteBackupConfirmation: $showingDeleteBackupConfirmation,
                        showingRepairProxyConfirmation: $showingRepairProxyConfirmation,
                        showingRepairDatastoreConfirmation: $showingRepairDatastoreConfirmation,
                        showingUninstallConfirmation: $showingUninstallConfirmation,
                        showingCleanUninstallConfirmation: $showingCleanUninstallConfirmation
                    )
                case .log:
                    RuntimeLogPanel(controller: controller)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(24)
        .frame(minWidth: 900, minHeight: 700)
        .alert(AppConstants.Actions.applySettings, isPresented: $showingApplySettingsConfirmation) {
            Button(AppConstants.Actions.cancel, role: .cancel) {}
            Button(AppConstants.Actions.ok) {
                Task { await controller.applySettings() }
            }
        } message: {
            Text(controller.applySettingsConfirmation)
        }
        .alert(AppConstants.Actions.applyBundle, isPresented: $showingUpdateConfirmation) {
            Button(AppConstants.Actions.cancel, role: .cancel) {}
            Button(AppConstants.Actions.startUpdate) {
                Task { await controller.applySelectedBundle() }
            }
        } message: {
            Text(controller.selectedBundleConfirmation)
        }
        .alert(AppConstants.Actions.rollback, isPresented: $showingRollbackConfirmation) {
            Button(AppConstants.Actions.cancel, role: .cancel) {}
            Button(AppConstants.Actions.startRollback, role: .destructive) {
                Task { await controller.rollbackRuntime() }
            }
        } message: {
            Text(controller.selectedBackupPath.isEmpty ? AppConstants.StatusText.latestBackupFallback : controller.selectedBackupPath)
        }
        .alert(AppConstants.Actions.deleteBackup, isPresented: $showingDeleteBackupConfirmation) {
            Button(AppConstants.Actions.cancel, role: .cancel) {}
            Button(AppConstants.Actions.deleteBackup, role: .destructive) {
                Task { await controller.deleteSelectedBackup() }
            }
        } message: {
            Text([
                AppConstants.StatusText.deleteBackupConfirmation,
                controller.selectedBackupPath,
            ].filter { !$0.isEmpty }.joined(separator: "\n\n"))
        }
        .alert(AppConstants.Actions.repairProxyPort, isPresented: $showingRepairProxyConfirmation) {
            Button(AppConstants.Actions.cancel, role: .cancel) {}
            Button(AppConstants.Actions.repairProxy, role: .destructive) {
                Task { await controller.repairProxyPort() }
            }
        } message: {
            Text(AppConstants.StatusText.repairProxyConfirmation)
        }
        .alert(AppConstants.Actions.repairDatastore, isPresented: $showingRepairDatastoreConfirmation) {
            Button(AppConstants.Actions.cancel, role: .cancel) {}
            Button(AppConstants.Actions.repairDatastore, role: .destructive) {
                Task { await controller.repairDatastore() }
            }
        } message: {
            Text(AppConstants.StatusText.repairDatastoreConfirmation)
        }
        .alert(AppConstants.Actions.startRuntimeServices, isPresented: $showingStartServicesConfirmation) {
            Button(AppConstants.Actions.cancel, role: .cancel) {}
            Button(AppConstants.Actions.startRuntimeServices) {
                Task { await controller.startRuntimeServices() }
            }
        } message: {
            Text(AppConstants.StatusText.startRuntimeServicesConfirmation)
        }
        .alert(AppConstants.Actions.stopRuntimeServices, isPresented: $showingStopServicesConfirmation) {
            Button(AppConstants.Actions.cancel, role: .cancel) {}
            Button(AppConstants.Actions.stopRuntimeServices, role: .destructive) {
                Task { await controller.stopRuntimeServices() }
            }
        } message: {
            Text(AppConstants.StatusText.stopRuntimeServicesConfirmation)
        }
        .alert(AppConstants.Actions.standardUninstall, isPresented: $showingUninstallConfirmation) {
            Button(AppConstants.Actions.cancel, role: .cancel) {}
            Button(AppConstants.Actions.uninstall, role: .destructive) {
                Task { await controller.uninstallRuntime() }
            }
        } message: {
            Text(AppConstants.StatusText.standardUninstallConfirmation)
        }
        .alert(AppConstants.Actions.cleanUninstall, isPresented: $showingCleanUninstallConfirmation) {
            Button(AppConstants.Actions.cancel, role: .cancel) {}
            Button(AppConstants.Actions.cleanUninstall, role: .destructive) {
                Task { await controller.uninstallRuntime(clean: true) }
            }
        } message: {
            Text(AppConstants.StatusText.cleanUninstallConfirmation)
        }
        .task {
            await controller.refresh()
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
                    controller.openTiroshWebsite()
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

    private var tabSelector: some View {
        Picker("", selection: $selectedTab) {
            ForEach(ManagerTab.allCases) { tab in
                Text(tab.title).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 640)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func pollStatus() async {
        while !Task.isCancelled {
            if !controller.isBusy {
                await controller.refreshHealthStatus()
            }
            try? await Task.sleep(nanoseconds: 5_000_000_000)
        }
    }

    private func pollLogs() async {
        while !Task.isCancelled {
            controller.refreshLogsIfLive()
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }
}
