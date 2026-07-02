#!/usr/bin/env python3
# ruff: noqa: E501
import json
import re
import sys
from pathlib import Path


def require_service(release, key):
    try:
        return release["services"][key]
    except KeyError as error:
        raise SystemExit(f"missing release service field: {key}.{error}") from error


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


def replace(pattern, replacement, content):
    next_content, count = re.subn(
        pattern,
        replacement,
        content,
        count=1,
        flags=re.MULTILINE,
    )
    if count != 1:
        raise SystemExit(f"release sync pattern did not match: {pattern}")
    return next_content


def replace_optional(pattern, replacement, content):
    next_content, count = re.subn(
        pattern,
        replacement,
        content,
        count=1,
        flags=re.MULTILINE,
    )
    if count > 1:
        raise SystemExit(f"release sync pattern matched too many times: {pattern}")
    return next_content


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
    for service in optional_services:
        require_field(release, f"services.{service}.displayName")
        require_field(release, f"services.{service}.image")
        require_field(release, f"services.{service}.version")
    require_field(release, "services.lab.displayName")
    require_field(release, "services.lab.image")
    require_field(release, "services.lab.version")


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
        f"""// Generated from {release_file.name} by make vm-version-source.
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
        f"""// Generated from {release_file.name} by make vm-version-source.
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
        f"""// Generated from {release_file.name} by make vm-version-source.
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


def sync_compose(root, release):
    compose = root / "Support/Guest/compose.yaml"
    content = compose.read_text(encoding="utf-8")
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
    replacements = {
        r"image: redis:[^\n]+": f"image: {redis['image']}",
        r"image: postgres:[^\n]+": f"image: {postgres['image']}",
        r"image: vitalserver:[^\n]+": f"image: {vitalserver['image']}",
        r"image: vitalserver-recorder-ingress:[^\n]+": (
            f"image: {recorder_ingress['image']}"
        ),
        r"image: vitalserver-recorder-recovery:[^\n]+": (
            f"image: {recorder_recovery['image']}"
        ),
        r"image: vitaldb-observer:[^\n]+": f"image: {vitaldb_observer['image']}",
        r"image: vitalserver-redis-relay:[^\n]+": (
            f"image: {redis_relay['image']}"
        ),
        r"image: vitalserver-lab:[^\n]+": f"image: {lab['image']}",
        r"image: ghcr\.io/joeferner/redis-commander:[^\n]+": (
            f"image: {redis_ui['image']}"
        ),
        r"image: swaggerapi/swagger-ui:[^\n]+": (
            f"image: {swagger_ui['image']}"
        ),
        r"image: nginx:[^\n]+": f"image: {guest_edge['image']}",
    }
    for pattern, replacement in replacements.items():
        content = replace(pattern, replacement, content)
    write_if_changed(compose, content)


def sync_build_config(root, release):
    config = root.parent.parent / "config/vm-build.toml"
    content = config.read_text(encoding="utf-8")
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
    replacements = {
        r'"vitalserver:[^"]+"': f'"{vitalserver["image"]}"',
        r'\n  "vitalserver-recorder-ingress:[^"]+"': f'\n  "{recorder_ingress["image"]}"',
        r'\n  "vitalserver-recorder-recovery:[^"]+"': f'\n  "{recorder_recovery["image"]}"',
        r'\n  "vitaldb-observer:[^"]+"': f'\n  "{vitaldb_observer["image"]}"',
        r'\n  "vitalserver-redis-relay:[^"]+"': f'\n  "{redis_relay["image"]}"',
        r'\n  "vitalserver-lab:[^"]+"': f'\n  "{lab["image"]}"',
        r'recorder_ingress_image = "vitalserver-recorder-ingress:[^"]+"': (
            f'recorder_ingress_image = "{recorder_ingress["image"]}"'
        ),
        r'recorder_recovery_image = "vitalserver-recorder-recovery:[^"]+"': (
            f'recorder_recovery_image = "{recorder_recovery["image"]}"'
        ),
        r'vitaldb_observer_image = "vitaldb-observer:[^"]+"': (
            f'vitaldb_observer_image = "{vitaldb_observer["image"]}"'
        ),
        r'redis_relay_image = "vitalserver-redis-relay:[^"]+"': (
            f'redis_relay_image = "{redis_relay["image"]}"'
        ),
        r'lab_image = "vitalserver-lab:[^"]+"': (
            f'lab_image = "{lab["image"]}"'
        ),
        r'"redis:[^"]+"': f'"{redis["image"]}"',
        r'"postgres:[^"]+"': f'"{postgres["image"]}"',
        r'"ghcr\.io/joeferner/redis-commander:[^"]+"': (
            f'"{redis_ui["image"]}"'
        ),
        r'"swaggerapi/swagger-ui:[^"]+"': f'"{swagger_ui["image"]}"',
        r'"nginx:[^"]+"': f'"{guest_edge["image"]}"',
    }
    for pattern, replacement in replacements.items():
        content = replace(pattern, replacement, content)
    content = replace_optional(
        r'\nexpected_version = "nginx/[^"]+"',
        "",
        content,
    )
    write_if_changed(config, content)


def sync_guest_scripts(root, release):
    bootstrap_operations = (
        root.parent.parent
        / "packages/vitalserver-guest-tools/src/tirosh_guest_tools/infrastructure"
        / "bootstrap_operations.py"
    )
    content = bootstrap_operations.read_text(encoding="utf-8")
    content = replace(
        r'\("vitalserver:[^"]+", "app"\)',
        f'("{require_service(release, "vitalServer")["image"]}", "app")',
        content,
    )
    content = replace(
        r'\("vitalserver-recorder-ingress:[^"]+", "recorder-ingress"\)',
        (
            f'("{require_service(release, "recorderIngress")["image"]}", '
            '"recorder-ingress")'
        ),
        content,
    )
    write_if_changed(bootstrap_operations, content)

    repair_datastore = (
        root.parent.parent
        / "packages/vitalserver-guest-tools/src/tirosh_guest_tools/application"
        / "redis_repair.py"
    )
    content = repair_datastore.read_text(encoding="utf-8")
    content = replace(
        r'"redis:[^"]+",',
        f'"{require_service(release, "redis")["image"]}",',
        content,
    )
    write_if_changed(repair_datastore, content)


def main():
    if len(sys.argv) not in {2, 3}:
        raise SystemExit("usage: sync-release.py <launcher-dir> [release-file]")
    root = Path(sys.argv[1])
    release_file = Path(sys.argv[2]) if len(sys.argv) == 3 else root / "release.json"
    if not release_file.is_absolute():
        release_file = root / release_file
    release = json.loads(release_file.read_text(encoding="utf-8"))
    validate_release_policy(release)
    sync_swift(root, release, release_file)
    sync_compose(root, release)
    sync_build_config(root, release)
    sync_guest_scripts(root, release)


if __name__ == "__main__":
    main()
