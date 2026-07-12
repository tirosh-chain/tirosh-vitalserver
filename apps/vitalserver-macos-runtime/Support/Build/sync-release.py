#!/usr/bin/env python3
# ruff: noqa: E501
import json
import re
import sys
from pathlib import Path

RELEASE_SERVICE_KEYS = (
    "vitalServer",
    "recorderIngress",
    "recorderRecovery",
    "vitalDBObserver",
    "redisRelay",
    "lab",
    "redis",
    "postgres",
    "redisUI",
    "swaggerUI",
    "guestEdge",
    "hostProxy",
)
GUEST_COMPOSE_SERVICE_RELEASE_KEYS = (
    ("postgres", "postgres"),
    ("redis", "redis"),
    ("app", "vitalServer"),
    ("recorder-recovery", "recorderRecovery"),
    ("recorder-ingress", "recorderIngress"),
    ("vitaldb-observer", "vitalDBObserver"),
    ("redis-relay", "redisRelay"),
    ("lab", "lab"),
    ("redis-ui", "redisUI"),
    ("swagger-ui", "swaggerUI"),
    ("edge", "guestEdge"),
)
GUEST_DOCKER_BUNDLE_RELEASE_KEYS = (
    "vitalServer",
    "recorderIngress",
    "recorderRecovery",
    "vitalDBObserver",
    "redisRelay",
    "lab",
    "postgres",
    "redis",
    "redisUI",
    "swaggerUI",
    "guestEdge",
)
GUEST_DOCKER_IMAGE_FIELD_RELEASE_KEYS = (
    ("recorder_ingress_image", "recorderIngress"),
    ("recorder_recovery_image", "recorderRecovery"),
    ("vitaldb_observer_image", "vitalDBObserver"),
    ("redis_relay_image", "redisRelay"),
    ("lab_image", "lab"),
)


def require_service(release, key):
    try:
        service = release["services"][key]
    except KeyError as error:
        raise SystemExit(f"missing release service field: {key}.{error}") from error
    if not isinstance(service, dict):
        raise SystemExit(f"release service must be an object: services.{key}")
    return service


def require_field(mapping, path):
    try:
        value = mapping
        for key in path.split("."):
            value = value[key]
        return value
    except KeyError as error:
        raise SystemExit(f"missing release field: {path}") from error


def write_if_changed(path, content):
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists() and path.read_text(encoding="utf-8") == content:
        return
    path.write_text(content, encoding="utf-8")


def swift_string(value):
    escaped = (
        str(value)
        .replace("\\", "\\\\")
        .replace('"', '\\"')
        .replace("\n", "\\n")
        .replace("\r", "\\r")
        .replace("\t", "\\t")
    )
    return f'"{escaped}"'


def validate_release_policy(release):
    require_field(release, "channel")
    require_field(release, "releaseLabel")
    target_platform = require_field(release, "targetPlatform")
    if not isinstance(target_platform, str) or not target_platform:
        raise SystemExit("release field must be a non-empty string: targetPlatform")
    require_field(release, "distribution.profile")
    require_field(release, "distribution.audience")
    optional_services = require_field(release, "bundle.optionalContainerServices")
    if not isinstance(optional_services, list):
        raise SystemExit(
            "release field must be a list: bundle.optionalContainerServices"
        )
    if "testkit" in optional_services:
        raise SystemExit(
            "release field bundle.optionalContainerServices must not include "
            "testkit; Lab is the product service"
        )
    if isinstance(release.get("services"), dict) and "testkit" in release["services"]:
        raise SystemExit(
            "release field services must not include testkit; Lab is the "
            "product service"
        )
    for service in RELEASE_SERVICE_KEYS:
        require_service_string(release, service, "displayName")
        require_service_string(release, service, "image")
        require_service_string(release, service, "version")
    for service in optional_services:
        require_service_string(release, service, "displayName")
        require_service_string(release, service, "image")
        require_service_string(release, service, "version")


