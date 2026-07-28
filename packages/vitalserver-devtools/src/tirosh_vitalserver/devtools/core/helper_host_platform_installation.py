from __future__ import annotations

from dataclasses import dataclass

from tirosh_vitalserver.devtools.core.helper_host_platform_release import (
    HELPER_HOST_RELEASE_MANIFEST_SCHEMA,
)

HOST_PLATFORM_INSTALLATION_SCHEMA = "vitalserver.host-platform-installation/v1"
HOST_PLATFORM_EFFECT_CONFIGURATION_SCHEMA = (
    "vitalserver.host-platform-layer-effect-configuration/v1"
)


@dataclass(frozen=True)
class ImmutableReleaseFile:
    relative_path: str
    sha256: str
    executable: bool


@dataclass(frozen=True)
class ReplaceableLaunchdService:
    role: str
    name: str
    definition_path: str
    definition_sha256: str


@dataclass(frozen=True)
class HostReleaseIdentity:
    release_id: str
    version: str
    archive_sha256: str
    slot_relative_path: str


def make_release_manifest(
    *,
    installation_id: str,
    release: HostReleaseIdentity,
    installation_root: str,
    files: tuple[ImmutableReleaseFile, ...],
    application_bundle_path: str,
    application_bundle_relative_path: str,
    application_bundle_tree_sha256: str,
    application_entrypoint_relative_path: str,
    bootstrap_path: str,
    bootstrap_sha256: str,
    services: tuple[ReplaceableLaunchdService, ...],
    manager_executable_path: str,
    supervisor_executable_path: str,
    supervisor_service_name: str,
    mutable_stores: tuple[dict[str, str], ...],
) -> dict[str, object]:
    release_root = f"{installation_root}/{release.slot_relative_path}/release"
    return {
        "schemaVersion": HELPER_HOST_RELEASE_MANIFEST_SCHEMA,
        "installationId": installation_id,
        "release": {
            "id": release.release_id,
            "version": release.version,
        },
        "releaseCatalogPath": installation_root,
        "releaseRootPath": release_root,
        "currentReleaseLinkPath": f"{installation_root}/current",
        "files": [
            {
                "relativePath": entry.relative_path,
                "sha256": entry.sha256,
                "executable": entry.executable,
            }
            for entry in files
        ],
        "operatorInterface": {
            "bootstrapConfigurationPath": bootstrap_path,
            "bootstrapConfigurationSha256": bootstrap_sha256,
            "applicationBundlePath": application_bundle_path,
            "applicationBundleRelativePath": application_bundle_relative_path,
            "applicationBundleTreeSha256": application_bundle_tree_sha256,
            "applicationBundleEntrypointRelativePath": (
                application_entrypoint_relative_path
            ),
        },
        "replaceableServices": [
            {
                "role": service.role,
                "manager": "launchd",
                "name": service.name,
                "definitionPath": service.definition_path,
                "definitionSha256": service.definition_sha256,
            }
            for service in services
        ],
        "stableComponents": [
            {
                "role": "host-installation-manager",
                "executablePath": manager_executable_path,
                "serviceName": None,
            },
            {
                "role": "update-handoff-supervisor",
                "executablePath": supervisor_executable_path,
                "serviceName": supervisor_service_name,
            },
        ],
        "mutableStores": list(mutable_stores),
    }


def make_initial_installation_manifest(
    *,
    installation_id: str,
    release: HostReleaseIdentity,
    activated_at: str,
) -> dict[str, object]:
    return {
        "schemaVersion": HOST_PLATFORM_INSTALLATION_SCHEMA,
        "installationId": installation_id,
        "installationRevision": 1,
        "activeRelease": {
            "id": release.release_id,
            "version": release.version,
            "sha256": release.archive_sha256,
            "slotRelativePath": release.slot_relative_path,
        },
        "rollbackRelease": None,
        "activationOperationId": f"fresh-install.{release.release_id}",
        "activatedAt": activated_at,
    }


def make_layer_effect_configuration(
    *,
    effect_executor_id: str,
    manager_executable_path: str,
    database_path: str,
    installation_root: str,
    exchange_root: str,
    apply: tuple[str, int, str, str, str],
    rollback: tuple[str, int, str, str, str],
) -> dict[str, object]:
    def transition(value: tuple[str, int, str, str, str]) -> dict[str, object]:
        (
            installation_id,
            revision,
            release_id,
            version,
            slot_relative_path,
        ) = value
        return {
            "installationId": installation_id,
            "expectedInstallationRevision": revision,
            "targetReleaseId": release_id,
            "targetReleaseVersion": version,
            "targetSlotRelativePath": slot_relative_path,
        }

    return {
        "schemaVersion": HOST_PLATFORM_EFFECT_CONFIGURATION_SCHEMA,
        "effectExecutorId": effect_executor_id,
        "manager": {
            "executablePath": manager_executable_path,
            "databasePath": database_path,
            "installationRootPath": installation_root,
            "launchctlExecutablePath": "/bin/launchctl",
            "exchangeRootPath": exchange_root,
        },
        "apply": transition(apply),
        "rollback": transition(rollback),
    }
