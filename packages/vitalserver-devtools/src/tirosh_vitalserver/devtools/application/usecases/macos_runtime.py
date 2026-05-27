from __future__ import annotations

from tirosh_vitalserver.devtools.adapters.macos_release.runtime_lifecycle import (
    build_runtime,
    check_runtime_health,
    control_runtime,
    print_runtime_ip,
    require_bridged_codesign_identity,
    sign_runtime,
    start_runtime_detached,
    sync_runtime_release_sources,
    wait_for_rootfs_ready,
    wait_for_runtime_http,
    wait_for_runtime_ip,
)
from tirosh_vitalserver.devtools.application.inputs import (
    RequireBridgedIdentityInput,
    RuntimeBuildInput,
    RuntimeControlInput,
    RuntimeHealthInput,
    RuntimeSignInput,
    RuntimeSyncReleaseInput,
    RuntimeVmHomeInput,
    RuntimeWaitInput,
)


def build(input: RuntimeBuildInput) -> int:
    return build_runtime(input)


def sync_release_sources(
    input: RuntimeSyncReleaseInput,
) -> int:
    return sync_runtime_release_sources(input)


def sign(input: RuntimeSignInput) -> int:
    return sign_runtime(input)


def require_bridged_identity(
    input: RequireBridgedIdentityInput,
) -> int:
    return require_bridged_codesign_identity(input)


def control(input: RuntimeControlInput) -> int:
    return control_runtime(input)


def start_detached(input: RuntimeVmHomeInput) -> int:
    return start_runtime_detached(input)


def print_ip(input: RuntimeVmHomeInput) -> int:
    return print_runtime_ip(input)


def wait_ip(input: RuntimeWaitInput) -> int:
    return wait_for_runtime_ip(input)


def wait_http(input: RuntimeWaitInput) -> int:
    return wait_for_runtime_http(input)


def wait_rootfs_ready(input: RuntimeWaitInput) -> int:
    return wait_for_rootfs_ready(input)


def health(input: RuntimeHealthInput) -> int:
    return check_runtime_health(input)
