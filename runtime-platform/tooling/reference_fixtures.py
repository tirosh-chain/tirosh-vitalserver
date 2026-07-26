"""Verification for quarantined, sanitized legacy behavior fixtures."""

from __future__ import annotations

import hashlib
import json
import re
from dataclasses import dataclass
from datetime import date
from pathlib import Path
from typing import Any, Iterable, List, Mapping, Sequence


FIXTURE_ROOT = Path("acceptance/reference-fixtures")
MANIFEST_NAME = "manifest.v1.json"
COLLECTION_NAME = "runtime-platform-reference-fixtures"
SCHEMA_VERSION = "v1"
FIXTURE_CLASSIFICATIONS = frozenset(
    {
        "legacy-wire-observation",
        "legacy-outcome-observation",
    }
)
FIXTURE_KINDS = frozenset(
    {
        "socketio-frame-observation",
        "ingress-outcome-observation",
        "replay-outcome-observation",
        "vital-file-upload-observation",
    }
)
NEW_PLATFORM_USES = frozenset(
    {
        "protocol-spike",
        "acceptance-oracle",
        "negative-oracle",
    }
)
CONTRACT_IDS = frozenset({"C1", "C2", "C3", "C4", "C5", "C6"})
ENTRY_KEYS = frozenset(
    {
        "id",
        "path",
        "sha256",
        "capturedAt",
        "classification",
        "source",
        "sanitization",
        "newPlatformUse",
        "vnextMapping",
    }
)
SOURCE_KEYS = frozenset({"repository", "revision", "path", "locator"})
SANITIZATION_KEYS = frozenset(
    {
        "rawProtocolContent",
        "patientData",
        "networkAddress",
        "secretMaterial",
    }
)
VNEXT_MAPPING_KEYS = frozenset({"contract", "purpose"})
FORBIDDEN_FIXTURE_KEYS = frozenset(
    {
        "accesstoken",
        "authorization",
        "credential",
        "filecontents",
        "ipaddress",
        "patient",
        "patientid",
        "patientname",
        "payload",
        "payloadbase64",
        "rawbytes",
        "rawpacket",
        "rawprotocolcontent",
        "privatekey",
        "rawframe",
        "rawpayload",
        "secret",
        "waveform",
    }
)
IDENTIFIER = re.compile(r"^[a-z][a-z0-9-]{2,127}$")
SHA256 = re.compile(r"^[0-9a-f]{64}$")
GIT_REVISION = re.compile(r"^[0-9a-f]{40}$")


@dataclass(frozen=True)
class FixtureFinding:
    """One explicit failure in the frozen-reference-fixture collection."""

    code: str
    location: str
    message: str

    def render(self) -> str:
        return "[{0}] {1}: {2}".format(self.code, self.location, self.message)


def _location(path: Path, fixtures_root: Path) -> str:
    try:
        return path.relative_to(fixtures_root).as_posix()
    except ValueError:
        return str(path)


def _read_json_object(path: Path, fixtures_root: Path) -> tuple[Mapping[str, Any] | None, List[FixtureFinding]]:
    try:
        document = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        return None, [
            FixtureFinding(
                "fixture-json-unreadable",
                _location(path, fixtures_root),
                "could not read JSON object: {0}".format(error),
            )
        ]
    if not isinstance(document, dict):
        return None, [
            FixtureFinding(
                "fixture-json-not-object",
                _location(path, fixtures_root),
                "JSON document must be an object",
            )
        ]
    return document, []


def _validate_exact_keys(
    document: Mapping[str, Any],
    expected: frozenset[str],
    location: str,
    findings: List[FixtureFinding],
) -> None:
    actual = set(document.keys())
    missing = sorted(expected - actual)
    unexpected = sorted(actual - expected)
    if missing:
        findings.append(
            FixtureFinding(
                "fixture-metadata-missing",
                location,
                "missing required fields: {0}".format(", ".join(missing)),
            )
        )
    if unexpected:
        findings.append(
            FixtureFinding(
                "fixture-metadata-unknown",
                location,
                "unknown fields are not allowed: {0}".format(", ".join(unexpected)),
            )
        )