def require_service_string(release, service, key):
    value = require_service(release, service).get(key)
    if not isinstance(value, str) or not value:
        raise SystemExit(
            f"release service field must be a non-empty string: services.{service}.{key}"
        )
    return value


def release_service_images(release):
    return {
        service: require_service_string(release, service, "image")
        for service in RELEASE_SERVICE_KEYS
    }


def validate_release_input_contract(root, release):
    """Validate immutable Guest compile inputs before any Docker/cache work.

    The release manifest is release metadata.  It may generate the designated
    Swift sources below, but it must never rewrite the Compose, VM build, or
    Guest source contracts that determine the air-gapped VM material.
    """

    images = release_service_images(release)
    validate_guest_compose_images(root / "Support/Guest/compose.yaml", images)
    validate_guest_docker_images_config(
        root.parent.parent / "config/vm-build.toml",
        images,
    )


def validate_guest_compose_images(compose_path, images):
    try:
        compose_text = compose_path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError) as error:
        raise SystemExit(
            f"error: release contract cannot read Guest compose: {compose_path}: {error}"
        ) from error
    compose_images = parse_guest_compose_images(compose_text, compose_path)
    for compose_service, release_service in GUEST_COMPOSE_SERVICE_RELEASE_KEYS:
        expected = images[release_service]
        actual = compose_images.get(compose_service)
        if actual is None:
            raise SystemExit(
                "error: release contract Guest compose image is missing: "
                f"path={compose_path} service={compose_service} "
                f"releaseService={release_service}"
            )
        if actual != expected:
            raise SystemExit(
                "error: release contract Guest compose image mismatch: "
                f"path={compose_path} service={compose_service} "
                f"releaseService={release_service} expected={expected} actual={actual}"
            )


def parse_guest_compose_images(content, path):
    in_services = False
    current_service = None
    images = {}
    for line_number, line in enumerate(content.splitlines(), start=1):
        if line == "services:":
            if in_services:
                raise SystemExit(
                    f"error: release contract Guest compose has duplicate services section: {path}"
                )
            in_services = True
            continue
        if not in_services:
            continue
        if line and not line.startswith((" ", "\t", "#")):
            break
        service_match = re.fullmatch(
            r"  ([A-Za-z0-9][A-Za-z0-9_-]*):\s*(?:#.*)?",
            line,
        )
        if service_match:
            current_service = service_match.group(1)
            continue
        image_match = re.fullmatch(r"    image:\s*(.*?)\s*(?:#.*)?", line)
        if not image_match:
            continue
        if current_service is None:
            raise SystemExit(
                "error: release contract Guest compose image has no service: "
                f"path={path} line={line_number}"
            )
        if current_service in images:
            raise SystemExit(
                "error: release contract Guest compose service has multiple images: "
                f"path={path} service={current_service}"
            )
        images[current_service] = compose_image_value(
            image_match.group(1),
            path,
            line_number,
        )
    if not in_services:
        raise SystemExit(f"error: release contract Guest compose has no services: {path}")
    return images


def compose_image_value(value, path, line_number):
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in {"'", '"'}:
        value = value[1:-1]
    if not value or any(character.isspace() for character in value):
        raise SystemExit(
            "error: release contract Guest compose image is invalid: "
            f"path={path} line={line_number}"
        )
    return value


def validate_guest_docker_images_config(config_path, images):
    try:
        config_text = config_path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError) as error:
        raise SystemExit(
            "error: release contract cannot read VM Docker image config: "
            f"{config_path}: {error}"
        ) from error
    section = toml_table(config_text, "guest.docker_images", config_path)
    actual_bundle_images = toml_string_list(section, "images", config_path)
    expected_bundle_images = [images[key] for key in GUEST_DOCKER_BUNDLE_RELEASE_KEYS]
    if actual_bundle_images != expected_bundle_images:
        raise SystemExit(
            "error: release contract VM Docker image list mismatch: "
            f"path={config_path} expected={expected_bundle_images} "
            f"actual={actual_bundle_images}"
        )
    for field, release_service in GUEST_DOCKER_IMAGE_FIELD_RELEASE_KEYS:
        expected = images[release_service]
        actual = toml_string(section, field, config_path)
        if actual != expected:
            raise SystemExit(
                "error: release contract VM Docker image field mismatch: "
                f"path={config_path} field=guest.docker_images.{field} "
                f"releaseService={release_service} expected={expected} actual={actual}"
            )


