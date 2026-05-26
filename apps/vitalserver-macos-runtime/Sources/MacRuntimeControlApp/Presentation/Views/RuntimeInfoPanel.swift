import RuntimeControl
import SwiftUI

struct RuntimeInfoPanel: View {
    @ObservedObject var viewModel: RuntimeViewModel
    @State private var showingBundledServices = false
    @State private var showingRuntimePaths = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(AppConstants.Labels.infoSummary)
                        .font(.headline)
                    Text(AppConstants.Labels.infoDescription)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                productInfoCard
                bundledServicesCard
                runtimePathsCard
            }
            .frame(maxWidth: 960, alignment: .leading)
            .padding(16)
        }
    }

    private var productInfoCard: some View {
        infoCard(AppConstants.Labels.sectionProductInfo) {
            Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 10) {
                statusRow(AppConstants.Labels.helperVersion, helperAppVersion)
                statusRow(AppConstants.Labels.vitalServerVersion, viewModel.releaseInfo.vitalServerVersion)
                statusRow(AppConstants.Labels.installedRuntimeVersion, viewModel.status.runtimeVersion ?? AppConstants.StatusText.unknown)
                statusRow(AppConstants.Labels.packageIdentifier, viewModel.installationInfo.packageIdentifier)
            }
        }
    }

    private var bundledServicesCard: some View {
        infoDisclosureCard(AppConstants.Labels.sectionBundledServices, isExpanded: $showingBundledServices) {
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 10) {
                GridRow {
                    Text(AppConstants.Labels.serviceName)
                        .fontWeight(.semibold)
                    Text(AppConstants.Labels.serviceImage)
                        .fontWeight(.semibold)
                    Text(AppConstants.Labels.serviceVersion)
                        .fontWeight(.semibold)
                }
                ForEach(bundledServices) { service in
                    GridRow {
                        Text(service.name)
                            .foregroundStyle(.secondary)
                        Text(service.image)
                            .font(.system(.body, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                        Text(service.version)
                            .fontWeight(.medium)
                    }
                }
            }
        }
    }

    private var runtimePathsCard: some View {
        infoDisclosureCard(AppConstants.Labels.sectionRuntimePaths, isExpanded: $showingRuntimePaths) {
            Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 10) {
                pathRow(AppConstants.Labels.appBundle, viewModel.installationInfo.appBundlePath)
                pathRow(AppConstants.Labels.runtimeHome, viewModel.installationInfo.runtimeHomePath)
                pathRow(AppConstants.Labels.dataDirectory, viewModel.settings.vitalFilesDirectory)
                pathRow(AppConstants.Labels.backupDirectory, viewModel.installationInfo.backupsPath)
            }
        }
    }

    private var helperAppVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
            ?? viewModel.releaseInfo.helperVersion
    }

    private var bundledServices: [RuntimeBundledServiceInfo] {
        viewModel.releaseInfo.services
    }

    private func infoDisclosureCard<Content: View>(
        _ title: String,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            DisclosureGroup(title, isExpanded: isExpanded) {
                content()
                    .padding(.top, 8)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func infoCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
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

    private func pathRow(_ label: String, _ path: String) -> some View {
        statusRow(label) {
            Text(path)
                .font(.system(.body, design: .monospaced))
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }
}
