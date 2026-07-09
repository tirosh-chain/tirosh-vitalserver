from __future__ import annotations

import time

from tirosh_guest_tools.adapters.outbound.runtime.observation_writer import (
    write_runtime_observation,
)
from tirosh_guest_tools.contracts import (
    RuntimeBootstrapEvidenceFileName,
    RuntimeDiagnosticsArtifactFileName,
)
from tirosh_guest_tools.domain.errors import GuestUseCaseInputError
from tirosh_guest_tools.domain.operations import RuntimeObservationAction
from tirosh_guest_tools.infrastructure.common import (
    RUNTIME_DIR,
    mount_runtime_share,
)
from tirosh_guest_tools.infrastructure.settings import SETTINGS

RUNTIME_OBSERVATION_FILE = (
    RUNTIME_DIR / RuntimeDiagnosticsArtifactFileName.RUNTIME_OBSERVATION.value
)
VM_IP_FILE = RUNTIME_DIR / RuntimeBootstrapEvidenceFileName.VM_IP.value


def run_runtime_observation_action(action: RuntimeObservationAction | str) -> None:
    action = RuntimeObservationAction(action)
    mount_runtime_share()
    if action == RuntimeObservationAction.ONCE:
        write_runtime_observation_outputs()
        return
    if action != RuntimeObservationAction.WATCH:
        raise GuestUseCaseInputError(
            f"unsupported runtime observation action: {action}",
            code="runtime-observation-action-unsupported",
        )
    while True:
        write_runtime_observation_outputs()
        time.sleep(max(SETTINGS.intervals.runtime_observation_seconds, 1))


def write_runtime_observation_outputs() -> None:
    write_runtime_observation(RUNTIME_OBSERVATION_FILE, vm_ip_file=VM_IP_FILE)