def toml_table(content, table, path):
    table_pattern = re.compile(rf"^\[{re.escape(table)}\]\s*$", re.MULTILINE)
    match = table_pattern.search(content)
    if match is None:
        raise SystemExit(f"error: release contract VM config table is missing: {path} [{table}]")
    next_table = re.search(r"^\[.+\]\s*$", content[match.end() :], re.MULTILINE)
    if next_table is None:
        return content[match.end() :]
    return content[match.end() : match.end() + next_table.start()]


def toml_string(section, key, path):
    match = re.search(
        rf'^\s*{re.escape(key)}\s*=\s*"([^"]+)"\s*(?:#.*)?$',
        section,
        re.MULTILINE,
    )
    if match is None:
        raise SystemExit(
            "error: release contract VM config string is missing or invalid: "
            f"path={path} key=guest.docker_images.{key}"
        )
    return match.group(1)


def toml_string_list(section, key, path):
    lines = section.splitlines()
    start = None
    for index, line in enumerate(lines):
        if re.fullmatch(rf"\s*{re.escape(key)}\s*=\s*\[\s*", line):
            start = index + 1
            break
    if start is None:
        raise SystemExit(
            "error: release contract VM config image list is missing: "
            f"path={path} key=guest.docker_images.{key}"
        )
    values = []
    for line in lines[start:]:
        stripped = line.strip()
        if stripped == "]":
            return values
        match = re.fullmatch(r'"([^"]+)"\s*,?\s*(?:#.*)?', stripped)
        if match is None:
            raise SystemExit(
                "error: release contract VM config image list is invalid: "
                f"path={path} key=guest.docker_images.{key} line={stripped}"
            )
        values.append(match.group(1))
    raise SystemExit(
        "error: release contract VM config image list is unterminated: "
        f"path={path} key=guest.docker_images.{key}"
    )


