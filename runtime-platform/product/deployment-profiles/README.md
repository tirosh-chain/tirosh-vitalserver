# Product deployment profiles

This directory contains named, composable desired deployments. A deployment
profile is not a runtime state store, a release receipt, or a provider
selection shortcut. It brings together only the configuration documents that
one named Host installation must consume together.

`profiles/` remains the owner-neutral capability selection vocabulary. In
contrast, a directory below `deployment-profiles/` states a concrete
combination of Host operating system, virtual-machine provider, upstream
placement, and public-edge intent. The directory name must make that
combination visible before a reader opens any JSON file.

Each profile records desired input only:

- C32 `MacOSVirtualMachineConfiguration` is consumed by the macOS Virtual
  Machine Supervisor;
- C33 `HostAgentDeploymentConfiguration` is consumed by Host Agent; and
- C36 `HostEdgeProxyDeploymentConfiguration` is consumed by Host Edge Proxy.

Those consumers own their own process and runtime facts. A profile never
claims that a VM booted, an endpoint connected, or a public listener became
ready. Those observations belong to the relevant Host/Guest state owner and
the C24 release-evidence workflow.

The first profile is
`macos-virtualization-external-vitalserver-reference/`. Its `reference` name
is intentional: it composes a package-buildable macOS/arm64 configuration with
the checked-in external VitalServer reference configuration. The `.example`
endpoint in that C46 source is not a deployable clinical target. A deployment
administrator must provide a separately identified C46 document for a real
external VitalServer before clean-Host installation and operational evidence
can be recorded.
