import Foundation

enum RuntimeProfile: String, CaseIterable, Identifiable {
    case recommended
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recommended:
            AppConstants.InstallWizard.recommendedProfile
        case .custom:
            AppConstants.InstallWizard.customProfile
        }
    }

    var description: String {
        switch self {
        case .recommended:
            "Mac mini 운영 기본값입니다."
        case .custom:
            "다음 단계에서 CPU, 메모리, 디스크를 직접 조정합니다."
        }
    }

    var defaults: RuntimeResources {
        switch self {
        case .recommended:
            RuntimeResources(cpuCount: 8, memoryGiB: 8, diskGiB: 64)
        case .custom:
            RuntimeResources(cpuCount: 8, memoryGiB: 8, diskGiB: 64)
        }
    }

    var specLine: String {
        switch self {
        case .recommended:
            defaults.summary
        case .custom:
            "사용자 지정"
        }
    }
}

struct RuntimeResources: Equatable {
    var cpuCount: Int
    var memoryGiB: Int
    var diskGiB: Int

    var summary: String {
        "\(cpuCount) vCPU / \(memoryGiB) GB RAM / \(diskGiB) GB disk"
    }
}

enum RuntimeNetworkMode: String, CaseIterable, Identifiable {
    case shared
    case bridged

    var id: String { rawValue }

    var title: String {
        switch self {
        case .shared:
            AppConstants.InstallWizard.sharedNetwork
        case .bridged:
            AppConstants.InstallWizard.bridgedNetwork
        }
    }
}

struct InstallSettings: Equatable {
    var profile: RuntimeProfile = .recommended
    var resources = RuntimeProfile.recommended.defaults
    var networkMode: RuntimeNetworkMode = .shared
    var proxyPort = 80
    var vitalFilesDirectory = "/Library/Application Support/TiroshVitalServer/vm/data/vital-files"
    var adminPassword = ""
    var adminPasswordConfirmation = ""
    var vmHostname = "tirosh-vitalserver"
    var publicHost = ""
    var publicPort = 80
    var startAfterInstall = true
    var startOnBoot = true

    mutating func applyProfileDefaults() {
        guard profile != .custom else {
            return
        }
        resources = profile.defaults
    }

    var summaryLines: [String] {
        [
            "Profile: \(profile.title)",
            "CPU: \(resources.cpuCount) vCPU",
            "Memory: \(resources.memoryGiB) GB",
            "Disk: \(resources.diskGiB) GB",
            "Network: \(networkMode.title)",
            "Host proxy port: \(proxyPort)",
            "Vital files directory: \(vitalFilesDirectory)",
            "Admin password: \(adminPassword.isEmpty ? "Not set" : "Configured")",
            "VM hostname: \(vmHostname)",
            "Public host: \(publicHost.isEmpty ? "Auto" : publicHost)",
            "Public port: \(publicHost.isEmpty ? "Auto" : "\(publicPort)")",
            "Start after install: \(startAfterInstall ? "Yes" : "No")",
            "Start on boot: \(startOnBoot ? "Yes" : "No")"
        ]
    }

    var validationMessage: String? {
        if adminPassword.isEmpty {
            return AppConstants.InstallWizard.adminPasswordRequired
        }
        if adminPassword != adminPasswordConfirmation {
            return AppConstants.InstallWizard.adminPasswordMismatch
        }
        return nil
    }

    var installEnvironment: String {
        [
            "TIROSH_CPU_COUNT=\(resources.cpuCount)",
            "TIROSH_MEMORY_GIB=\(resources.memoryGiB)",
            "TIROSH_DISK_GIB=\(resources.diskGiB)",
            "TIROSH_NETWORK_MODE=\(networkMode.rawValue)",
            "TIROSH_PROXY_PORT=\(proxyPort)",
            "TIROSH_VITAL_FILES_DIR=\(vitalFilesDirectory)",
            "TIROSH_ADMIN_PASSWORD_B64=\(Data(adminPassword.utf8).base64EncodedString())",
            "TIROSH_VM_HOSTNAME=\(vmHostname)",
            "TIROSH_PUBLIC_HOST=\(publicHost)",
            "TIROSH_PUBLIC_PORT=\(publicPort)",
            "TIROSH_START_AFTER_INSTALL=\(startAfterInstall ? "true" : "false")",
            "TIROSH_START_ON_BOOT=\(startOnBoot ? "true" : "false")"
        ].joined(separator: "\n") + "\n"
    }
}
