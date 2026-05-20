import SwiftUI

struct ContentView: View {
    @StateObject private var controller = RuntimeController()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            statusGrid
            actionBar
            logPanel
        }
        .padding(24)
        .task {
            await controller.refresh()
        }
        .task {
            await pollStatus()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(AppConstants.Product.displayName)
                .font(.title)
                .fontWeight(.semibold)
            Text(AppConstants.Product.subtitle)
                .foregroundStyle(.secondary)
        }
    }

    private var statusGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 12) {
            statusRow(
                AppConstants.Labels.runtime,
                controller.status.runtimeInstalled
                    ? AppConstants.StatusText.installed
                    : AppConstants.StatusText.notInstalled
            )
            statusRow(
                AppConstants.Labels.vmService,
                controller.status.vmServiceLoaded
                    ? AppConstants.StatusText.loaded
                    : AppConstants.StatusText.notLoaded
            )
            statusRow(
                AppConstants.Labels.proxyService,
                controller.status.proxyServiceLoaded
                    ? AppConstants.StatusText.loaded
                    : AppConstants.StatusText.notLoaded
            )
            statusRow(AppConstants.Labels.proxyPort, String(controller.status.proxyPort))
            statusRow(AppConstants.Labels.vmIP, controller.status.vmIP ?? AppConstants.StatusText.waiting)
            statusRow(AppConstants.Labels.guestHTTP, controller.status.guestHTTP ?? AppConstants.StatusText.notChecked)
            statusRow(AppConstants.Labels.hostProxy, controller.status.hostProxyHTTP ?? AppConstants.StatusText.notChecked)
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func statusRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .fontWeight(.medium)
        }
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            Button(AppConstants.Actions.healthCheck) {
                Task { await controller.healthCheck() }
            }
            Menu(AppConstants.Actions.open) {
                Button(AppConstants.Actions.openVitalServer) {
                    controller.openVitalServer()
                }
                Button(AppConstants.Actions.openRedisUI) {
                    controller.openRedisUI()
                }
                Button(AppConstants.Actions.openSwagger) {
                    controller.openSwagger()
                }
            }
            Button(AppConstants.Actions.uninstall) {
                Task { await controller.uninstallRuntime() }
            }
            .foregroundStyle(.red)
            .disabled(controller.isBusy || !controller.status.runtimeInstalled)
            Spacer()
            Button(AppConstants.Actions.refresh) {
                Task { await controller.refresh() }
            }
            .disabled(controller.isBusy)
        }
    }

    private var logPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(AppConstants.Labels.log)
                .font(.headline)
            ScrollView {
                Text(controller.message)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(minHeight: 120)
            .padding(12)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func pollStatus() async {
        while !Task.isCancelled {
            if !controller.isBusy {
                await controller.refreshHealthStatus()
            }
            try? await Task.sleep(nanoseconds: 5_000_000_000)
        }
    }
}
