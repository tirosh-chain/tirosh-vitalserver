import Foundation
import Contracts
import Errors

public struct RuntimeCloudInitSeedContext {
    public let runtimeDirectory: URL
    public let seedImageName: String
    public let seedVolumeName: String

    public init(
        runtimeDirectory: URL,
        seedImageName: String,
        seedVolumeName: String
    ) {
        self.runtimeDirectory = runtimeDirectory
        self.seedImageName = seedImageName
        self.seedVolumeName = seedVolumeName
    }
}

public struct RuntimeCloudInitSeedImageBuildRequest: Equatable {
    public let sourceDirectory: URL
    public let outputImage: URL
    public let volumeName: String

    public init(
        sourceDirectory: URL,
        outputImage: URL,
        volumeName: String
    ) {
        self.sourceDirectory = sourceDirectory
        self.outputImage = outputImage
        self.volumeName = volumeName
    }
}

public struct RuntimeCloudInitSeedOperations {
    public let pathState: (URL) -> RuntimePathState
    public let removeItem: (URL) throws -> Void
    public let createDirectory: (URL, Bool) throws -> Void
    public let writeData: (Data, URL, Data.WritingOptions) throws -> Void
    public let buildSeedImage: (RuntimeCloudInitSeedImageBuildRequest) throws -> Void
    public let instanceID: () -> String

    public init(
        pathState: @escaping (URL) -> RuntimePathState,
        removeItem: @escaping (URL) throws -> Void,
        createDirectory: @escaping (URL, Bool) throws -> Void,
        writeData: @escaping (Data, URL, Data.WritingOptions) throws -> Void,
        buildSeedImage: @escaping (RuntimeCloudInitSeedImageBuildRequest) throws -> Void,
        instanceID: @escaping () -> String
    ) {
        self.pathState = pathState
        self.removeItem = removeItem
        self.createDirectory = createDirectory
        self.writeData = writeData
        self.buildSeedImage = buildSeedImage
        self.instanceID = instanceID
    }
}

public struct RuntimeCloudInitSeedWriter {
    public let context: RuntimeCloudInitSeedContext
    public let operations: RuntimeCloudInitSeedOperations

    public init(
        context: RuntimeCloudInitSeedContext,
        operations: RuntimeCloudInitSeedOperations
    ) {
        self.context = context
        self.operations = operations
    }

    public func create(hostname: String, sshAuthorizedKeys: [String] = []) throws {
        let seedDir = context.runtimeDirectory.appendingPathComponent("cloud-init-seed")
        let seedISO = context.runtimeDirectory.appendingPathComponent(context.seedImageName)
        try removePathIfPresent(seedDir)
        try operations.createDirectory(seedDir, true)
        try operations.writeData(metaData(hostname: hostname), seedDir.appendingPathComponent("meta-data"), .atomic)
        try operations.writeData(
            userData(hostname: hostname, sshAuthorizedKeys: sshAuthorizedKeys),
            seedDir.appendingPathComponent("user-data"),
            .atomic
        )

        try removePathIfPresent(seedISO)
        try operations.buildSeedImage(
            RuntimeCloudInitSeedImageBuildRequest(
                sourceDirectory: seedDir,
                outputImage: seedISO,
                volumeName: context.seedVolumeName
            )
        )
    }

    private func removePathIfPresent(_ url: URL) throws {
        switch operations.pathState(url) {
        case .file, .directory, .other:
            try operations.removeItem(url)
        case .missing:
            return
        case .inspectFailed(let reason):
            throw RuntimeCloudInitSeedWriterError.pathInspectionFailed(path: url.path, reason: reason)
        case .unknown(let value):
            throw RuntimeCloudInitSeedWriterError.unexpectedPathState(path: url.path, state: value)
        }
    }

    private func metaData(hostname: String) -> Data {
        Data("""
        instance-id: \(operations.instanceID())
        local-hostname: \(hostname)

        """.utf8)
    }

    private func userData(hostname: String, sshAuthorizedKeys: [String]) -> Data {
        Data("""
        #cloud-config
        hostname: \(hostname)
        manage_etc_hosts: true
        ssh_pwauth: false
        disable_root: true
        users:
          - default
          - name: ubuntu
            groups: [adm, sudo]
            shell: /bin/bash
            sudo: ALL=(ALL) NOPASSWD:ALL
            lock_passwd: true
            ssh_authorized_keys:\(sshAuthorizedKeysYAML(sshAuthorizedKeys))
        runcmd:
          - mkdir -p /mnt/tirosh
          - mountpoint -q /mnt/tirosh || mount -t virtiofs tirosh /mnt/tirosh
          - mkdir -p /mnt/tirosh/run
          - test -x /mnt/tirosh/deploy/bootstrap.sh
          - bash -lc '/mnt/tirosh/deploy/bootstrap.sh > /mnt/tirosh/run/bootstrap.log 2>&1'

        """.utf8)
    }

    private func sshAuthorizedKeysYAML(_ keys: [String]) -> String {
        guard !keys.isEmpty else {
            return " []"
        }
        return keys
            .map { "\n              - '\($0.replacingOccurrences(of: "'", with: "''"))'" }
            .joined()
    }
}
