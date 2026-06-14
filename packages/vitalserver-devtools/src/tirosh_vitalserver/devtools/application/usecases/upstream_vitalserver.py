from __future__ import annotations

import json

from tirosh_vitalserver.devtools.adapters.toolchain.upstream_vitalserver import (
    read_upstream_vitalserver_state,
)
from tirosh_vitalserver.devtools.adapters.toolchain.workspace_paths import repo_root
from tirosh_vitalserver.devtools.application.inputs import (
    VerifyUpstreamVitalServerInput,
)
from tirosh_vitalserver.devtools.core.errors import DomainError
from tirosh_vitalserver.devtools.core.upstream_vitalserver_contract import (
    VerificationIssue,
    VerificationMode,
    VerificationResult,
    manifest_from_dict,
    verify_upstream_vitalserver_contract,
)


def verify_upstream_vitalserver(input: VerifyUpstreamVitalServerInput) -> int:
    root = repo_root()
    manifest_path = input.manifest or root / "config/upstream-vitalserver-contract.json"
    try:
        raw_manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        if not isinstance(raw_manifest, dict):
            raise DomainError("manifest root must be an object")
        manifest = manifest_from_dict(raw_manifest)
    except FileNotFoundError:
        result = VerificationResult(
            mode=input.mode,
            issues=(
                VerificationIssue(
                    stage="manifest-read",
                    message="upstream contract manifest is missing",
                    file=str(manifest_path),
                    fix=(
                        "Create config/upstream-vitalserver-contract.json "
                        "before release verification."
                    ),
                ),
            ),
            observations=(),
        )
        _print_result(result)
        return 1
    except (OSError, json.JSONDecodeError, DomainError) as error:
        result = VerificationResult(
            mode=input.mode,
            issues=(
                VerificationIssue(
                    stage="manifest-read",
                    message="upstream contract manifest is invalid",
                    file=str(manifest_path),
                    actual=f"{type(error).__name__}: {error}",
                    fix="Fix the upstream contract manifest schema or JSON syntax.",
                ),
            ),
            observations=(),
        )
        _print_result(result)
        return 1

    state = read_upstream_vitalserver_state(root, manifest)
    result = verify_upstream_vitalserver_contract(manifest, state, input.mode)
    _print_result(result)
    return 0 if result.ok else 1


def _print_result(result: VerificationResult) -> None:
    print(f"upstream vitalserver verification mode={result.mode}")
    for observation in result.observations:
        suffix = ""
        if observation.rule_id:
            suffix += f" rule={observation.rule_id}"
        if observation.file:
            suffix += f" file={observation.file}"
        print(f"ok: {observation.stage}: {observation.message}{suffix}")
    for issue in result.issues:
        print(f"failed: {issue.message}")
        print(f"stage: {issue.stage}")
        if issue.rule_id:
            print(f"rule: {issue.rule_id}")
        if issue.file:
            print(f"file: {issue.file}")
        if issue.expected:
            print(f"expected: {issue.expected}")
        if issue.actual:
            print(f"actual: {issue.actual}")
        if issue.fix:
            print(f"fix: {issue.fix}")


def parse_verification_mode(value: str) -> VerificationMode:
    if value not in ("approved", "candidate"):
        raise DomainError(f"unsupported upstream verification mode: {value}")
    return value
