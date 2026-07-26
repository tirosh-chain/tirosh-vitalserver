# Host Platform release archive composer

This release-process tool creates the rigid C68 Host Platform archive consumed
by Host Installation Manager. Its source composition names the exact local
candidate release directory, the three C48-declared service-definition source
files, and the C53 Runtime Console bootstrap source. Those paths are build
inputs only: the produced archive contains only the C48-declared bytes under
the fixed `release/`, `service-definitions/`, and `operator-interface/`
layout.

The `service-definitions/` filename is not inferred from a source extension.
It is determined by the candidate C48 `platform`: `role.plist` for macOS,
`role.service` for Linux, and `role.json` for Windows. This allows a release
process on any OS to compose the target platform's fixed C68 layout without
letting the composing machine redefine a Host contract.

The composer reads the candidate C48 from
`releaseSourceDirectory/installation-manifest.json`, verifies every source
against its declared SHA-256, rejects undeclared release files and symbolic
links, and creates a new deterministic tar+gzip output. It does not select an
active release, write an installation-manager store, activate `current`, or
sign C25.

Example composition:

```json
{
  "schemaVersion": "v1",
  "releaseSourceDirectory": "/release/runtime-platform-030",
  "serviceDefinitionSources": [
    { "role": "host-agent", "sourcePath": "/release/services/host-agent.plist" },
    { "role": "host-edge-proxy", "sourcePath": "/release/services/host-edge-proxy.plist" },
    { "role": "host-update-handoff-supervisor", "sourcePath": "/release/services/host-update-handoff-supervisor.plist" }
  ],
  "operatorInterfaceBootstrapSourcePath": "/release/operator/runtime-console-bootstrap.json"
}
```

```sh
host-platform-release-archive-composer \
  --composition /release/host-platform-030.archive-composition.json \
  --output-archive /release/runtime-platform-030.tar.gz
```
