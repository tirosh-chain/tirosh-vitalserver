#!/usr/bin/env python3
"""Verify one explicit C79 real-file Vital replay corpus.

The verifier consumes a human-authored approval document and exact external
files. It verifies contract, registration, regular-file identity, byte size,
and SHA-256. It never decides that content is non-identifying or authorized
for redistribution.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import hashlib
import json
import os
from pathlib import Path
from typing import Any, Mapping, Sequence

from tooling.contracts import ContractRepository


class VitalReplayCorpusError(RuntimeError):
    """The C79 declaration or selected corpus bytes are invalid."""


@dataclass(frozen=True)
class VerifiedVitalReplayCorpusEntry:
    entry_id: str
    path: Path
    byte_size: int
    sha256: str
    format_version: int
    minimum_graph_compatible_signal_count: int


@dataclass(frozen=True)
class VerifiedVitalReplayCorpus:
    corpus_id: str
    manifest_path: Path
    entries: tuple[VerifiedVitalReplayCorpusEntry, ...]


def verify_vital_replay_corpus(
    contract_root: Path,
    manifest_path: Path,
    corpus_directory: Path,
) -> VerifiedVitalReplayCorpus:
    validate_contract_root(contract_root)
    validate_regular_file(manifest_path, "C79 manifest")
    if (
        not corpus_directory.is_absolute()
        or corpus_directory.is_symlink()
        or not corpus_directory.is_dir()
    ):
        raise VitalReplayCorpusError(
            "C79 corpus directory must be an absolute non-symlink directory"
        )
    try:
        document = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise VitalReplayCorpusError(
            "C79 manifest is not one readable JSON document"
        ) from error
    if not isinstance(document, dict):
        raise VitalReplayCorpusError("C79 manifest must be one JSON object")
    repository = ContractRepository(contract_root)
    repository.load()
    findings = repository.validate_instance(
        "vital-replay-corpus-manifest.schema.json",
        document,
    )
    if findings:
        raise VitalReplayCorpusError(
            "C79 manifest contract failed: "
            + "; ".join(finding.render() for finding in findings)
        )
    entries = document["entries"]
    entry_ids = [entry["id"] for entry in entries]
    file_names = [entry["fileName"] for entry in entries]
    if len(set(entry_ids)) != len(entry_ids):
        raise VitalReplayCorpusError("C79 entry IDs must be unique")
    if len(set(file_names)) != len(file_names):
        raise VitalReplayCorpusError("C79 file names must be unique")
    registered_names = set(file_names)
    actual_vital_names = {
        child.name
        for child in corpus_directory.iterdir()
        if child.name.endswith(".vital")
    }
    if actual_vital_names != registered_names:
        missing = sorted(registered_names - actual_vital_names)
        unregistered = sorted(actual_vital_names - registered_names)
        raise VitalReplayCorpusError(
            "C79 corpus registration mismatch"
            + ("; missing=" + ",".join(missing) if missing else "")
            + (
                "; unregistered=" + ",".join(unregistered)
                if unregistered
                else ""
            )
        )
    verified: list[VerifiedVitalReplayCorpusEntry] = []
    for entry in entries:
        path = corpus_directory / entry["fileName"]
        validate_regular_file(path, "C79 corpus entry " + entry["id"])
        observed_size = path.stat().st_size
        if observed_size != entry["byteSize"]:
            raise VitalReplayCorpusError(
                "C79 byte size mismatch for " + entry["id"]
            )
        observed_sha256 = sha256_file(path)
        if observed_sha256 != entry["sha256"]:
            raise VitalReplayCorpusError(
                "C79 SHA-256 mismatch for " + entry["id"]
            )
        verified.append(
            VerifiedVitalReplayCorpusEntry(
                entry_id=entry["id"],
                path=path,
                byte_size=observed_size,
                sha256=observed_sha256,
                format_version=entry["formatVersion"],
                minimum_graph_compatible_signal_count=entry[
                    "expectedReplay"
                ]["minimumGraphCompatibleSignalCount"],
            )
        )
    return VerifiedVitalReplayCorpus(
        corpus_id=document["corpusId"],
        manifest_path=manifest_path,
        entries=tuple(verified),
    )


def validate_contract_root(contract_root: Path) -> None:
    if (
        not contract_root.is_absolute()
        or contract_root.is_symlink()
        or not contract_root.is_dir()
        or not (
            contract_root / "contracts" / "catalog" / "v1.json"
        ).is_file()
    ):
        raise VitalReplayCorpusError(
            "C79 contract root must be the absolute canonical contract repository"
        )


def validate_regular_file(path: Path, label: str) -> None:
    if (
        not path.is_absolute()
        or path.is_symlink()
        or not path.is_file()
    ):
        raise VitalReplayCorpusError(
            label + " must be an absolute non-symlink regular file"
        )


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        while chunk := source.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def result_document(corpus: VerifiedVitalReplayCorpus) -> Mapping[str, Any]:
    return {
        "schemaVersion": "v1",
        "state": "verified",
        "corpusId": corpus.corpus_id,
        "manifestPath": str(corpus.manifest_path),
        "entries": [
            {
                "id": entry.entry_id,
                "path": str(entry.path),
                "byteSize": entry.byte_size,
                "sha256": entry.sha256,
                "formatVersion": entry.format_version,
                "minimumGraphCompatibleSignalCount": (
                    entry.minimum_graph_compatible_signal_count
                ),
            }
            for entry in corpus.entries
        ],
    }


def canonical_json(document: Mapping[str, Any]) -> str:
    return json.dumps(document, sort_keys=True, separators=(",", ":"))


def parse_arguments(arguments: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--contract-root", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--corpus-directory", type=Path, required=True)
    return parser.parse_args(arguments)


def main(arguments: Sequence[str] | None = None) -> int:
    options = parse_arguments(
        arguments if arguments is not None else os.sys.argv[1:]
    )
    corpus = verify_vital_replay_corpus(
        options.contract_root,
        options.manifest,
        options.corpus_directory,
    )
    print(canonical_json(result_document(corpus)))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except VitalReplayCorpusError as error:
        print("vital-replay-corpus:", error, file=os.sys.stderr)
        raise SystemExit(2)
