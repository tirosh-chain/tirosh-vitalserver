import SwiftUI

struct InstallerView: View {
    @StateObject private var controller = InstallerController()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                progressPanel
                installLocationsPanel
                settingsPanel
                actionBar
                logPanel
            }
            .padding(24)
        }
        .frame(minWidth: 760, idealWidth: 820, minHeight: 720, idealHeight: 760)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Configure & Install Tirosh VitalServer")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Set the runtime policy before installing the product package.")
                .foregroundStyle(.secondary)
        }
    }

    private var settingsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Runtime Settings")
                .font(.headline)
            Stepper(value: $controller.settings.cpuCount, in: 7...64) {
                labeledValue("CPU", "\(controller.settings.cpuCount)")
            }
            Stepper(value: $controller.settings.memoryGiB, in: 4...64, step: 4) {
                labeledValue("Memory", "\(controller.settings.memoryGiB) GiB")
            }
            Stepper(value: $controller.settings.diskGiB, in: 32...512, step: 16) {
                labeledValue("VM disk", "\(controller.settings.diskGiB) GiB")
            }
            Picker("Network", selection: $controller.settings.networkMode) {
                Text("Shared").tag("shared")
                Text("Bridged").tag("bridged")
            }
            .frame(maxWidth: 280, alignment: .leading)
            Stepper(value: $controller.settings.proxyPort, in: 1...65_535) {
                labeledValue("Proxy port", "\(controller.settings.proxyPort)")
            }
            settingRow("Vital files directory") {
                TextField("Vital files directory", text: $controller.settings.vitalFilesDirectory)
                    .textFieldStyle(.roundedBorder)
                Button("Choose") {
                    controller.chooseVitalFilesDirectory()
                }
            }
            settingRow("VM hostname") {
                TextField("VM hostname", text: $controller.settings.vmHostname)
                    .textFieldStyle(.roundedBorder)
            }
            settingRow("Public host") {
                TextField("Public host", text: $controller.settings.publicHost)
                    .textFieldStyle(.roundedBorder)
            }
            Stepper(value: $controller.settings.publicPort, in: 1...65_535) {
                labeledValue("Public port", "\(controller.settings.publicPort)")
            }
            settingRow("Admin password") {
                SecureField("Admin password", text: $controller.settings.adminPassword)
                    .textFieldStyle(.roundedBorder)
            }
            Toggle("Start after install", isOn: $controller.settings.startAfterInstall)
            Toggle("Start on boot", isOn: $controller.settings.startOnBoot)
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var actionBar: some View {
        HStack {
            Button("Validate") {
                controller.revalidate()
            }
            .disabled(controller.isBusy)
            Button("Open Install Log") {
                controller.openInstallLog()
            }
            Spacer()
            Button("Install") {
                Task { await controller.install() }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(controller.isBusy)
        }
    }

    private var progressPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(controller.stage)
                    .fontWeight(.semibold)
                Spacer()
                if controller.isBusy {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            if !controller.validationIssues.isEmpty {
                ForEach(controller.validationIssues, id: \.self) { issue in
                    Text(issue)
                        .foregroundStyle(.red)
                }
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var installLocationsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PKG Install Locations")
                .font(.headline)
            locationRow("Manager app", "/Applications/Tirosh VitalServer Manager.app")
            locationRow("Runtime home", "/Library/Application Support/TiroshVitalServer/vm")
            locationRow("Nginx bundle", "/Library/Application Support/TiroshVitalServer/nginx")
            locationRow("Runtime tools", "/usr/local/bin/vitalserver-vm")
            locationRow("LaunchDaemons", "/Library/LaunchDaemons/com.tirosh.vitalserver-*.plist")
            locationRow("Install log", "/Library/Application Support/TiroshVitalServer/logs/install.log")
        }
        .padding(16)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var logPanel: some View {
        ScrollView {
            Text(controller.message)
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .frame(minHeight: 90)
        .padding(12)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func labeledValue(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .frame(width: 160, alignment: .leading)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }

    private func settingRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .frame(width: 160, alignment: .leading)
            content()
        }
    }

    private func locationRow(_ label: String, _ path: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 130, alignment: .leading)
            Text(path)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}
