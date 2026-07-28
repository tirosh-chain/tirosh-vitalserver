from __future__ import annotations

import re

HELPER_HOST_ARCHIVE_COMPOSITION_SCHEMA = (
    "vitalserver.helper-host-platform-release-archive-composition/v1"
)
HELPER_HOST_ARCHIVE_MEDIA_TYPE = (
    "application/vnd.tirosh.vitalserver-helper.host-platform-release+tar+gzip"
)
HELPER_HOST_RELEASE_MANIFEST_SCHEMA = (
    "vitalserver.helper-host-platform-release-manifest/v1"
)
STABLE_OWNER_EXECUTABLES = {
    "vitalserver-host-installation-manager",
    "vitalserver-update-handoff-supervisor",
}
STABLE_OWNER_SERVICE_ROLES = {
    "host-installation-manager",
    "update-handoff-supervisor",
}
SHA256 = re.compile(r"^[a-f0-9]{64}$")


def validate_helper_host_platform_release_documents(
    composition: object,
    manifest: object,
) -> None:
    require_object(
        composition,
        {
            "schemaVersion",
            "releaseSourceDirectory",
            "serviceDefinitionSources",
            "operatorInterfaceBootstrapSourcePath",
        },
        "Helper Host archive composition",
    )
    if composition["schemaVersion"] != HELPER_HOST_ARCHIVE_COMPOSITION_SCHEMA:
        raise ValueError("Helper Host archive composition schemaVersion is invalid")
    require_absolute_string(
        composition["releaseSourceDirectory"],
        "releaseSourceDirectory",
    )
    require_absolute_string(
        composition["operatorInterfaceBootstrapSourcePath"],
        "operatorInterfaceBootstrapSourcePath",
    )
    sources = composition["serviceDefinitionSources"]
    if not isinstance(sources, list) or not sources:
        raise ValueError("serviceDefinitionSources must be a non-empty array")
    source_roles: set[str] = set()
    for index, source in enumerate(sources):
        require_object(
            source,
            {"role", "sourcePath"},
            f"serviceDefinitionSources[{index}]",
        )
        role = require_nonempty_string(source["role"], "service role")
        if role in source_roles:
            raise ValueError(f"service definition role is duplicated: {role}")
        if role in STABLE_OWNER_SERVICE_ROLES:
            raise ValueError(f"stable owner service must not be replaced: {role}")
        source_roles.add(role)
        require_absolute_string(source["sourcePath"], "service sourcePath")

    require_object(
        manifest,
        {
            "schemaVersion",
            "installationId",
            "release",
            "releaseCatalogPath",
            "releaseRootPath",
            "currentReleaseLinkPath",
            "files",
            "operatorInterface",
            "replaceableServices",
            "stableComponents",
            "mutableStores",
        },
        "Helper Host installation manifest",
    )
    if manifest["schemaVersion"] != HELPER_HOST_RELEASE_MANIFEST_SCHEMA:
        raise ValueError("Helper Host installation manifest schemaVersion is invalid")
    require_nonempty_string(manifest["installationId"], "installationId")
    require_object(manifest["release"], {"id", "version"}, "release")
    require_nonempty_string(manifest["release"]["id"], "release.id")
    require_nonempty_string(manifest["release"]["version"], "release.version")
    require_absolute_string(manifest["releaseCatalogPath"], "releaseCatalogPath")
    require_absolute_string(manifest["releaseRootPath"], "releaseRootPath")
    require_absolute_string(
        manifest["currentReleaseLinkPath"],
        "currentReleaseLinkPath",
    )
    entries = manifest["files"]
    if not isinstance(entries, list) or not entries:
        raise ValueError("files must be a non-empty array")
    paths: set[str] = set()
    executable_by_path: dict[str, bool] = {}
    for index, entry in enumerate(entries):
        require_object(
            entry,
            {"relativePath", "sha256", "executable"},
            f"immutablePayload.entries[{index}]",
        )
        relative = require_safe_relative_path(entry["relativePath"])
        if relative in paths:
            raise ValueError(f"immutable payload path is duplicated: {relative}")
        if relative.rsplit("/", 1)[-1] in STABLE_OWNER_EXECUTABLES:
            raise ValueError(
                f"stable owner executable must not be replaced: {relative}"
            )
        paths.add(relative)
        require_sha256(entry["sha256"], f"immutable payload {relative}")
        if not isinstance(entry["executable"], bool):
            raise ValueError(f"immutable payload executable is invalid: {relative}")
        executable_by_path[relative] = entry["executable"]

    operator = manifest["operatorInterface"]
    require_object(
        operator,
        {
            "bootstrapConfigurationPath",
            "bootstrapConfigurationSha256",
            "applicationBundlePath",
            "applicationBundleRelativePath",
            "applicationBundleTreeSha256",
            "applicationBundleEntrypointRelativePath",
        },
        "operatorInterface",
    )
    require_sha256(
        operator["bootstrapConfigurationSha256"],
        "operator bootstrap",
    )
    require_absolute_string(
        operator["bootstrapConfigurationPath"],
        "bootstrapConfigurationPath",
    )
    require_sha256(operator["applicationBundleTreeSha256"], "application bundle")
    require_absolute_string(operator["applicationBundlePath"], "applicationBundlePath")
    application_bundle_relative = require_safe_relative_path(
        operator["applicationBundleRelativePath"]
    )
    application_entrypoint = require_safe_relative_path(
        operator["applicationBundleEntrypointRelativePath"]
    )
    if not any(
        path == application_bundle_relative
        or path.startswith(f"{application_bundle_relative}/")
        for path in paths
    ):
        raise ValueError(
            "application bundle is absent from immutable release files: "
            f"{application_bundle_relative}"
        )
    release_entrypoint = (
        f"{application_bundle_relative}/{application_entrypoint}"
    )
    if executable_by_path.get(release_entrypoint) is not True:
        raise ValueError(
            "application bundle entrypoint is absent or not executable: "
            f"{release_entrypoint}"
        )

    services = manifest["replaceableServices"]
    if not isinstance(services, list) or not services:
        raise ValueError("replaceableServices must be a non-empty array")
    declared_roles: set[str] = set()
    for index, service in enumerate(services):
        require_object(
            service,
            {"role", "manager", "name", "definitionPath", "definitionSha256"},
            f"replaceableServices[{index}]",
        )
        role = require_nonempty_string(service["role"], "required service role")
        if role in STABLE_OWNER_SERVICE_ROLES:
            raise ValueError(f"stable owner service must not be quiesced: {role}")
        if role in declared_roles:
            raise ValueError(f"required service role is duplicated: {role}")
        declared_roles.add(role)
        if service["manager"] != "launchd":
            raise ValueError(f"Helper Host service manager must be launchd: {role}")
        require_nonempty_string(service["name"], f"service name {role}")
        require_absolute_string(
            service["definitionPath"],
            f"service definitionPath {role}",
        )
        require_sha256(service["definitionSha256"], f"service definition {role}")
    if declared_roles != source_roles:
        raise ValueError(
            "service definition source roles differ from required service roles "
            f"missing={sorted(declared_roles - source_roles)} "
            f"unknown={sorted(source_roles - declared_roles)}"
        )
    stable_components = manifest["stableComponents"]
    if not isinstance(stable_components, list):
        raise ValueError("stableComponents must be an array")
    stable_roles: set[str] = set()
    for index, component in enumerate(stable_components):
        require_object(
            component,
            {"role", "executablePath", "serviceName"},
            f"stableComponents[{index}]",
        )
        role = require_nonempty_string(component["role"], "stable component role")
        if role in stable_roles:
            raise ValueError(f"stable component role is duplicated: {role}")
        stable_roles.add(role)
        require_absolute_string(
            component["executablePath"],
            "stable component executablePath",
        )
        if component["serviceName"] is not None:
            require_nonempty_string(
                component["serviceName"],
                "stable component serviceName",
            )
    if stable_roles != STABLE_OWNER_SERVICE_ROLES:
        raise ValueError(
            "stable component roles differ "
            f"missing={sorted(STABLE_OWNER_SERVICE_ROLES - stable_roles)} "
            f"unknown={sorted(stable_roles - STABLE_OWNER_SERVICE_ROLES)}"
        )
    if stable_roles & declared_roles:
        raise ValueError("stable and replaceable service roles overlap")
    mutable_stores = manifest["mutableStores"]
    if not isinstance(mutable_stores, list):
        raise ValueError("mutableStores must be an array")
    mutable_ids: set[str] = set()
    for index, store in enumerate(mutable_stores):
        require_object(
            store,
            {"id", "path", "kind", "owner", "retention"},
            f"mutableStores[{index}]",
        )
        store_id = require_nonempty_string(store["id"], "mutable store id")
        if store_id in mutable_ids:
            raise ValueError(f"mutable store id is duplicated: {store_id}")
        mutable_ids.add(store_id)
        require_absolute_string(store["path"], f"mutable store path {store_id}")
        require_nonempty_string(store["kind"], f"mutable store kind {store_id}")
        require_nonempty_string(store["owner"], f"mutable store owner {store_id}")
        require_nonempty_string(
            store["retention"],
            f"mutable store retention {store_id}",
        )


def require_object(value: object, keys: set[str], location: str) -> None:
    if not isinstance(value, dict):
        raise ValueError(f"{location} must be an object")
    actual = set(value)
    if actual != keys:
        raise ValueError(
            f"{location} fields differ "
            f"missing={sorted(keys - actual)} unknown={sorted(actual - keys)}"
        )


def require_nonempty_string(value: object, location: str) -> str:
    if not isinstance(value, str) or not value:
        raise ValueError(f"{location} must be non-empty text")
    return value


def require_absolute_string(value: object, location: str) -> str:
    text = require_nonempty_string(value, location)
    if not text.startswith("/"):
        raise ValueError(f"{location} must be an absolute path")
    return text


def require_safe_relative_path(value: object) -> str:
    text = require_nonempty_string(value, "relative path")
    parts = text.split("/")
    if (
        text.startswith("/")
        or "\\" in text
        or any(part in {"", ".", ".."} for part in parts)
    ):
        raise ValueError(f"relative path is unsafe: {text}")
    return text


def require_sha256(value: object, location: str) -> str:
    if not isinstance(value, str) or not SHA256.fullmatch(value):
        raise ValueError(f"{location} SHA-256 is invalid")
    return value