def _path_is_within(path: Path, directory: Path) -> bool:
    try:
        path.relative_to(directory)
    except ValueError:
        return False
    return True


def _normalized_key(key: str) -> str:
    return re.sub(r"[^a-z0-9]", "", key.lower())


def _prohibited_key_findings(value: Any, location: str) -> Iterable[FixtureFinding]:
    if isinstance(value, dict):
        for key, child in value.items():
            child_location = "{0}/{1}".format(location, key)
            if _normalized_key(key) in FORBIDDEN_FIXTURE_KEYS:
                yield FixtureFinding(
                    "fixture-prohibited-key",
                    child_location,
                    "sanitized fixtures must not retain raw or sensitive data fields",
                )
            yield from _prohibited_key_findings(child, child_location)
    elif isinstance(value, list):
        for index, child in enumerate(value):
            yield from _prohibited_key_findings(child, "{0}/{1}".format(location, index))


def _validate_fixture_document(
    document: Mapping[str, Any], path: Path, fixtures_root: Path
) -> List[FixtureFinding]:
    location = _location(path, fixtures_root)
    findings = list(_prohibited_key_findings(document, location))

    if document.get("schemaVersion") != SCHEMA_VERSION:
        findings.append(
            FixtureFinding(
                "fixture-schema-version-invalid",
                location,
                "fixture schemaVersion must be {0}".format(SCHEMA_VERSION),
            )
        )
    fixture_kind = document.get("fixtureKind")
    if fixture_kind not in FIXTURE_KINDS:
        findings.append(
            FixtureFinding(
                "fixture-kind-invalid",
                location,
                "fixtureKind must be one of: {0}".format(", ".join(sorted(FIXTURE_KINDS))),
            )
        )
    if not isinstance(document.get("expectedFact"), dict):
        findings.append(
            FixtureFinding(
                "fixture-expected-fact-missing",
                location,
                "fixture must declare an expectedFact object",
            )
        )
    return findings

