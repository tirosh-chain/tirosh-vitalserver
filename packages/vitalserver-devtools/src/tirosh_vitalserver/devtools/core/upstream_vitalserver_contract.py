from __future__ import annotations

from dataclasses import dataclass
from pathlib import PurePosixPath
from typing import Any, Literal

from tirosh_vitalserver.devtools.core.errors import DomainError

VerificationMode = Literal["approved", "candidate"]


@dataclass(frozen=True)
class ApprovedCommit:
    sha: str
    label: str
    verified_at: str
    notes: str


@dataclass(frozen=True)
class PatternRule:
    id: str
    file: str
    patterns: tuple[str, ...]


@dataclass(frozen=True)
class UpstreamVitalServerContractManifest:
    contract_version: int
    remote: str
    submodule_path: str
    approved_commits: tuple[ApprovedCommit, ...]
    required_files: tuple[str, ...]
    required_contracts: tuple[PatternRule, ...]
    forbidden_markers: tuple[PatternRule, ...]


@dataclass(frozen=True)
class UpstreamVitalServerState:
    submodule_url: str | None
    submodule_url_error: str | None
    commit: str | None
    commit_error: str | None
    dirty_status: str | None
    dirty_status_error: str | None
    files: dict[str, str]
    file_errors: dict[str, str]
    remote_commit_present: bool | None = None
    remote_commit_error: str | None = None


@dataclass(frozen=True)
class VerificationIssue:
    stage: str
    message: str
    file: str | None = None
    rule_id: str | None = None
    expected: str | None = None
    actual: str | None = None
    fix: str | None = None


@dataclass(frozen=True)
class VerificationObservation:
    stage: str
    message: str
    file: str | None = None
    rule_id: str | None = None


@dataclass(frozen=True)
class VerificationResult:
    mode: VerificationMode
    issues: tuple[VerificationIssue, ...]
    observations: tuple[VerificationObservation, ...]

    @property
    def ok(self) -> bool:
        return not self.issues


def manifest_from_dict(data: dict[str, Any]) -> UpstreamVitalServerContractManifest:
    return UpstreamVitalServerContractManifest(
        contract_version=_required_int(data, "contractVersion"),
        remote=_required_str(data, "remote"),
        submodule_path=_required_str(data, "submodulePath"),
        approved_commits=tuple(
            ApprovedCommit(
                sha=_required_str(item, "sha"),
                label=_required_str(item, "label"),
                verified_at=_required_str(item, "verifiedAt"),
                notes=_required_str(item, "notes"),
            )
            for item in _required_list(data, "approvedCommits")
        ),
        required_files=tuple(
            _required_str_item(item, "requiredFiles")
            for item in _required_list(data, "requiredFiles")
        ),
        required_contracts=tuple(
            _pattern_rule(item, "requiredContracts")
            for item in _required_list(data, "requiredContracts")
        ),
        forbidden_markers=tuple(
            _pattern_rule(item, "forbiddenMarkers")
            for item in _required_list(data, "forbiddenMarkers")
        ),
    )


def verify_upstream_vitalserver_contract(
    manifest: UpstreamVitalServerContractManifest,
    state: UpstreamVitalServerState,
    mode: VerificationMode,
    *,
    require_remote_commit: bool = False,
) -> VerificationResult:
    if mode not in ("approved", "candidate"):
        raise DomainError(f"unsupported upstream verification mode: {mode}")

    issues: list[VerificationIssue] = []
    observations: list[VerificationObservation] = []

    _verify_remote(manifest, state, issues, observations)
    _verify_commit(manifest, state, mode, issues, observations)
    if require_remote_commit:
        _verify_remote_commit(manifest, state, issues, observations)
    _verify_dirty_state(state, issues, observations)
    _verify_required_files(manifest, state, issues, observations)
    _verify_required_contracts(manifest, state, issues, observations)
    _verify_forbidden_markers(manifest, state, issues, observations)

    return VerificationResult(
        mode=mode,
        issues=tuple(issues),
        observations=tuple(observations),
    )


