from __future__ import annotations

from collections.abc import Callable
from contextlib import AbstractContextManager
from dataclasses import dataclass
from pathlib import Path

from tirosh_vitalserver.devtools.application.inputs import (
    ComposeHelperStableUpdateReleaseInput,
    HelperStableUpdateLayerArtifactInput,
    MaterializedHelperUpdatePayload,
)
from tirosh_vitalserver.devtools.core.errors import DomainError
from tirosh_vitalserver.devtools.core.helper_stable_update_release import (
    encode_helper_stable_update_specification,
)
from tirosh_vitalserver.devtools.core.helper_stable_update_release_models import (
    HelperStableUpdateReleasePlan,
)
from tirosh_vitalserver.devtools.core.update_bootstrap_bundle_models import (
    BuildUpdateBootstrapBundleInput,
    BuildUpdateBootstrapBundleResult,
)


@dataclass(frozen=True)
class HelperStableUpdateReleaseOperations:
    materialize_payload: Callable[
        [tuple[HelperStableUpdateLayerArtifactInput, ...]],
        AbstractContextManager[MaterializedHelperUpdatePayload],
    ]
    build_bundle: Callable[
        [BuildUpdateBootstrapBundleInput],
        BuildUpdateBootstrapBundleResult,
    ]
    require_active_publisher_key: Callable[[Path, str], bytes]


def compose(
    input: ComposeHelperStableUpdateReleaseInput,
    operations: HelperStableUpdateReleaseOperations,
) -> int:
    operations.require_active_publisher_key(
        input.publisher_trust_store,
        input.publisher_key_id,
    )
    with operations.materialize_payload(input.layers) as payload:
        plan = HelperStableUpdateReleasePlan(
            update_id=input.update_id,
            specification_id=input.specification_id,
            layers=payload.layers,
        )
        specification = payload.root / "update-specification.json"
        try:
            specification.write_bytes(encode_helper_stable_update_specification(plan))
        except OSError as error:
            raise DomainError(
                "Helper stable update specification write failed "
                f"path={specification}: {error}"
            ) from error
        result = operations.build_bundle(
            BuildUpdateBootstrapBundleInput(
                update_id=input.update_id,
                product_version=input.product_version,
                runtime_version=input.runtime_version,
                target_platform=input.target_platform,
                target_architecture=input.target_architecture,
                layer_order=[layer.layer.value for layer in payload.layers],
                next_updater=input.next_updater,
                specification=specification,
                payload_root=payload.root,
                publisher_key_id=input.publisher_key_id,
                publisher_private_key=input.publisher_private_key,
                issued_at=input.issued_at,
                output=input.output,
            )
        )
    print(
        "Helper stable update release is ready: "
        f"{result.archive} envelopeSHA256={result.envelope_sha256}"
    )
    return 0
