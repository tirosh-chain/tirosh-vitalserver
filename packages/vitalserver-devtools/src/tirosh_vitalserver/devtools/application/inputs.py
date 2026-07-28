from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from tirosh_vitalserver.devtools.core.helper_stable_update_release_models import (
    HelperStableUpdateLayer,
    HelperStableUpdateLayerRelease,
)
from tirosh_vitalserver.devtools.core.update_bootstrap_bundle_models import (
    BuildUpdateBootstrapBundleInput,
    VerifyUpdateBootstrapBundleInput,
)
from tirosh_vitalserver.devtools.core.update_bundle_models import BuildUpdateBundleInput
from tirosh_vitalserver.devtools.core.upstream_vitalserver_contract import (
    VerificationMode,
)


@dataclass(frozen=True)
class ConfigValueInput:
    config: Path
    key: str


@dataclass(frozen=True)
class HostProxyInput:
    runtime_dir: str
    proxy_config: str
    port: str
    bind_host: str
    http_port: str
    upstream: str
    trust_proxy: str
    nginx_bin: str
    nginx_conf: str
    nginx_prefix: str


@dataclass(frozen=True)
class NginxBundleInput:
    config: Path
    bundle_dir: Path
    binary: str | None
    expected_version: str | None
    release_file: Path | None = None


@dataclass(frozen=True)
class EnvironmentInput:
    proxy: HostProxyInput
    python: str
    uv: str
    compose: str


@dataclass(frozen=True)
class ComposeCommandInput:
    compose: str
    compose_args: list[str]
    bind_host: str
    http_port: str
    redis_host: str
    redis_port: str
    trust_proxy: str


@dataclass(frozen=True)
class OpenProductUrlInput:
    port: str


@dataclass(frozen=True)
class PythonWorkspaceToolInput:
    uv: str
    tool_args: list[str]


@dataclass(frozen=True)
class UbuntuBootAssetsInput:
    config: Path
    runtime_dir: Path | None
    rootfs_size: str | None
    recreate_rootfs: bool | None
    disk_image_name: str | None


@dataclass(frozen=True)
class CloudInitInput:
    config: Path
    runtime_dir: Path | None
    seed_dir: Path | None
    seed_iso: Path | None
    hostname: str | None
    instance_id: str | None
    username: str | None
    password: str | None
    ssh_key: Path | None
    run_bootstrap: bool | None
    share_tag: str | None
    share_mount: str | None
    bootstrap_script: str | None


@dataclass(frozen=True)
class RootfsBaseInput:
    source: Path
    output: Path
    force: bool
    compression_threads: int | None
    expected_run_id: str | None


@dataclass(frozen=True)
class RootfsArtifactDeployVerifyInput:
    rootfs_base: Path
    deploy_dir: Path


@dataclass(frozen=True)
class DockerImageBundleInput:
    config: Path
    bundle_path: Path | None
    platform: str | None
    compression_threads: int | None


@dataclass(frozen=True)
class GuestDeploymentInput:
    config: Path
    vm_home: Path
    runtime_dir: Path
    deploy_dir: Path | None
    docker_bundle: Path | None
    rootfs_run_id: str | None
    source_deploy_dir: Path | None = None
    rootfs_artifact: Path | None = None
    runtime_boot_smoke_run_id: str | None = None


@dataclass(frozen=True)
class RequireGitBranchInput:
    branch: str


@dataclass(frozen=True)
class VerifyUpstreamVitalServerInput:
    mode: VerificationMode
    manifest: Path | None
    require_remote_commit: bool = False


@dataclass(frozen=True)
class RenderTemplateInput:
    template: Path
    output: Path
    var: list[str]


@dataclass(frozen=True)
class RuntimeBuildInput:
    config: Path
    release_file: Path
    sdkroot: str | None
    clang_module_cache: str | None


@dataclass(frozen=True)
class RuntimeSyncReleaseInput:
    config: Path
    release_file: Path


@dataclass(frozen=True)
class RuntimeSignInput:
    config: Path
    identity: str
    entitlements: str


@dataclass(frozen=True)
class RequireBridgedIdentityInput:
    identity: str


@dataclass(frozen=True)
class RuntimeControlInput:
    config: Path
    vm_home: Path
    runtime_args: list[str]


@dataclass(frozen=True)
class RuntimeVmHomeInput:
    config: Path
    vm_home: Path


@dataclass(frozen=True)
class RuntimeGuestAddressOwnerInput:
    config: Path
    vm_home: Path
    runtime_control_api_base_url: str
    runtime_control_api_token: str
    runtime_control_api_token_header: str
    runtime_control_api_timeout: float


@dataclass(frozen=True)
class RuntimeWaitInput:
    config: Path
    vm_home: Path
    timeout: int
    expected_run_id: str | None = None


@dataclass(frozen=True)
class RootfsRunInput:
    config: Path
    vm_home: Path
    run_id: str


@dataclass(frozen=True)
class GoldenRootfsPreflightInput:
    config: Path
    vm_home: Path
    expected_run_id: str
    apt_source: str = "network"


@dataclass(frozen=True)
class RuntimeBootSmokeRunInput:
    config: Path
    vm_home: Path
    run_id: str


@dataclass(frozen=True)
class RuntimeHealthInput:
    config: Path
    vm_home: Path
    proxy_port: str


@dataclass(frozen=True)
class MacOSAppInput:
    config: Path
    release_file: Path
    sdkroot: str | None
    clang_module_cache: str | None
    codesign_identity: str