def _verify_remote(
    manifest: UpstreamVitalServerContractManifest,
    state: UpstreamVitalServerState,
    issues: list[VerificationIssue],
    observations: list[VerificationObservation],
) -> None:
    if state.submodule_url_error:
        issues.append(
            VerificationIssue(
                stage="remote",
                message="could not read upstream submodule URL",
                expected=manifest.remote,
                actual=state.submodule_url_error,
                fix=(
                    "Repair .gitmodules or initialize vendor/vitalserver "
                    "before release verification."
                ),
            )
        )
        return
    if state.submodule_url != manifest.remote:
        issues.append(
            VerificationIssue(
                stage="remote",
                message="unexpected upstream submodule URL",
                expected=manifest.remote,
                actual=state.submodule_url,
                fix=(
                    "Point vendor/vitalserver at the original "
                    "vitaldb/vitalserver remote."
                ),
            )
        )
        return
    observations.append(
        VerificationObservation(
            stage="remote",
            message=f"upstream remote {state.submodule_url}",
        )
    )


def _verify_commit(
    manifest: UpstreamVitalServerContractManifest,
    state: UpstreamVitalServerState,
    mode: VerificationMode,
    issues: list[VerificationIssue],
    observations: list[VerificationObservation],
) -> None:
    approved = {commit.sha: commit for commit in manifest.approved_commits}
    if state.commit_error:
        issues.append(
            VerificationIssue(
                stage="commit",
                message="could not read upstream submodule commit",
                actual=state.commit_error,
                fix=(
                    "Initialize vendor/vitalserver and ensure the submodule "
                    "checkout is readable."
                ),
            )
        )
        return
    if not state.commit:
        issues.append(
            VerificationIssue(
                stage="commit",
                message="upstream submodule commit is missing",
                fix="Initialize vendor/vitalserver before release verification.",
            )
        )
        return
    if state.commit in approved:
        observations.append(
            VerificationObservation(
                stage="commit",
                message=(
                    f"upstream commit {state.commit} approved "
                    f"({approved[state.commit].label})"
                ),
            )
        )
        return
    message = f"upstream commit {state.commit} is not in approvedCommits"
    if mode == "approved":
        issues.append(
            VerificationIssue(
                stage="commit",
                message=message,
                expected=", ".join(sorted(approved)),
                actual=state.commit,
                fix=(
                    "Run candidate verification, runtime smoke, and add the "
                    "commit to config/upstream-vitalserver-contract.json if "
                    "approved."
                ),
            )
        )
    else:
        observations.append(
            VerificationObservation(stage="commit", message=f"candidate: {message}")
        )


def _verify_remote_commit(
    manifest: UpstreamVitalServerContractManifest,
    state: UpstreamVitalServerState,
    issues: list[VerificationIssue],
    observations: list[VerificationObservation],
) -> None:
    if state.commit_error or not state.commit:
        return
    if state.remote_commit_error:
        issues.append(
            VerificationIssue(
                stage="remote-commit",
                message="could not verify upstream commit against remote",
                expected=f"{manifest.remote} contains {state.commit}",
                actual=state.remote_commit_error,
                fix=(
                    "Retry with network access or verify the candidate commit "
                    "exists in the original upstream remote before approval."
                ),
            )
        )
        return
    if state.remote_commit_present is not True:
        issues.append(
            VerificationIssue(
                stage="remote-commit",
                message="upstream candidate commit is not present in remote",
                expected=f"{manifest.remote} contains {state.commit}",
                actual=str(state.remote_commit_present),
                fix=(
                    "Use a commit reachable from the original upstream remote, "
                    "not a local-only or fork-only commit."
                ),
            )
        )
        return
    observations.append(
        VerificationObservation(
            stage="remote-commit",
            message=f"upstream remote contains commit {state.commit}",
        )
    )


def _verify_dirty_state(
    state: UpstreamVitalServerState,
    issues: list[VerificationIssue],
    observations: list[VerificationObservation],
) -> None:
    if state.dirty_status_error:
        issues.append(
            VerificationIssue(
                stage="dirty-submodule",
                message="could not read upstream submodule dirty state",
                actual=state.dirty_status_error,
                fix="Ensure vendor/vitalserver is a readable git checkout.",
            )
        )
        return
    if state.dirty_status:
        issues.append(
            VerificationIssue(
                stage="dirty-submodule",
                message="upstream submodule has uncommitted changes",
                actual=state.dirty_status,
                fix=(
                    "Commit, discard, or move local vendor/vitalserver changes "
                    "before release verification."
                ),
            )
        )
        return
    observations.append(
        VerificationObservation(
            stage="dirty-submodule",
            message="upstream submodule is clean",
        )
    )


