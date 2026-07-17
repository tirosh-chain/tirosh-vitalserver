#!/usr/bin/env python3
"""Generate or verify the deterministic pre-release SPDX source inventory."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any, Dict, Optional, Sequence


JSON_OBJECT = Dict[str, Any]


class SourceInventoryError(RuntimeError):
    """The declared source inventory cannot safely be generated."""


def load_json(path: Path) -> JSON_OBJECT:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise SourceInventoryError(f"could not read {path}: {error}") from error
    if not isinstance(value, dict):
        raise SourceInventoryError(f"{path} must contain one JSON object")
    return value


def build_document(root: Path) -> JSON_OBJECT:
    policy_path = root / "product" / "delivery" / "sbom-policy.v1.json"
    policy = load_json(policy_path)
    allowlist = policy.get("licenseAllowlist")
    components = policy.get("components")
    if policy.get("schemaVersion") != "v1" or not isinstance(allowlist, list) or not isinstance(components, list):
        raise SourceInventoryError("SBOM policy must declare schemaVersion v1, licenseAllowlist, and components")
    if not isinstance(policy.get("generatedAt"), str) or not isinstance(policy.get("documentName"), str) or not isinstance(policy.get("documentNamespace"), str):
        raise SourceInventoryError("SBOM policy document metadata is required")

    seen_ids: set[str] = set()
    packages: list[JSON_OBJECT] = []
    relationships: list[JSON_OBJECT] = []
    for component in components:
        if not isinstance(component, dict):
            raise SourceInventoryError("SBOM policy components must be objects")
        component_id = component.get("id")
        name = component.get("name")
        version = component.get("version")
        source = component.get("source")
        license_id = component.get("license")
        notice_status = component.get("noticeStatus")
        if not all(isinstance(value, str) and value for value in (component_id, name, version, source, license_id, notice_status)):
            raise SourceInventoryError("each SBOM component requires id, name, version, source, license, and noticeStatus")
        if component_id in seen_ids:
            raise SourceInventoryError(f"duplicate SBOM component id: {component_id}")
        if license_id not in allowlist:
            raise SourceInventoryError(f"SBOM component {component_id} uses unapproved license {license_id}")
        source_path = root / source
        if not source_path.is_file():
            raise SourceInventoryError(f"SBOM component {component_id} source does not exist: {source}")
        seen_ids.add(component_id)
        spdx_id = "SPDXRef-" + component_id
        packages.append(
            {
                "SPDXID": spdx_id,
                "name": name,
                "versionInfo": version,
                "downloadLocation": "NOASSERTION",
                "filesAnalyzed": False,
                "licenseConcluded": license_id,
                "licenseDeclared": license_id,
                "copyrightText": "NOASSERTION",
                "supplier": "NOASSERTION",
                "sourceInfo": f"source={source}; noticeStatus={notice_status}",
            }
        )
        relationships.append(
            {
                "spdxElementId": "SPDXRef-DOCUMENT",
                "relationshipType": "DESCRIBES",
                "relatedSpdxElement": spdx_id,
            }
        )

    return {
        "spdxVersion": "SPDX-2.3",
        "dataLicense": "CC0-1.0",
        "SPDXID": "SPDXRef-DOCUMENT",
        "name": policy["documentName"],
        "documentNamespace": policy["documentNamespace"],
        "creationInfo": {
            "creators": ["Tool: runtime-platform/source-inventory"],
            "created": policy["generatedAt"],
        },
        "documentComment": "This is a source-input inventory only. It is not release-artifact SBOM or delivery proof.",
        "packages": packages,
        "relationships": relationships,
    }


def canonical(document: JSON_OBJECT) -> str:
    return json.dumps(document, indent=2, sort_keys=True) + "\n"


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("product/delivery/sbom/runtime-platform-source-inventory.spdx.json"),
        help="output path relative to --root unless absolute",
    )
    parser.add_argument("--check", action="store_true", help="require the checked-in output to match generated content")
    arguments = parser.parse_args(argv)
    root = arguments.root.resolve()
    output = arguments.output if arguments.output.is_absolute() else root / arguments.output
    try:
        expected = canonical(build_document(root))
    except SourceInventoryError as error:
        parser.exit(2, f"source inventory generation failed: {error}\n")

    if arguments.check:
        try:
            actual = output.read_text(encoding="utf-8")
        except OSError as error:
            parser.exit(1, f"source inventory check failed: could not read {output}: {error}\n")
        if actual != expected:
            parser.exit(1, "source inventory check failed: generated SPDX source inventory is stale\n")
        print("runtime-platform source inventory SBOM is current")
        return 0

    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(expected, encoding="utf-8")
    print(f"runtime-platform source inventory SBOM written: {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
