import Foundation
import RuntimeControl
import Contracts
import AppKit
import SwiftUI
import Errors

public struct ContentView: View {
    @EnvironmentObject private var viewModel: RuntimeViewModel
    @State private var showingUpdateConfirmation = false
    @State private var showingRollbackConfirmation = false
    @State private var showingRestoreRuntimeDataBackupConfirmation = false
    @State private var showingDeleteBackupConfirmation = false
    @State private var showingDeleteRuntimeDataBackupConfirmation = false
    @State private var showingRepairProxyConfirmation = false
    @State private var showingRepairDatastoreConfirmation = false
    @State private var showingRepairVMDiskConfirmation = false
    @State private var showingRepairRuntimeServicesConfirmation = false
    @State private var showingRestartVMRuntimeConfirmation = false
    @State private var showingStartServicesConfirmation = false
    @State private var showingStopServicesConfirmation = false
    @State private var showingUninstallConfirmation = false
    @State private var showingCleanUninstallConfirmation = false
    @State private var showingApplySettingsConfirmation = false
    @State private var showingStatusRecorderDetails = true
    @State private var showingStatusResourceUsage = true
    @State private var selectedSection = RuntimeSection.status
    @State private var hoveredServiceLink: String?
    @State private var isHoveringVitalDBIcon = false
    private let statusPollingIntervalPolicy = RuntimeStatusPollingIntervalPolicy()

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            sectionSelector
            sectionContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(18)
        .frame(minWidth: 720, minHeight: 560)
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
            Text(viewModel.selectedBackupPath ?? AppConstants.StatusText.latestBackupFallback)
        }
        .alert(AppConstants.Actions.restoreBackup, isPresented: $showingRestoreRuntimeDataBackupConfirmation) {
            Button(AppConstants.Actions.cancel, role: .cancel) {}
            Button(AppConstants.Actions.restoreBackup, role: .destructive) {
                Task { await viewModel.restoreRuntimeDataBackup() }
            }
        } message: {
            Text([
                AppConstants.StatusText.restoreRuntimeDataBackupConfirmation,
                viewModel.selectedRuntimeDataBackupPath,
            ].compactMap { $0 }.joined(separator: "\n\n"))
        }
        .alert(AppConstants.Actions.deleteUpdateBackup, isPresented: $showingDeleteBackupConfirmation) {
            Button(AppConstants.Actions.cancel, role: .cancel) {}
            Button(AppConstants.Actions.deleteUpdateBackup, role: .destructive) {
                Task { await viewModel.deleteSelectedBackup() }
            }
        } message: {
            Text([
                AppConstants.StatusText.deleteBackupConfirmation,
                viewModel.selectedBackupPath,
            ].compactMap { $0 }.joined(separator: "\n\n"))
        }
        .alert(AppConstants.Actions.deleteVitalServerBackup, isPresented: $showingDeleteRuntimeDataBackupConfirmation) {
            Button(AppConstants.Actions.cancel, role: .cancel) {}
            Button(AppConstants.Actions.deleteVitalServerBackup, role: .destructive) {
                Task { await viewModel.deleteSelectedRuntimeDataBackup() }
            }
        } message: {
            Text([
                AppConstants.StatusText.deleteRuntimeDataBackupConfirmation,
                viewModel.selectedRuntimeDataBackupPath,
            ].compactMap { $0 }.joined(separator: "\n\n"))
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
        .alert(AppConstants.Actions.repairVMDisk, isPresented: $showingRepairVMDiskConfirmation) {
            Button(AppConstants.Actions.cancel, role: .cancel) {}
            Button(AppConstants.Actions.repairVMDisk, role: .destructive) {
                Task { await viewModel.repairVMDisk() }
            }
        } message: {
            Text(AppConstants.StatusText.repairVMDiskConfirmation)
        }
        .alert(AppConstants.Actions.repairRuntimeServices, isPresented: $showingRepairRuntimeServicesConfirmation) {
            Button(AppConstants.Actions.cancel, role: .cancel) {}
            Button(AppConstants.Actions.repairRuntimeServices, role: .destructive) {
                Task { await viewModel.repairRuntimeServices() }
            }
        } message: {
            Text(AppConstants.StatusText.repairRuntimeServicesConfirmation)
        }
        .alert(AppConstants.Actions.restartVMRuntime, isPresented: $showingRestartVMRuntimeConfirmation) {
            Button(AppConstants.Actions.cancel, role: .cancel) {}
            Button(AppConstants.Actions.restartVMRuntime, role: .destructive) {
                Task { await viewModel.restartVMRuntimeFromSettings() }
            }
        } message: {
            Text(AppConstants.StatusText.restartVMRuntimeConfirmation)
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
        .task(id: selectedSection) {
            await pollSelectedSection()
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            if let brandImage = RuntimeHeaderBrandAsset.image {
                Button {
                    viewModel.openVitalDBWebsite()
                } label: {
                    Image(nsImage: brandImage)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: 36, height: 36)
                        .padding(4)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(isHoveringVitalDBIcon ? Color.accentColor.opacity(0.10) : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(isHoveringVitalDBIcon ? Color.accentColor.opacity(0.35) : Color.clear, lineWidth: 1)
                        )
                        .scaleEffect(isHoveringVitalDBIcon ? 1.04 : 1)
                        .accessibilityLabel(AppConstants.Product.vitalDBName)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .onHover { isHovering in
                    isHoveringVitalDBIcon = isHovering
                    if isHovering {
                        NSCursor.pointingHand.set()
                    } else {
                        NSCursor.arrow.set()
                    }
                }
                .help(AppConstants.Product.vitalDBURL)
            }
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
    }

    private var sectionSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                HStack(spacing: 4) {
                    ForEach(RuntimeSection.primarySections()) { section in
                        sectionButton(section)
                    }
                }
                .padding(3)
                .background(Color(nsColor: .controlColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                HStack(spacing: 6) {
                    ForEach(RuntimeSection.utilitySections()) { section in
                        sectionButton(section)
                    }
                    overflowSectionMenu
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    @ViewBuilder
    private var sectionContent: some View {
        if selectedSection == .log {
            RuntimeLogPanel(viewModel: viewModel)
        } else {
            ScrollView(.vertical) {
                selectedSectionContent
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.bottom, 8)
            }
        }
    }

    @ViewBuilder
    private var selectedSectionContent: some View {
        switch selectedSection {
        case .status:
            RuntimeStatusPanel(
                viewModel: viewModel,
                showingRecorderDetails: $showingStatusRecorderDetails,
                showingResourceUsage: $showingStatusResourceUsage
            )
        case .recorders:
            RuntimeRecordersPanel(viewModel: viewModel)
        case .beds:
            RuntimeBedsPanel(viewModel: viewModel)
        case .observability:
            RuntimeObservabilityPanel(viewModel: viewModel)
        case .log:
            RuntimeLogPanel(viewModel: viewModel)
        case .settings:
            RuntimeSettingsPanel(
                viewModel: viewModel,
                showingApplySettingsConfirmation: $showingApplySettingsConfirmation,
                showingRestartVMRuntimeConfirmation: $showingRestartVMRuntimeConfirmation
            )
        case .update:
            RuntimeUpdatePanel(
                viewModel: viewModel,
                showingUpdateConfirmation: $showingUpdateConfirmation
            )
        case .info:
            RuntimeInfoPanel(viewModel: viewModel)
        case .advanced:
            RuntimeAdvancedPanel(
                viewModel: viewModel,
                showingApplySettingsConfirmation: $showingApplySettingsConfirmation,
                showingRollbackConfirmation: $showingRollbackConfirmation,
                showingRestoreRuntimeDataBackupConfirmation: $showingRestoreRuntimeDataBackupConfirmation,
                showingRepairProxyConfirmation: $showingRepairProxyConfirmation,
                showingRepairDatastoreConfirmation: $showingRepairDatastoreConfirmation,
                showingRepairVMDiskConfirmation: $showingRepairVMDiskConfirmation,
                showingRepairRuntimeServicesConfirmation: $showingRepairRuntimeServicesConfirmation,
                showingStartServicesConfirmation: $showingStartServicesConfirmation,
                showingStopServicesConfirmation: $showingStopServicesConfirmation,
                hoveredServiceLink: $hoveredServiceLink
            )
        case .test:
            RuntimeTestPanel(viewModel: viewModel)
        case .dangerZone:
            RuntimeDangerZonePanel(
                viewModel: viewModel,
                showingDeleteBackupConfirmation: $showingDeleteBackupConfirmation,
                showingDeleteRuntimeDataBackupConfirmation: $showingDeleteRuntimeDataBackupConfirmation,
                showingUninstallConfirmation: $showingUninstallConfirmation,
                showingCleanUninstallConfirmation: $showingCleanUninstallConfirmation
            )
        }
    }

    private func sectionButton(_ section: RuntimeSection) -> some View {
        Button {
            selectedSection = section
        } label: {
            Text(section.title)
                .font(.system(size: 13, weight: selectedSection == section ? .semibold : .regular))
                .lineLimit(1)
                .padding(.horizontal, 13)
                .padding(.vertical, 6)
                .frame(minWidth: 66)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(selectedSection == section ? Color.primary : Color.secondary)
        .background(sectionButtonBackground(isSelected: selectedSection == section))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var overflowSectionMenu: some View {
        Menu {
            ForEach(RuntimeSection.overflowSections()) { section in
                Button {
                    selectedSection = section
                } label: {
                    Text(section.title)
                }
            }
        } label: {
            Text(AppConstants.Labels.sectionMore)
                .font(.system(
                    size: 13,
                    weight: RuntimeSection.sectionIsInOverflow(selectedSection) ? .semibold : .regular
                ))
                .lineLimit(1)
                .padding(.horizontal, 13)
                .padding(.vertical, 6)
                .frame(minWidth: 66)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
        .foregroundStyle(RuntimeSection.sectionIsInOverflow(selectedSection) ? Color.primary : Color.secondary)
        .background(sectionButtonBackground(isSelected: RuntimeSection.sectionIsInOverflow(selectedSection)))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func sectionButtonBackground(isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(isSelected ? Color(nsColor: .controlBackgroundColor) : Color.clear)
            .shadow(color: isSelected ? Color.black.opacity(0.10) : Color.clear, radius: 1, y: 1)
    }

    private func pollStatus() async {
        while !Task.isCancelled {
            await viewModel.refreshHealthStatus()
            try? await Task.sleep(nanoseconds: statusPollingIntervalPolicy.statusPollingIntervalNanoseconds(
                status: viewModel.status
            ))
        }
    }

    private func pollLogs() async {
        while !Task.isCancelled {
            if selectedSection == .log {
                await viewModel.refreshLogsIfLive()
            } else if selectedSection == .update, viewModel.shouldShowUpdateProgress {
                await viewModel.refreshLogsIfLive()
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }

    private func pollSelectedSection() async {
        while !Task.isCancelled {
            await refreshSelectedSection()
            try? await Task.sleep(nanoseconds: 5_000_000_000)
        }
    }

    private func refreshSelectedSection() async {
        switch selectedSection {
        case .recorders, .beds:
            await viewModel.refreshVitalRecorders()
        case .observability:
            await viewModel.refreshRuntimeEvents()
            await viewModel.refreshVitalRecorders()
        default:
            break
        }
    }
}

private enum RuntimeHeaderBrandAsset {
    @MainActor
    static var image: NSImage? {
        loadImage()
    }

    private static func loadImage() -> NSImage? {
        if let bundledURL = Bundle.main.url(forResource: "vitaldb", withExtension: "png"),
           let image = NSImage(contentsOf: bundledURL) {
            return image
        }
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../../../Support/App/vitaldb.png")
            .standardizedFileURL
        return NSImage(contentsOf: sourceURL)
    }
}
