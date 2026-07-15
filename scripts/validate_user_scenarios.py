#!/usr/bin/env python3
"""Validate product scenario catalog and Gherkin traceability."""

from __future__ import annotations

import re
import sys
from collections import Counter
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CATALOG_PATH = ROOT / "docs/product/user-scenarios.md"
FEATURES_DIR = ROOT / "features"

CATALOG_ID_PATTERN = re.compile(r"^\| `(?P<id>US-[A-Z]+-\d{3})` \|")
SCENARIO_PATTERN = re.compile(r"^\s*Scenario(?: Outline)?:\s+\S")
STEP_PATTERNS = {
    "Given": re.compile(r"^\s*Given\s+\S"),
    "When": re.compile(r"^\s*When\s+\S"),
    "Then": re.compile(r"^\s*Then\s+\S"),
}
ID_TAG_PATTERN = re.compile(r"^@US-[A-Z]+-\d{3}$")
BDD_STATE_TAGS = {"@bdd-pending", "@bdd-automated"}


@dataclass(frozen=True)
class FeatureScenario:
    """One scenario and the tags and steps declared for it."""

    path: Path
    line_number: int
    title: str
    tags: tuple[str, ...]
    steps: frozenset[str]


def read_catalog_ids(path: Path) -> list[str]:
    """Read stable scenario IDs from the catalog table."""

    ids: list[str] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        match = CATALOG_ID_PATTERN.match(line)
        if match is not None:
            ids.append(match.group("id"))
    return ids


def read_feature_scenarios(path: Path) -> list[FeatureScenario]:
    """Read scenario boundaries needed by the repository traceability check."""

    scenarios: list[FeatureScenario] = []
    pending_tags: list[str] = []
    current_title: str | None = None
    current_line = 0
    current_tags: tuple[str, ...] = ()
    current_steps: set[str] = set()

    def finish_current() -> None:
        if current_title is None:
            return
        scenarios.append(
            FeatureScenario(
                path=path,
                line_number=current_line,
                title=current_title,
                tags=current_tags,
                steps=frozenset(current_steps),
            )
        )

    for line_number, line in enumerate(
        path.read_text(encoding="utf-8").splitlines(), start=1
    ):
        stripped = line.strip()
        if stripped.startswith("@"):
            pending_tags.extend(stripped.split())
            continue
        if SCENARIO_PATTERN.match(line):
            finish_current()
            current_title = stripped.split(":", maxsplit=1)[1].strip()
            current_line = line_number
            current_tags = tuple(pending_tags)
            current_steps = set()
            pending_tags = []
            continue
        if current_title is not None:
            for keyword, pattern in STEP_PATTERNS.items():
                if pattern.match(line):
                    current_steps.add(keyword)

    finish_current()
    return scenarios


def duplicate_values(values: list[str]) -> list[str]:
    """Return sorted duplicate values."""

    return sorted(value for value, count in Counter(values).items() if count > 1)


def validate() -> list[str]:
    """Return explicit validation failures without converting them to success."""

    failures: list[str] = []
    if not CATALOG_PATH.is_file():
        return [f"scenario catalog is missing: {CATALOG_PATH}"]
    if not FEATURES_DIR.is_dir():
        return [f"features directory is missing: {FEATURES_DIR}"]

    catalog_ids = read_catalog_ids(CATALOG_PATH)
    if not catalog_ids:
        failures.append(f"scenario catalog contains no IDs: {CATALOG_PATH}")
    for duplicate in duplicate_values(catalog_ids):
        failures.append(f"duplicate catalog scenario ID: {duplicate}")

    feature_paths = sorted(FEATURES_DIR.glob("*.feature"))
    if not feature_paths:
        failures.append(f"no .feature files found: {FEATURES_DIR}")

    scenarios = [
        scenario
        for feature_path in feature_paths
        for scenario in read_feature_scenarios(feature_path)
    ]
    feature_ids: list[str] = []
    required_steps = set(STEP_PATTERNS)

    for scenario in scenarios:
        location = f"{scenario.path.relative_to(ROOT)}:{scenario.line_number}"
        id_tags = [tag for tag in scenario.tags if ID_TAG_PATTERN.match(tag)]
        if len(id_tags) != 1:
            failures.append(
                f"{location}: scenario must have exactly one @US-* tag; found={id_tags}"
            )
        else:
            feature_ids.append(id_tags[0][1:])

        state_tags = [tag for tag in scenario.tags if tag in BDD_STATE_TAGS]
        if len(state_tags) != 1:
            failures.append(
                f"{location}: scenario must have exactly one BDD state tag; "
                f"found={state_tags}"
            )

        missing_steps = sorted(required_steps - scenario.steps)
        if missing_steps:
            failures.append(
                f"{location}: scenario is missing required steps: "
                f"{', '.join(missing_steps)}"
            )

    for duplicate in duplicate_values(feature_ids):
        failures.append(f"duplicate feature scenario ID: {duplicate}")

    catalog_only = sorted(set(catalog_ids) - set(feature_ids))
    feature_only = sorted(set(feature_ids) - set(catalog_ids))
    if catalog_only:
        failures.append(
            f"catalog IDs without feature scenarios: {', '.join(catalog_only)}"
        )
    if feature_only:
        failures.append(f"feature IDs missing from catalog: {', '.join(feature_only)}")

    return failures


def main() -> int:
    """Run validation and print a concise proof summary."""

    failures = validate()
    if failures:
        print("Product scenario validation failed:", file=sys.stderr)
        for failure in failures:
            print(f"  - {failure}", file=sys.stderr)
        return 1

    scenario_count = len(read_catalog_ids(CATALOG_PATH))
    feature_count = len(list(FEATURES_DIR.glob("*.feature")))
    print(
        "Product scenario validation passed: "
        f"scenarios={scenario_count} featureFiles={feature_count}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
