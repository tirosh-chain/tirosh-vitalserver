from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path

from tirosh_vitalserver.devtools.core.update_bootstrap_bundle_models import (
    BuildUpdateBootstrapBundleInput,
    BuildUpdateBootstrapBundleResult,
    VerifyUpdateBootstrapBundleInput,
)


@dataclass(frozen=True)
class UpdateBootstrapBundleOperations:
    build_bundle: Callable[
        [BuildUpdateBootstrapBundleInput],
        BuildUpdateBootstrapBundleResult,
    ]
    verify_bundle: Callable[[Path, Path], None]


def build(
    input: BuildUpdateBootstrapBundleInput,
    operations: UpdateBootstrapBundleOperations,
) -> int:
    result = operations.build_bundle(input)
    print(
        "update bootstrap bundle is ready: "
        f"{result.archive} envelopeSHA256={result.envelope_sha256}"
    )
    return 0


def verify(
    input: VerifyUpdateBootstrapBundleInput,
    operations: UpdateBootstrapBundleOperations,
) -> int:
    operations.verify_bundle(
        input.bundle,
        input.publisher_trust_store,
    )
    print(f"update bootstrap bundle is verified: {input.bundle}")
    return 0
