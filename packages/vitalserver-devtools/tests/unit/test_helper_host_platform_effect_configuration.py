from __future__ import annotations

import json
from pathlib import Path

import pytest

from tirosh_vitalserver.devtools.adapters.macos_release import (
    helper_host_platform_installation,
)
from tirosh_vitalserver.devtools.application.usecases import (
    helper_host_platform_effect_configuration,
)
from tirosh_vitalserver.devtools.core.errors import DomainError
from tirosh_vitalserver.devtools.core.helper_host_platform_installation import (
    HOST_PLATFORM_EFFECT_CONFIGURATION_SCHEMA,
    HostReleaseTransition,
    make_layer_effect_configuration,
)


def test_composes_explicit_apply_and_rollback_owner_configuration(
    tmp_path: Path,
) -> None:
    output = tmp_path / "host-effect.json"
    result = helper_host_platform_effect_configuration.compose(
        helper_host_platform_effect_configuration.HelperHostPlatformEffectConfigurationInput(
            effect_executor_id="helper-host-platform-effect-executor",
            manager_executable_path=(
                "/usr/local/bin/vitalserver-host-installation-manager"
            ),
            database_path=(
                "/Library/Application Support/VitalServerHelper/"
                "update-manager/state.sqlite"
            ),
            installation_root=(
                "/Library/Application Support/VitalServerHelper/host-platform"
            ),
            exchange_root=(
                "/Library/Application Support/VitalServerHelper/update-manager/exchange"
            ),
            installation_id="installation-42",
            apply_revision=4,
            apply_release_id="release-0.2.2",
            apply_release_version="0.2.2",
            apply_slot_relative_path="releases/release-0.2.2",
            rollback_revision=5,
            rollback_release_id="release-0.2.1",
            rollback_release_version="0.2.1",
            rollback_slot_relative_path="releases/release-0.2.1",
            output=output,
        ),
        helper_host_platform_effect_configuration.HelperHostPlatformEffectConfigurationOperations(
            write_document=(helper_host_platform_installation.write_json_document),
        ),
    )

    assert result == 0
    document = json.loads(output.read_text(encoding="utf-8"))
    assert document["schemaVersion"] == HOST_PLATFORM_EFFECT_CONFIGURATION_SCHEMA
    assert document["apply"] == {
        "installationId": "installation-42",
        "expectedInstallationRevision": 4,
        "targetReleaseId": "release-0.2.2",
        "targetReleaseVersion": "0.2.2",
        "targetSlotRelativePath": "releases/release-0.2.2",
    }
    assert document["rollback"] == {
        "installationId": "installation-42",
        "expectedInstallationRevision": 5,
        "targetReleaseId": "release-0.2.1",
        "targetReleaseVersion": "0.2.1",
        "targetSlotRelativePath": "releases/release-0.2.1",
    }


def test_rejects_nonconsecutive_owner_revision() -> None:
    with pytest.raises(
        DomainError,
        match=("rollback installation revision must immediately follow apply revision"),
    ):
        make_layer_effect_configuration(
            effect_executor_id="helper-host-platform-effect-executor",
            manager_executable_path="/usr/local/bin/manager",
            database_path="/product/update-manager/state.sqlite",
            installation_root="/product/host-platform",
            exchange_root="/product/update-manager/exchange",
            apply=HostReleaseTransition(
                installation_id="installation-42",
                expected_installation_revision=4,
                release_id="release-0.2.2",
                version="0.2.2",
                slot_relative_path="releases/release-0.2.2",
            ),
            rollback=HostReleaseTransition(
                installation_id="installation-42",
                expected_installation_revision=6,
                release_id="release-0.2.1",
                version="0.2.1",
                slot_relative_path="releases/release-0.2.1",
            ),
        )