def _verify_required_files(
    manifest: UpstreamVitalServerContractManifest,
    state: UpstreamVitalServerState,
    issues: list[VerificationIssue],
    observations: list[VerificationObservation],
) -> None:
    for file in manifest.required_files:
        if file in state.file_errors:
            issues.append(
                VerificationIssue(
                    stage="required-file",
                    message="required upstream file is not readable",
                    file=file,
                    actual=state.file_errors[file],
                    fix="Pin vendor/vitalserver to a compatible upstream layout.",
                )
            )
            continue
        if file not in state.files:
            issues.append(
                VerificationIssue(
                    stage="required-file",
                    message="required upstream file is missing",
                    file=file,
                    fix="Pin vendor/vitalserver to a compatible upstream layout.",
                )
            )
            continue
        observations.append(
            VerificationObservation(
                stage="required-file",
                message="required file present",
                file=file,
            )
        )


def _verify_required_contracts(
    manifest: UpstreamVitalServerContractManifest,
    state: UpstreamVitalServerState,
    issues: list[VerificationIssue],
    observations: list[VerificationObservation],
) -> None:
    for rule in manifest.required_contracts:
        content = state.files.get(rule.file)
        if content is None:
            continue
        missing = [pattern for pattern in rule.patterns if pattern not in content]
        if missing:
            issues.append(
                VerificationIssue(
                    stage="required-contract",
                    message="required upstream contract pattern is missing",
                    file=rule.file,
                    rule_id=rule.id,
                    expected=", ".join(rule.patterns),
                    actual=f"missing: {', '.join(missing)}",
                    fix=(
                        "Review the upstream change and update Helper integration "
                        "only with an intentional contract migration."
                    ),
                )
            )
            continue
        observations.append(
            VerificationObservation(
                stage="required-contract",
                message="contract present",
                file=rule.file,
                rule_id=rule.id,
            )
        )


def _verify_forbidden_markers(
    manifest: UpstreamVitalServerContractManifest,
    state: UpstreamVitalServerState,
    issues: list[VerificationIssue],
    observations: list[VerificationObservation],
) -> None:
    for rule in manifest.forbidden_markers:
        content = state.files.get(rule.file)
        if content is None:
            continue
        found = [pattern for pattern in rule.patterns if pattern in content]
        if found:
            issues.append(
                VerificationIssue(
                    stage="forbidden-marker",
                    message="forbidden upstream patch marker is present",
                    file=rule.file,
                    rule_id=rule.id,
                    expected="absent",
                    actual=", ".join(found),
                    fix=(
                        "Keep VRecorder IP correction in the recorder ingress, "
                        "not in upstream VitalServer."
                    ),
                )
            )
            continue
        observations.append(
            VerificationObservation(
                stage="forbidden-marker",
                message="forbidden marker absent",
                file=rule.file,
                rule_id=rule.id,
            )
        )


def manifest_files(manifest: UpstreamVitalServerContractManifest) -> tuple[str, ...]:
    files = set(manifest.required_files)
    files.update(rule.file for rule in manifest.required_contracts)
    files.update(rule.file for rule in manifest.forbidden_markers)
    return tuple(sorted(files, key=lambda value: PurePosixPath(value).parts))


def _pattern_rule(data: Any, field: str) -> PatternRule:
    if not isinstance(data, dict):
        raise DomainError(f"{field} entries must be objects")
    patterns = tuple(
        _required_str_item(item, f"{field}.patterns")
        for item in _required_list(data, "patterns")
    )
    if not patterns:
        raise DomainError(f"{field} entry must declare at least one pattern")
    return PatternRule(
        id=_required_str(data, "id"),
        file=_required_str(data, "file"),
        patterns=patterns,
    )


def _required_int(data: dict[str, Any], key: str) -> int:
    value = data.get(key)
    if not isinstance(value, int):
        raise DomainError(f"manifest field {key} must be an integer")
    return value


def _required_str(data: dict[str, Any], key: str) -> str:
    value = data.get(key)
    if not isinstance(value, str) or not value:
        raise DomainError(f"manifest field {key} must be a non-empty string")
    return value


def _required_list(data: dict[str, Any], key: str) -> list[Any]:
    value = data.get(key)
    if not isinstance(value, list):
        raise DomainError(f"manifest field {key} must be a list")
    return value


def _required_str_item(value: Any, field: str) -> str:
    if not isinstance(value, str) or not value:
        raise DomainError(f"{field} entries must be non-empty strings")
    return value