def _validate_manifest_entry(
    entry: Any,
    index: int,
    fixtures_root: Path,
    declared_paths: set[str],
    declared_ids: set[str],
) -> tuple[Path | None, List[FixtureFinding]]:
    location = "{0}/fixtures/{1}".format(MANIFEST_NAME, index)
    findings: List[FixtureFinding] = []
    if not isinstance(entry, dict):
        return None, [
            FixtureFinding(
                "fixture-metadata-invalid",
                location,
                "fixture entry must be an object",
            )
        ]

    _validate_exact_keys(entry, ENTRY_KEYS, location, findings)
    fixture_id = entry.get("id")
    if not isinstance(fixture_id, str) or not IDENTIFIER.fullmatch(fixture_id):
        findings.append(
            FixtureFinding(
                "fixture-id-invalid",
                location,
                "id must be a stable lowercase kebab-case identifier",
            )
        )
    elif fixture_id in declared_ids:
        findings.append(
            FixtureFinding("fixture-id-duplicate", location, "fixture id is duplicated"))
    else:
        declared_ids.add(fixture_id)

    relative_path = entry.get("path")
    fixture_path: Path | None = None
    if not isinstance(relative_path, str) or not relative_path.endswith(".json"):
        findings.append(
            FixtureFinding(
                "fixture-path-invalid",
                location,
                "path must be a relative JSON fixture path",
            )
        )
    else:
        candidate = (fixtures_root / relative_path).resolve()
        if Path(relative_path).is_absolute() or not _path_is_within(candidate, fixtures_root):
            findings.append(
                FixtureFinding(
                    "fixture-path-escape",
                    location,
                    "path must remain inside acceptance/reference-fixtures",
                )
            )
        elif relative_path == MANIFEST_NAME:
            findings.append(
                FixtureFinding(
                    "fixture-path-invalid",
                    location,
                    "manifest cannot register itself as a fixture",
                )
            )
        elif relative_path in declared_paths:
            findings.append(
                FixtureFinding("fixture-path-duplicate", location, "fixture path is duplicated"))
            fixture_path = candidate
        else:
            declared_paths.add(relative_path)
            fixture_path = candidate

    digest = entry.get("sha256")
    if not isinstance(digest, str) or not SHA256.fullmatch(digest):
        findings.append(
            FixtureFinding(
                "fixture-digest-invalid",
                location,
                "sha256 must be a lowercase 64-character digest",
            )
        )

    captured_at = entry.get("capturedAt")
    if not isinstance(captured_at, str):
        findings.append(
            FixtureFinding(
                "fixture-captured-at-invalid",
                location,
                "capturedAt must be an ISO-8601 calendar date",
            )
        )
    else:
        try:
            date.fromisoformat(captured_at)
        except ValueError:
            findings.append(
                FixtureFinding(
                    "fixture-captured-at-invalid",
                    location,
                    "capturedAt must be an ISO-8601 calendar date",
                )
            )

    source = entry.get("source")
    if not isinstance(source, dict):
        findings.append(FixtureFinding("fixture-source-invalid", location, "source must be an object"))
    else:
        _validate_exact_keys(source, SOURCE_KEYS, "{0}/source".format(location), findings)
        if not isinstance(source.get("repository"), str) or not source["repository"]:
            findings.append(FixtureFinding("fixture-source-invalid", location, "source.repository is required"))
        revision = source.get("revision")
        if not isinstance(revision, str) or not GIT_REVISION.fullmatch(revision):
            findings.append(
                FixtureFinding(
                    "fixture-source-invalid",
                    location,
                    "source.revision must be a full lowercase Git revision",
                )
            )
        source_path = source.get("path")
        if (
            not isinstance(source_path, str)
            or not source_path
            or source_path.startswith("/")
            or ".." in Path(source_path).parts
        ):
            findings.append(
                FixtureFinding(
                    "fixture-source-invalid",
                    location,
                    "source.path must be a non-empty repository-relative path",
                )
            )
        if not isinstance(source.get("locator"), str) or not source["locator"]:
            findings.append(FixtureFinding("fixture-source-invalid", location, "source.locator is required"))

    sanitization = entry.get("sanitization")
    if not isinstance(sanitization, dict):
        findings.append(
            FixtureFinding("fixture-sanitization-invalid", location, "sanitization must be an object")
        )
    else:
        _validate_exact_keys(
            sanitization,
            SANITIZATION_KEYS,
            "{0}/sanitization".format(location),
            findings,
        )
        for field in SANITIZATION_KEYS:
            if sanitization.get(field) is not False:
                findings.append(
                    FixtureFinding(
                        "fixture-sanitization-invalid",
                        "{0}/sanitization/{1}".format(location, field),
                        "every prohibited data category must be explicitly false",
                    )
                )

    classification = entry.get("classification")
    if classification not in FIXTURE_CLASSIFICATIONS:
        findings.append(
            FixtureFinding(
                "fixture-classification-invalid",
                location,
                "classification must be one of: {0}".format(
                    ", ".join(sorted(FIXTURE_CLASSIFICATIONS))
                ),
            )
        )

    uses = entry.get("newPlatformUse")
    if not isinstance(uses, list) or not uses or any(
        not isinstance(use, str) or use not in NEW_PLATFORM_USES for use in uses
    ):
        findings.append(
            FixtureFinding(
                "fixture-use-invalid",
                location,
                "newPlatformUse must be a non-empty list of declared uses",
            )
        )
    elif len(uses) != len(set(uses)):
        findings.append(FixtureFinding("fixture-use-invalid", location, "newPlatformUse contains a duplicate"))

    mapping = entry.get("vnextMapping")
    if not isinstance(mapping, dict):
        findings.append(
            FixtureFinding("fixture-vnext-mapping-invalid", location, "vnextMapping must be an object")
        )
    else:
        _validate_exact_keys(mapping, VNEXT_MAPPING_KEYS, "{0}/vnextMapping".format(location), findings)
        if mapping.get("contract") not in CONTRACT_IDS:
            findings.append(
                FixtureFinding(
                    "fixture-vnext-mapping-invalid",
                    location,
                    "vnextMapping.contract must identify C1 through C6",
                )
            )
        if not isinstance(mapping.get("purpose"), str) or not mapping["purpose"]:
            findings.append(
                FixtureFinding(
                    "fixture-vnext-mapping-invalid",
                    location,
                    "vnextMapping.purpose is required",
                )
            )

    return fixture_path, findings


