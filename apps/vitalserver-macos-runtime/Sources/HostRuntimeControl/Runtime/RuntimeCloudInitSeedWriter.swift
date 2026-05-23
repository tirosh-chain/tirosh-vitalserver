import Foundation
import HostRuntimeInfrastructure
import RuntimeCore
import RuntimeContracts

struct RuntimeCloudInitSeedWriter {
    let installedPaths: InstalledRuntimePaths
    let fileStore: RuntimeFileStore
    let runRequired: (String, [String]) throws -> Void

    func create(hostname: String) throws {
        let seedDir = installedPaths.runtimeDirectory.appendingPathComponent("cloud-init-seed")
        let seedISO = installedPaths.runtimeDirectory.appendingPathComponent(Constants.BootAssets.cloudInit)
        if fileStore.directoryExists(seedDir) {
            try fileStore.removeItem(at: seedDir)
        }
        try fileStore.createDirectory(at: seedDir, withIntermediateDirectories: true)
        let instanceID = "tirosh-\(UUID().uuidString.lowercased())"
        try fileStore.writeData(Data("""
        instance-id: \(instanceID)
        local-hostname: \(hostname)

        """.utf8), to: seedDir.appendingPathComponent("meta-data"), options: .atomic)

        try fileStore.writeData(Data("""
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

        """.utf8), to: seedDir.appendingPathComponent("user-data"), options: .atomic)

        if fileStore.fileExists(seedISO) {
            try fileStore.removeItem(at: seedISO)
        }
        try runRequired(
            Constants.Commands.hdiutil,
            [
                "makehybrid",
                "-iso",
                "-joliet",
                "-default-volume-name",
                "cidata",
                "-o",
                seedISO.path,
                seedDir.path,
            ]
        )
    }
}
