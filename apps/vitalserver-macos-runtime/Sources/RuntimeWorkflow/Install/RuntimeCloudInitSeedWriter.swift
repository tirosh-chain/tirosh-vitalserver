import Foundation

public struct RuntimeCloudInitSeedContext {
    public let runtimeDirectory: URL
    public let seedImageName: String
    public let seedVolumeName: String
    public let hdiutilExecutable: String

    public init(
        runtimeDirectory: URL,
        seedImageName: String,
        seedVolumeName: String,
        hdiutilExecutable: String
    ) {
        self.runtimeDirectory = runtimeDirectory
        self.seedImageName = seedImageName
        self.seedVolumeName = seedVolumeName
        self.hdiutilExecutable = hdiutilExecutable
    }
}

public struct RuntimeCloudInitSeedOperations {
    public let directoryExists: (URL) -> Bool
    public let fileExists: (URL) -> Bool
    public let removeItem: (URL) throws -> Void
    public let createDirectory: (URL, Bool) throws -> Void
    public let writeData: (Data, URL, Data.WritingOptions) throws -> Void
    public let runRequired: (String, [String]) throws -> Void
    public let instanceID: () -> String

    public init(
        directoryExists: @escaping (URL) -> Bool,
        fileExists: @escaping (URL) -> Bool,
        removeItem: @escaping (URL) throws -> Void,
        createDirectory: @escaping (URL, Bool) throws -> Void,
        writeData: @escaping (Data, URL, Data.WritingOptions) throws -> Void,
        runRequired: @escaping (String, [String]) throws -> Void,
        instanceID: @escaping () -> String
    ) {
        self.directoryExists = directoryExists
        self.fileExists = fileExists
        self.removeItem = removeItem
        self.createDirectory = createDirectory
        self.writeData = writeData
        self.runRequired = runRequired
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

    public func create(hostname: String) throws {
        let seedDir = context.runtimeDirectory.appendingPathComponent("cloud-init-seed")
        let seedISO = context.runtimeDirectory.appendingPathComponent(context.seedImageName)
        if operations.directoryExists(seedDir) {
            try operations.removeItem(seedDir)
        }
        try operations.createDirectory(seedDir, true)
        try operations.writeData(metaData(hostname: hostname), seedDir.appendingPathComponent("meta-data"), .atomic)
        try operations.writeData(userData(hostname: hostname), seedDir.appendingPathComponent("user-data"), .atomic)

        if operations.fileExists(seedISO) {
            try operations.removeItem(seedISO)
        }
        try operations.runRequired(
            context.hdiutilExecutable,
            [
                "makehybrid",
                "-iso",
                "-joliet",
                "-default-volume-name",
                context.seedVolumeName,
                "-o",
                seedISO.path,
                seedDir.path,
            ]
        )
    }

    private func metaData(hostname: String) -> Data {
        Data("""
        instance-id: \(operations.instanceID())
        local-hostname: \(hostname)

        """.utf8)
    }

    private func userData(hostname: String) -> Data {
        Data("""
        #cloud-config
        hostname: \(hostname)
        manage_etc_hosts: true
        ssh_pwauth: true
        disable_root: true
        users:
          - default
          - name: ubuntu
            groups: [adm, sudo]
            shell: /bin/bash
            sudo: ALL=(ALL) NOPASSWD:ALL
            lock_passwd: false
            ssh_authorized_keys: []
        chpasswd:
          expire: false
          users:
            - name: ubuntu
              password: ubuntu
              type: text
        runcmd:
          - mkdir -p /mnt/tirosh
          - mountpoint -q /mnt/tirosh || mount -t virtiofs tirosh /mnt/tirosh
          - mkdir -p /mnt/tirosh/run
          - test -x /mnt/tirosh/deploy/bootstrap.sh
          - bash -lc '/mnt/tirosh/deploy/bootstrap.sh > /mnt/tirosh/run/bootstrap.log 2>&1'

        """.utf8)
    }
}
