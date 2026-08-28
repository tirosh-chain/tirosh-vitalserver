from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path

from tirosh_vitalserver.devtools.core.helper_host_platform_installation import (
    HostReleaseTransition,
    make_layer_effect_configuration,
)


@dataclass(frozen=True)
class HelperHostPlatformEffectConfigurationInput:
    effect_executor_id: str
    manager_executable_path: str
    database_path: str
    installation_root: str
    exchange_root: str
    installation_id: str
    apply_revision: int
    apply_release_id: str
    apply_release_version: str
    apply_slot_relative_path: str
    rollback_revision: int
    rollback_release_id: str
    rollback_release_version: str
    rollback_slot_relative_path: str
    output: Path


@dataclass(frozen=True)
class HelperHostPlatformEffectConfigurationOperations:
    write_document: Callable[[Path, dict[str, object]], None]


def compose(
    input: HelperHostPlatformEffectConfigurationInput,
    operations: HelperHostPlatformEffectConfigurationOperations,
) -> int:
    document = make_layer_effect_configuration(
        effect_executor_id=input.effect_executor_id,
        manager_executable_path=input.manager_executable_path,
        database_path=input.database_path,
        installation_root=input.installation_root,
        exchange_root=input.exchange_root,
        apply=HostReleaseTransition(
            installation_id=input.installation_id,
            expected_installation_revision=input.apply_revision,
            release_id=input.apply_release_id,
            version=input.apply_release_version,
            slot_relative_path=input.apply_slot_relative_path,
        ),
        rollback=HostReleaseTransition(
            installation_id=input.installation_id,
            expected_installation_revision=input.rollback_revision,
            release_id=input.rollback_release_id,
            version=input.rollback_release_version,
            slot_relative_path=input.rollback_slot_relative_path,
        ),
    )
    operations.write_document(input.output, document)
    print(f"Helper Host Platform layer effect configuration is ready: {input.output}")
    return 0