@dataclass(frozen=True)
class InstalledStatusInput:
    config: Path
    fail_on_unhealthy: bool


@dataclass(frozen=True)
class InstalledHealthInput:
    config: Path
    proxy_port: str


@dataclass(frozen=True)
class InstalledSmokeInput:
    config: Path
    proxy_port: str


@dataclass(frozen=True)
class ReleaseUpdateBundleInput:
    config: Path
    release_file: Path
    bundle_name: str | None
    bundle_kind: str
    target_platform: str | None
    output_dir: Path | None
    rootfs_base: str | None
    migration: list[Path]
    requires_two_phase_update: bool
    compression_threads: int | None
    sdkroot: str | None
    clang_module_cache: str | None
    codesign_identity: str
    nginx_binary: str | None
    nginx_expected_version: str | None
    docker_platform: str | None


@dataclass(frozen=True)
class HelperStableUpdateLayerArtifactInput:
    layer: HelperStableUpdateLayer
    artifact: Path
    artifact_media_type: str
    effect_executor: Path
    effect_configuration: Path
    rollback_artifact: Path
    rollback_media_type: str


@dataclass(frozen=True)
class ComposeHelperStableUpdateReleaseInput:
    update_id: str
    specification_id: str
    product_version: str
    runtime_version: str
    target_platform: str
    target_architecture: str
    layers: tuple[HelperStableUpdateLayerArtifactInput, ...]
    next_updater: Path
    publisher_key_id: str
    publisher_private_key: Path
    publisher_trust_store: Path
    issued_at: str
    output: Path


@dataclass(frozen=True)
class MaterializedHelperUpdatePayload:
    root: Path
    layers: tuple[HelperStableUpdateLayerRelease, ...]


@dataclass(frozen=True)
class VerifyReleaseUpdateBundleInput:
    config: Path
    release_file: Path
    bundle_name: str | None
    bundle_kind: str
    output_dir: Path | None


@dataclass(frozen=True)
class ApplySmokeReleaseUpdateBundleInput:
    config: Path
    release_file: Path
    bundle_name: str | None
    bundle_kind: str
    output_dir: Path | None


@dataclass(frozen=True)
class ReleasePackageEnvironmentPreflightInput:
    config: Path
    release_file: Path
    output: Path | None
    output_kind: str
    update_bootstrap_trust_store: Path


@dataclass(frozen=True)
class ReleasePackageInput:
    config: Path
    release_file: Path
    output: Path | None
    output_kind: str
    rootfs_base: Path
    golden_runtime_dir: Path
    proxy_port: str
    compression_threads: int | None
    sdkroot: str | None
    clang_module_cache: str | None
    codesign_identity: str
    nginx_binary: str | None
    nginx_expected_version: str | None
    docker_platform: str | None
    guest_deploy_source: Path
    update_bootstrap_trust_store: Path


@dataclass(frozen=True)
class ReleaseTroubleshootingToolsInput:
    config: Path
    release_file: Path
    output: Path | None
    sdkroot: str | None
    clang_module_cache: str | None
    codesign_identity: str


@dataclass(frozen=True)
class ReleaseDmgArtifactVerifyInput:
    config: Path
    release_file: Path
    output: Path | None
    update_bootstrap_trust_store: Path


@dataclass(frozen=True)
class ReleaseTroubleshootingToolsVerifyInput:
    config: Path
    release_file: Path
    output: Path | None


@dataclass(frozen=True)
class MacOSPackageCleanInput:
    config: Path
    release_file: Path


@dataclass(frozen=True)
class MacOSPackageInstallInput:
    config: Path
    release_file: Path
    install_settings: str | None


@dataclass(frozen=True)
class VerifyUpdateBundleInput:
    bundle_path: Path


__all__ = [
    "ApplySmokeReleaseUpdateBundleInput",
    "BuildUpdateBootstrapBundleInput",
    "BuildUpdateBundleInput",
    "CloudInitInput",
    "ComposeCommandInput",
    "ComposeHelperStableUpdateReleaseInput",
    "ConfigValueInput",
    "DockerImageBundleInput",
    "EnvironmentInput",
    "GuestDeploymentInput",
    "HelperStableUpdateLayerArtifactInput",
    "HostProxyInput",
    "InstalledHealthInput",
    "InstalledSmokeInput",
    "InstalledStatusInput",
    "MacOSAppInput",
    "MacOSPackageCleanInput",
    "MacOSPackageInstallInput",
    "MaterializedHelperUpdatePayload",
    "NginxBundleInput",
    "OpenProductUrlInput",
    "PythonWorkspaceToolInput",
    "ReleaseDmgArtifactVerifyInput",
    "ReleasePackageEnvironmentPreflightInput",
    "ReleasePackageInput",
    "ReleaseTroubleshootingToolsInput",
    "ReleaseTroubleshootingToolsVerifyInput",
    "ReleaseUpdateBundleInput",
    "RenderTemplateInput",
    "RequireBridgedIdentityInput",
    "RequireGitBranchInput",
    "RootfsArtifactDeployVerifyInput",
    "RootfsBaseInput",
    "RuntimeBuildInput",
    "RuntimeControlInput",
    "RuntimeHealthInput",
    "RuntimeSignInput",
    "RuntimeSyncReleaseInput",
    "RuntimeVmHomeInput",
    "RuntimeWaitInput",
    "UbuntuBootAssetsInput",
    "VerifyReleaseUpdateBundleInput",
    "VerifyUpdateBootstrapBundleInput",
    "VerifyUpdateBundleInput",
]
