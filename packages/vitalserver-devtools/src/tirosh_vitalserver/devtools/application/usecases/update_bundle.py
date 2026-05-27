from __future__ import annotations

from tirosh_vitalserver.devtools.adapters.update_bundle.bundle_service import (
    build_bundle,
    verify_bundle,
)
from tirosh_vitalserver.devtools.application.inputs import (
    BuildUpdateBundleInput,
    VerifyUpdateBundleInput,
)


def build_update_bundle(input: BuildUpdateBundleInput) -> int:
    result = build_bundle(input)
    print(f"update bundle is ready: {result.archive}")
    return 0


def verify_update_bundle(input: VerifyUpdateBundleInput) -> int:
    verify_bundle(input.bundle_path)
    print(f"update bundle verified: {input.bundle_path}")
    return 0