def sync_swift(root, release, release_file):
    helper_version = release["helperVersion"]
    min_updater_version = release["minUpdaterVersion"]
    release_channel = require_field(release, "channel")
    release_label = require_field(release, "releaseLabel")
    distribution_profile = require_field(release, "distribution.profile")
    test_enabled = distribution_profile == "dev"
    vitalserver = require_service(release, "vitalServer")
    recorder_ingress = require_service(release, "recorderIngress")
    recorder_recovery = require_service(release, "recorderRecovery")
    vitaldb_observer = require_service(release, "vitalDBObserver")
    redis_relay = require_service(release, "redisRelay")
    lab = require_service(release, "lab")
    redis = require_service(release, "redis")
    postgres = require_service(release, "postgres")
    redis_ui = require_service(release, "redisUI")
    swagger_ui = require_service(release, "swaggerUI")
    guest_edge = require_service(release, "guestEdge")
    host_proxy = require_service(release, "hostProxy")
    vitalserver_name = require_field(release, "services.vitalServer.displayName")
    recorder_ingress_name = require_field(release, "services.recorderIngress.displayName")
    recorder_recovery_name = require_field(
        release,
        "services.recorderRecovery.displayName",
    )
    vitaldb_observer_name = require_field(
        release,
        "services.vitalDBObserver.displayName",
    )
    redis_relay_name = require_field(release, "services.redisRelay.displayName")
    lab_name = require_field(release, "services.lab.displayName")
    redis_name = require_field(release, "services.redis.displayName")
    postgres_name = require_field(release, "services.postgres.displayName")
    redis_ui_name = require_field(release, "services.redisUI.displayName")
    swagger_ui_name = require_field(release, "services.swaggerUI.displayName")
    guest_edge_name = require_field(release, "services.guestEdge.displayName")
    host_proxy_name = require_field(release, "services.hostProxy.displayName")

    write_if_changed(
        root / "Sources/Bootstrap/Composition/GeneratedVersion.swift",
        f"""// Generated from {release_file.name} by make devtools/release-contract.
// Do not edit this file directly.

import Contracts

public extension Constants {{
    static let launcherVersion = {swift_string(helper_version)}
    static let launcherChannel = UpdateBundleChannel(
        rawValue: {swift_string(release_channel)}
    )
}}
""",
    )
    write_if_changed(
        root
        / "Sources/Adapters/Inbound/MacControlPanel/Generated"
        / "GeneratedRelease.swift",
        f"""// Generated from {release_file.name} by make devtools/release-contract.
// Do not edit this file directly.

public enum GeneratedRelease {{
    public static let helperVersion = {swift_string(helper_version)}
    public static let channel = {swift_string(release_channel)}
    public static let releaseLabel = {swift_string(release_label)}
    public static let testEnabled = {str(test_enabled).lower()}
    public static let minUpdaterVersion = {swift_string(min_updater_version)}
    public static let vitalServerVersion = {swift_string(release["vitalServerVersion"])}
    public static let vitalServerName = {swift_string(vitalserver_name)}
    public static let recorderIngressName = {swift_string(recorder_ingress_name)}
    public static let recorderRecoveryName = {swift_string(recorder_recovery_name)}
    public static let vitalDBObserverName = {swift_string(vitaldb_observer_name)}
    public static let redisRelayName = {swift_string(redis_relay_name)}
    public static let labName = {swift_string(lab_name)}
    public static let redisName = {swift_string(redis_name)}
    public static let postgresName = {swift_string(postgres_name)}
    public static let redisUIName = {swift_string(redis_ui_name)}
    public static let swaggerUIName = {swift_string(swagger_ui_name)}
    public static let guestEdgeName = {swift_string(guest_edge_name)}
    public static let hostProxyName = {swift_string(host_proxy_name)}
    public static let vitalServerImage = {swift_string(vitalserver["image"])}
    public static let recorderIngressImage = {swift_string(recorder_ingress["image"])}
    public static let recorderRecoveryImage = {swift_string(recorder_recovery["image"])}
    public static let vitalDBObserverImage = {swift_string(vitaldb_observer["image"])}
    public static let redisRelayImage = {swift_string(redis_relay["image"])}
    public static let labImage = {swift_string(lab["image"])}
    public static let redisImage = {swift_string(redis["image"])}
    public static let postgresImage = {swift_string(postgres["image"])}
    public static let redisUIImage = {swift_string(redis_ui["image"])}
    public static let swaggerUIImage = {swift_string(swagger_ui["image"])}
    public static let guestEdgeImage = {swift_string(guest_edge["image"])}
    public static let hostProxyImage = {swift_string(host_proxy["image"])}
    public static let recorderIngressVersion = {swift_string(recorder_ingress["version"])}
    public static let recorderRecoveryVersion = {swift_string(recorder_recovery["version"])}
    public static let vitalDBObserverVersion = {swift_string(vitaldb_observer["version"])}
    public static let redisRelayVersion = {swift_string(redis_relay["version"])}
    public static let labVersion = {swift_string(lab["version"])}
    public static let redisVersion = {swift_string(redis["version"])}
    public static let postgresVersion = {swift_string(postgres["version"])}
    public static let redisUIVersion = {swift_string(redis_ui["version"])}
    public static let swaggerUIVersion = {swift_string(swagger_ui["version"])}
    public static let guestEdgeVersion = {swift_string(guest_edge["version"])}
    public static let hostProxyVersion = {swift_string(host_proxy["version"])}
}}
""",
    )
    write_if_changed(
        root
        / "Sources/Adapters/Inbound/MacControlPanel/Generated"
        / "RuntimeReleaseInfo+Generated.swift",
        f"""// Generated from {release_file.name} by make devtools/release-contract.
// Do not edit this file directly.

import Foundation
import RuntimeControl
import Errors

public extension RuntimeReleaseInfo {{
    static var generated: RuntimeReleaseInfo {{
        let services = [
            RuntimeBundledServiceInfo(
                name: GeneratedRelease.vitalServerName,
                image: GeneratedRelease.vitalServerImage,
                version: GeneratedRelease.vitalServerVersion
            ),
            RuntimeBundledServiceInfo(
                name: GeneratedRelease.recorderIngressName,
                image: GeneratedRelease.recorderIngressImage,
                version: GeneratedRelease.recorderIngressVersion
            ),
            RuntimeBundledServiceInfo(
                name: GeneratedRelease.recorderRecoveryName,
                image: GeneratedRelease.recorderRecoveryImage,
                version: GeneratedRelease.recorderRecoveryVersion
            ),
            RuntimeBundledServiceInfo(
                name: GeneratedRelease.vitalDBObserverName,
                image: GeneratedRelease.vitalDBObserverImage,
                version: GeneratedRelease.vitalDBObserverVersion
            ),
            RuntimeBundledServiceInfo(
                name: GeneratedRelease.redisRelayName,
                image: GeneratedRelease.redisRelayImage,
                version: GeneratedRelease.redisRelayVersion
            ),
            RuntimeBundledServiceInfo(
                name: GeneratedRelease.labName,
                image: GeneratedRelease.labImage,
                version: GeneratedRelease.labVersion
            ),
            RuntimeBundledServiceInfo(
                name: GeneratedRelease.redisName,
                image: GeneratedRelease.redisImage,
                version: GeneratedRelease.redisVersion
            ),
            RuntimeBundledServiceInfo(
                name: GeneratedRelease.postgresName,
                image: GeneratedRelease.postgresImage,
                version: GeneratedRelease.postgresVersion
            ),
            RuntimeBundledServiceInfo(
                name: GeneratedRelease.redisUIName,
                image: GeneratedRelease.redisUIImage,
                version: GeneratedRelease.redisUIVersion
            ),
            RuntimeBundledServiceInfo(
                name: GeneratedRelease.swaggerUIName,
                image: GeneratedRelease.swaggerUIImage,
                version: GeneratedRelease.swaggerUIVersion
            ),
            RuntimeBundledServiceInfo(
                name: GeneratedRelease.guestEdgeName,
                image: GeneratedRelease.guestEdgeImage,
                version: GeneratedRelease.guestEdgeVersion
            ),
            RuntimeBundledServiceInfo(
                name: GeneratedRelease.hostProxyName,
                image: GeneratedRelease.hostProxyImage,
                version: GeneratedRelease.hostProxyVersion
            ),
        ]
        return RuntimeReleaseInfo(
            helperVersion: GeneratedRelease.helperVersion,
            minimumUpdaterVersion: GeneratedRelease.minUpdaterVersion,
            vitalServerVersion: GeneratedRelease.vitalServerVersion,
            services: services
        )
    }}
}}
""",
    )


def sync_release(root, release, release_file):
    validate_release_policy(release)
    validate_release_input_contract(root, release)
    sync_swift(root, release, release_file)


def main():
    if len(sys.argv) not in {2, 3}:
        raise SystemExit("usage: sync-release.py <launcher-dir> [release-file]")
    root = Path(sys.argv[1])
    release_file = Path(sys.argv[2]) if len(sys.argv) == 3 else root / "release.json"
    if not release_file.is_absolute():
        release_file = root / release_file
    release = json.loads(release_file.read_text(encoding="utf-8"))
    sync_release(root, release, release_file)


if __name__ == "__main__":
    main()