def validate(root: Path) -> List[FixtureFinding]:
    """Verify fixture provenance, integrity, and explicit sanitization assertions."""

    root = root.resolve()
    fixtures_root = (root / FIXTURE_ROOT).resolve()
    manifest_path = fixtures_root / MANIFEST_NAME
    if not fixtures_root.is_dir():
        return [
            FixtureFinding(
                "fixture-root-missing",
                str(FIXTURE_ROOT),
                "reference fixture directory does not exist",
            )
        ]
    manifest, findings = _read_json_object(manifest_path, fixtures_root)
    if manifest is None:
        return findings

    _validate_exact_keys(
        manifest,
        frozenset({"schemaVersion", "collection", "fixtures"}),
        MANIFEST_NAME,
        findings,
    )
    if manifest.get("schemaVersion") != SCHEMA_VERSION:
        findings.append(
            FixtureFinding(
                "fixture-manifest-version-invalid",
                MANIFEST_NAME,
                "schemaVersion must be {0}".format(SCHEMA_VERSION),
            )
        )
    if manifest.get("collection") != COLLECTION_NAME:
        findings.append(
            FixtureFinding(
                "fixture-manifest-collection-invalid",
                MANIFEST_NAME,
                "collection must be {0}".format(COLLECTION_NAME),
            )
        )
    entries = manifest.get("fixtures")
    if not isinstance(entries, list) or not entries:
        findings.append(
            FixtureFinding(
                "fixture-manifest-entries-invalid",
                MANIFEST_NAME,
                "fixtures must be a non-empty array",
            )
        )
        return findings

    declared_paths: set[str] = set()
    declared_ids: set[str] = set()
    for index, entry in enumerate(entries):
        fixture_path, entry_findings = _validate_manifest_entry(
            entry,
            index,
            fixtures_root,
            declared_paths,
            declared_ids,
        )
        findings.extend(entry_findings)
        if fixture_path is None:
            continue
        if not fixture_path.is_file():
            findings.append(
                FixtureFinding(
                    "fixture-file-missing",
                    _location(fixture_path, fixtures_root),
                    "manifest fixture file does not exist",
                )
            )
            continue

        expected_digest = entry.get("sha256") if isinstance(entry, dict) else None
        actual_digest = hashlib.sha256(fixture_path.read_bytes()).hexdigest()
        if expected_digest != actual_digest:
            findings.append(
                FixtureFinding(
                    "fixture-digest-mismatch",
                    _location(fixture_path, fixtures_root),
                    "manifest sha256 does not match the sanitized fixture bytes",
                )
            )

        fixture_document, document_findings = _read_json_object(fixture_path, fixtures_root)
        findings.extend(document_findings)
        if fixture_document is not None:
            findings.extend(_validate_fixture_document(fixture_document, fixture_path, fixtures_root))

    actual_paths = {
        path.relative_to(fixtures_root).as_posix()
        for path in fixtures_root.rglob("*.json")
        if path.name != MANIFEST_NAME
    }
    for unregistered_path in sorted(actual_paths - declared_paths):
        findings.append(
            FixtureFinding(
                "fixture-unregistered",
                unregistered_path,
                "JSON fixture is not registered in manifest.v1.json",
            )
        )
    return findings
