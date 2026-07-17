"""Executable verification helpers for the runtime-platform contract source."""

from __future__ import annotations

import copy
import json
import warnings
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, Iterable, List, Mapping, Optional, Sequence, Tuple
from urllib.parse import unquote, urlparse

from jsonschema import FormatChecker
from jsonschema.validators import validator_for
with warnings.catch_warnings():
    # macOS system Python may use LibreSSL. The validator imports urllib3 for URL
    # tooling, while this verifier validates an already local, in-memory bundle.
    warnings.filterwarnings(
        "ignore",
        message=r"urllib3 v2 only supports OpenSSL 1\.1\.1\+",
    )
    from openapi_spec_validator import validate
from referencing import Registry, Resource


JSON_OBJECT = Dict[str, Any]
HTTP_METHODS = ("get", "put", "post", "delete", "options", "head", "patch", "trace")
STABLE_SCHEMA_KEYS = (
    "$schema",
    "$id",
    "type",
    "format",
    "pattern",
    "const",
    "minimum",
    "maximum",
    "exclusiveMinimum",
    "exclusiveMaximum",
    "multipleOf",
    "minLength",
    "maxLength",
    "minItems",
    "maxItems",
    "uniqueItems",
    "additionalProperties",
    "allOf",
    "anyOf",
    "oneOf",
    "if",
    "then",
    "else",
    "not",
    "dependentRequired",
)


@dataclass(frozen=True)
class Finding:
    """A deterministic contract verification failure."""

    code: str
    location: str
    message: str

    def render(self) -> str:
        return "[{0}] {1}: {2}".format(self.code, self.location, self.message)


class ContractToolError(RuntimeError):
    """Raised when the contract source itself cannot be read or resolved."""


def load_json(path: Path) -> JSON_OBJECT:
    """Read a JSON object without converting decode failures into empty data."""

    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ContractToolError("could not read JSON at {0}: {1}".format(path, error))
    if not isinstance(data, dict):
        raise ContractToolError("JSON document at {0} must be an object".format(path))
    return data


def write_json(path: Path, document: JSON_OBJECT) -> None:
    """Write a deterministic generated JSON artifact."""

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(document, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def pointer_lookup(document: Any, fragment: str) -> Any:
    """Resolve an RFC 6901 fragment within a JSON document."""

    if fragment in ("", "#"):
        return document
    pointer = unquote(fragment)
    if pointer.startswith("#"):
        pointer = pointer[1:]
    if not pointer.startswith("/"):
        raise ContractToolError("unsupported JSON pointer fragment: {0}".format(fragment))

    current = document
    for raw_token in pointer[1:].split("/"):
        token = raw_token.replace("~1", "/").replace("~0", "~")
        if isinstance(current, list):
            try:
                current = current[int(token)]
            except (ValueError, IndexError) as error:
                raise ContractToolError(
                    "could not resolve JSON pointer {0}: {1}".format(fragment, error)
                )
        elif isinstance(current, dict) and token in current:
            current = current[token]
        else:
            raise ContractToolError(
                "could not resolve JSON pointer {0}".format(fragment)
            )
    return current


class ContractRepository:
    """Loads canonical schemas and resolves only declared contract references."""

    def __init__(self, root: Path) -> None:
        self.root = root.resolve()
        self.contracts_root = self.root / "contracts"
        self.schema_root = self.contracts_root / "json-schema" / "v1"
        self.openapi_path = self.contracts_root / "openapi" / "control.v1.json"
        self.catalog_path = self.contracts_root / "catalog" / "v1.json"
        self.examples_manifest_path = self.contracts_root / "examples" / "v1" / "manifest.json"
        self.operation_policy_path = (
            self.contracts_root / "policies" / "v1" / "operation-transitions.json"
        )
        self.baseline_path = self.contracts_root / "compatibility" / "v1" / "baseline.json"
        self.bundle_path = self.contracts_root / "generated" / "control.v1.bundle.json"
        self.schemas_by_path: Dict[Path, JSON_OBJECT] = {}
        self.schemas_by_id: Dict[str, Tuple[Path, JSON_OBJECT]] = {}
        self.schemas_by_name: Dict[str, Tuple[Path, JSON_OBJECT]] = {}
        self.registry: Optional[Registry] = None

    def load(self) -> None:
        if not self.schema_root.is_dir():
            raise ContractToolError("schema directory is missing: {0}".format(self.schema_root))

        self.schemas_by_path.clear()
        self.schemas_by_id.clear()
        self.schemas_by_name.clear()
        self.registry = None

        for path in sorted(self.schema_root.glob("*.schema.json")):
            document = load_json(path)
            schema_id = document.get("$id")
            if not isinstance(schema_id, str) or not schema_id:
                raise ContractToolError("schema has no stable $id: {0}".format(path))
            if schema_id in self.schemas_by_id:
                raise ContractToolError("duplicate schema $id: {0}".format(schema_id))
            if path.name in self.schemas_by_name:
                raise ContractToolError("duplicate schema file name: {0}".format(path.name))
            self.schemas_by_path[path.resolve()] = document
            self.schemas_by_id[schema_id] = (path.resolve(), document)
            self.schemas_by_name[path.name] = (path.resolve(), document)

        if not self.schemas_by_path:
            raise ContractToolError("no schema documents found in {0}".format(self.schema_root))

        resources = [
            (schema_id, Resource.from_contents(document))
            for schema_id, (_, document) in self.schemas_by_id.items()
        ]
        self.registry = Registry().with_resources(resources)

    def require_loaded(self) -> None:
        if self.registry is None:
            raise ContractToolError("contract repository has not been loaded")

    def schema(self, name: str) -> Tuple[Path, JSON_OBJECT]:
        self.require_loaded()
        try:
            return self.schemas_by_name[name]
        except KeyError:
            raise ContractToolError("schema is not declared: {0}".format(name))

    def resolve_schema_reference(
        self, reference: str, base_path: Path
    ) -> Tuple[Path, JSON_OBJECT, Any, str]:
        """Resolve a local file or stable-URN reference to a schema fragment."""

        self.require_loaded()
        document_path = base_path.resolve()
        parsed = urlparse(reference)
        fragment = parsed.fragment
        reference_without_fragment = reference.split("#", 1)[0]

        if reference.startswith("#"):
            try:
                document = self.schemas_by_path[document_path]
            except KeyError:
                raise ContractToolError(
                    "local schema reference has unknown source document: {0}".format(
                        document_path
                    )
                )
            return document_path, document, pointer_lookup(document, "#{0}".format(fragment)), fragment

        if parsed.scheme:
            try:
                target_path, document = self.schemas_by_id[reference_without_fragment]
            except KeyError:
                raise ContractToolError(
                    "schema reference is not declared by this contract root: {0}".format(
                        reference_without_fragment
                    )
                )
            return target_path, document, pointer_lookup(document, "#{0}".format(fragment)), fragment

        target_path = (document_path.parent / reference_without_fragment).resolve()
        try:
            document = self.schemas_by_path[target_path]
        except KeyError:
            raise ContractToolError(
                "schema file reference is not declared by this contract root: {0}".format(
                    reference
                )
            )
        return target_path, document, pointer_lookup(document, "#{0}".format(fragment)), fragment

    def validate_schema_documents(self) -> List[Finding]:
        findings = []
        for path, schema in sorted(self.schemas_by_path.items()):
            try:
                validator_for(schema).check_schema(schema)
            except Exception as error:  # jsonschema provides several schema exception types.
                findings.append(
                    Finding(
                        "schema-invalid",
                        self.relative(path),
                        str(error),
                    )
                )
        return findings

    def validate_instance(self, schema_name: str, instance: Any) -> List[str]:
        self.require_loaded()
        _, schema = self.schema(schema_name)
        validator_class = validator_for(schema)
        validator = validator_class(
            schema,
            registry=self.registry,
            format_checker=FormatChecker(),
        )
        errors = sorted(validator.iter_errors(instance), key=lambda error: str(error.path))
        return [
            "{0}: {1}".format(error.json_path or "$", error.message)
            for error in errors
        ]

    def relative(self, path: Path) -> str:
        try:
            return path.resolve().relative_to(self.root).as_posix()
        except ValueError:
            return str(path)


def validate_catalog(repository: ContractRepository) -> List[Finding]:
    """Check that C1–C47 have one owner and explicit canonical schema sources."""

    findings = []
    try:
        catalog = load_json(repository.catalog_path)
    except ContractToolError as error:
        return [Finding("catalog-unreadable", repository.relative(repository.catalog_path), str(error))]

    contracts = catalog.get("contracts")
    if catalog.get("schemaVersion") != "v1" or not isinstance(contracts, list):
        return [
            Finding(
                "catalog-invalid",
                repository.relative(repository.catalog_path),
                "catalog must have schemaVersion v1 and a contracts array",
            )
        ]

    expected_ids = {"C1", "C2", "C3", "C4", "C5", "C6", "C7", "C8", "C9", "C10", "C11", "C12", "C13", "C14", "C15", "C16", "C17", "C18", "C19", "C20", "C21", "C22", "C23", "C24", "C25", "C26", "C27", "C28", "C29", "C30", "C31", "C32", "C33", "C34", "C35", "C36", "C37", "C38", "C39", "C40", "C41", "C42", "C43", "C44", "C45", "C46", "C47"}
    actual_ids = set()
    for entry in contracts:
        if not isinstance(entry, dict):
            findings.append(
                Finding(
                    "catalog-invalid",
                    repository.relative(repository.catalog_path),
                    "every contract entry must be an object",
                )
            )
            continue
        contract_id = entry.get("id")
        owner = entry.get("owner")
        schema_relative_paths = entry.get("schemas")
        if not isinstance(contract_id, str):
            findings.append(
                Finding("catalog-invalid", "catalog", "contract entry has no string id"))
            continue
        if contract_id in actual_ids:
            findings.append(
                Finding("catalog-duplicate-id", "catalog", "duplicate contract id {0}".format(contract_id))
            )
        actual_ids.add(contract_id)
        if not isinstance(owner, str) or not owner:
            findings.append(
                Finding("catalog-owner-missing", "catalog/{0}".format(contract_id), "owner is required")
            )
        if not isinstance(schema_relative_paths, list) or not schema_relative_paths:
            findings.append(
                Finding(
                    "catalog-schema-missing",
                    "catalog/{0}".format(contract_id),
                    "non-empty schemas array is required",
                )
            )
            continue
        seen_schema_paths = set()
        for schema_relative_path in schema_relative_paths:
            if not isinstance(schema_relative_path, str):
                findings.append(
                    Finding(
                        "catalog-schema-missing",
                        "catalog/{0}".format(contract_id),
                        "each schema path must be a string",
                    )
                )
                continue
            if schema_relative_path in seen_schema_paths:
                findings.append(
                    Finding(
                        "catalog-schema-duplicate",
                        "catalog/{0}".format(contract_id),
                        "schema path is duplicated: {0}".format(schema_relative_path),
                    )
                )
                continue
            seen_schema_paths.add(schema_relative_path)
            if not (repository.contracts_root / schema_relative_path).is_file():
                findings.append(
                    Finding(
                        "catalog-schema-missing",
                        "catalog/{0}".format(contract_id),
                        "declared schema does not exist: {0}".format(schema_relative_path),
                    )
                )

    missing_ids = expected_ids - actual_ids
    extra_ids = actual_ids - expected_ids
    for contract_id in sorted(missing_ids):
        findings.append(Finding("catalog-contract-missing", "catalog", "missing {0}".format(contract_id)))
    for contract_id in sorted(extra_ids):
        findings.append(Finding("catalog-contract-unknown", "catalog", "unknown {0}".format(contract_id)))
    return findings


def validate_examples(repository: ContractRepository) -> List[Finding]:
    """Verify positive and negative fixture decode outcomes without fallback."""

    findings = []
    try:
        manifest = load_json(repository.examples_manifest_path)
    except ContractToolError as error:
        return [
            Finding(
                "examples-manifest-unreadable",
                repository.relative(repository.examples_manifest_path),
                str(error),
            )
        ]

    fixtures = manifest.get("fixtures")
    if manifest.get("schemaVersion") != "v1" or not isinstance(fixtures, list):
        return [
            Finding(
                "examples-manifest-invalid",
                repository.relative(repository.examples_manifest_path),
                "manifest must have schemaVersion v1 and a fixtures array",
            )
        ]

    examples_root = repository.examples_manifest_path.parent
    for entry in fixtures:
        if not isinstance(entry, dict):
            findings.append(Finding("example-entry-invalid", "examples", "fixture entry must be an object"))
            continue
        fixture_relative_path = entry.get("path")
        schema_name = entry.get("schema")
        expected_valid = entry.get("valid")
        if not isinstance(fixture_relative_path, str) or not isinstance(schema_name, str):
            findings.append(
                Finding("example-entry-invalid", "examples", "fixture needs path and schema"))
            continue
        if not isinstance(expected_valid, bool):
            findings.append(
                Finding("example-entry-invalid", fixture_relative_path, "fixture valid must be boolean"))
            continue
        fixture_path = (examples_root / fixture_relative_path).resolve()
        try:
            fixture_path.relative_to(examples_root.resolve())
        except ValueError:
            findings.append(
                Finding("example-path-escape", fixture_relative_path, "fixture path escapes examples root")
            )
            continue
        try:
            instance = load_json(fixture_path)
            validation_errors = repository.validate_instance(schema_name, instance)
        except ContractToolError as error:
            findings.append(Finding("example-unreadable", fixture_relative_path, str(error)))
            continue

        actual_valid = not validation_errors
        if actual_valid != expected_valid:
            expectation = "valid" if expected_valid else "invalid"
            observed = "valid" if actual_valid else "invalid"
            detail = "; ".join(validation_errors[:3])
            findings.append(
                Finding(
                    "example-outcome-mismatch",
                    fixture_relative_path,
                    "expected {0}, observed {1}: {2}".format(expectation, observed, detail),
                )
            )
    return findings


def operation_states(repository: ContractRepository) -> List[str]:
    """Read the canonical Operation state enumeration from C2."""

    _, operation_schema = repository.schema("operation.schema.json")
    states = operation_schema.get("properties", {}).get("state", {}).get("enum")
    if not isinstance(states, list) or not all(isinstance(state, str) for state in states):
        raise ContractToolError("Operation schema has no state enum")
    return list(states)


def load_operation_policy(repository: ContractRepository) -> JSON_OBJECT:
    return load_json(repository.operation_policy_path)


def transition_allowed(policy: Mapping[str, Any], source: str, target: str) -> bool:
    """Return the contract decision for one proposed Operation state transition."""

    states = policy.get("states")
    if not isinstance(states, dict):
        return False
    source_definition = states.get(source)
    if not isinstance(source_definition, dict):
        return False
    allowed_targets = source_definition.get("allowedTargets")
    return isinstance(allowed_targets, list) and target in allowed_targets


def validate_operation_policy(repository: ContractRepository) -> List[Finding]:
    """Ensure every declared Operation state has explicit terminal behavior."""

    findings = []
    try:
        policy = load_operation_policy(repository)
        states = operation_states(repository)
    except ContractToolError as error:
        return [
            Finding(
                "operation-policy-unreadable",
                repository.relative(repository.operation_policy_path),
                str(error),
            )
        ]

    policy_states = policy.get("states")
    if policy.get("schemaVersion") != "v1" or not isinstance(policy_states, dict):
        return [
            Finding(
                "operation-policy-invalid",
                repository.relative(repository.operation_policy_path),
                "policy must have schemaVersion v1 and a states object",
            )
        ]
    if policy.get("initialState") != "requested":
        findings.append(
            Finding("operation-policy-invalid", "operation policy", "initialState must be requested")
        )

    if set(policy_states) != set(states):
        findings.append(
            Finding(
                "operation-policy-state-mismatch",
                "operation policy",
                "policy states must exactly match the Operation state enum",
            )
        )
    for state in states:
        definition = policy_states.get(state)
        if not isinstance(definition, dict):
            continue
        terminal = definition.get("terminal")
        targets = definition.get("allowedTargets")
        if not isinstance(terminal, bool) or not isinstance(targets, list):
            findings.append(
                Finding("operation-policy-invalid", state, "terminal and allowedTargets are required")
            )
            continue
        unknown_targets = set(targets) - set(states)
        if unknown_targets:
            findings.append(
                Finding(
                    "operation-policy-invalid",
                    state,
                    "unknown target states: {0}".format(", ".join(sorted(unknown_targets))),
                )
            )
        if terminal and targets:
            findings.append(
                Finding("operation-terminal-transition", state, "terminal state has outgoing transitions")
            )
        if not terminal and not targets:
            findings.append(
                Finding("operation-dead-end", state, "non-terminal state has no outgoing transition")
            )
    return findings


def bundle_openapi(repository: ContractRepository) -> JSON_OBJECT:
    """Inline schema references so a formal OpenAPI validator sees one document."""

    source = load_json(repository.openapi_path)
    source_path = repository.openapi_path.resolve()
    resolving: List[Tuple[Path, str]] = []

    def bundle_node(node: Any, base_path: Path) -> Any:
        if isinstance(node, list):
            return [bundle_node(item, base_path) for item in node]
        if not isinstance(node, dict):
            return copy.deepcopy(node)

        reference = node.get("$ref")
        source_is_schema = base_path.resolve() in repository.schemas_by_path
        if isinstance(reference, str) and (not reference.startswith("#") or source_is_schema):
            target_path, _, target, fragment = repository.resolve_schema_reference(reference, base_path)
            key = (target_path, fragment)
            if key in resolving:
                raise ContractToolError("cyclic schema reference: {0}".format(reference))
            resolving.append(key)
            resolved_target = bundle_node(target, target_path)
            resolving.pop()
            sibling_nodes = {key: value for key, value in node.items() if key != "$ref"}
            if not sibling_nodes:
                return resolved_target
            return {
                "allOf": [
                    resolved_target,
                    bundle_node(sibling_nodes, base_path),
                ]
            }
        return {key: bundle_node(value, base_path) for key, value in node.items()}

    bundle = bundle_node(source, source_path)
    if not isinstance(bundle, dict):
        raise ContractToolError("OpenAPI bundle must be an object")
    return bundle


def iter_references(node: Any) -> Iterable[str]:
    if isinstance(node, dict):
        reference = node.get("$ref")
        if isinstance(reference, str):
            yield reference
        for value in node.values():
            yield from iter_references(value)
    elif isinstance(node, list):
        for value in node:
            yield from iter_references(value)


def validate_openapi(repository: ContractRepository) -> List[Finding]:
    """Check the source ref graph and the resulting OpenAPI 3.1 document."""

    try:
        bundle = bundle_openapi(repository)
    except ContractToolError as error:
        return [
            Finding(
                "openapi-reference-invalid",
                repository.relative(repository.openapi_path),
                str(error),
            )
        ]

    findings = []
    for reference in iter_references(bundle):
        if not reference.startswith("#"):
            findings.append(
                Finding(
                    "openapi-external-reference-left",
                    repository.relative(repository.openapi_path),
                    "bundle still contains external reference {0}".format(reference),
                )
            )
    if findings:
        return findings

    try:
        validate(bundle)
    except Exception as error:  # Package-specific exceptions differ by OpenAPI version.
        findings.append(
            Finding(
                "openapi-invalid",
                repository.relative(repository.openapi_path),
                str(error),
            )
        )
    return findings


def generate_openapi_bundle(repository: ContractRepository) -> JSON_OBJECT:
    """Generate and persist the checked-in OpenAPI bundle from canonical sources."""

    bundle = bundle_openapi(repository)
    write_json(repository.bundle_path, bundle)
    return bundle


def validate_generated_openapi_bundle(repository: ContractRepository) -> List[Finding]:
    """Require the checked-in bundle to match the canonical external-reference source."""

    try:
        expected = bundle_openapi(repository)
        actual = load_json(repository.bundle_path)
    except ContractToolError as error:
        return [
            Finding("openapi-bundle-unreadable", repository.relative(repository.bundle_path), str(error))
        ]
    if actual != expected:
        return [
            Finding(
                "openapi-bundle-stale",
                repository.relative(repository.bundle_path),
                "generated bundle differs; run make -C runtime-platform contract-generate",
            )
        ]
    return []


def build_baseline(repository: ContractRepository) -> JSON_OBJECT:
    """Create the immutable v1 compatibility baseline from canonical sources."""

    relative_schemas = {
        path.relative_to(repository.contracts_root).as_posix(): copy.deepcopy(schema)
        for path, schema in sorted(repository.schemas_by_path.items())
    }
    return {
        "schemaVersion": "v1",
        "baselineKind": "runtime-platform-contract-v1",
        "schemas": relative_schemas,
        "openapi": load_json(repository.openapi_path),
    }


def generate_baseline(repository: ContractRepository) -> JSON_OBJECT:
    """Persist an initial compatibility baseline only when no baseline exists."""

    if repository.baseline_path.exists():
        raise ContractToolError(
            "compatibility baseline already exists: {0}; use an explicit compatible extension instead".format(
                repository.baseline_path
            )
        )

    baseline = build_baseline(repository)
    write_json(repository.baseline_path, baseline)
    return baseline


def extend_baseline(repository: ContractRepository) -> JSON_OBJECT:
    """Record additive v1 contracts only after existing v1 compatibility passes."""

    if not repository.baseline_path.is_file():
        raise ContractToolError(
            "compatibility baseline is missing: {0}; initialize the major baseline first".format(
                repository.baseline_path
            )
        )
    findings = validate_compatibility(repository)
    if findings:
        raise ContractToolError(
            "cannot extend compatibility baseline because existing v1 contracts changed:\n{0}".format(
                "\n".join(finding.render() for finding in findings)
            )
        )
    baseline = build_baseline(repository)
    write_json(repository.baseline_path, baseline)
    return baseline


def replace_baseline_for_unreleased_contracts(repository: ContractRepository) -> JSON_OBJECT:
    """Replace v1 compatibility history only for an explicitly unreleased platform.

    This is deliberately not part of :func:`extend_baseline`: an extension
    promises that existing external consumers remain compatible, while a
    replacement records a consciously redesigned contract vocabulary before
    any release artifact is distributed. The caller must opt in by invoking
    the command whose name states that limited authority.
    """

    if not repository.baseline_path.is_file():
        raise ContractToolError(
            "compatibility baseline is missing: {0}; initialize the major baseline first".format(
                repository.baseline_path
            )
        )
    baseline = build_baseline(repository)
    write_json(repository.baseline_path, baseline)
    return baseline


def compare_schema(
    baseline: Any, candidate: Any, location: str = "$"
) -> List[str]:
    """Reject v1 removals, type/enum changes, and newly required fields."""

    findings: List[str] = []
    if not isinstance(baseline, dict):
        if baseline != candidate:
            findings.append("{0}: baseline value changed".format(location))
        return findings
    if not isinstance(candidate, dict):
        return ["{0}: schema object was replaced with a non-object".format(location)]

    for key in STABLE_SCHEMA_KEYS:
        if key in baseline and candidate.get(key) != baseline[key]:
            findings.append("{0}: stable keyword {1} changed".format(location, key))

    if "enum" in baseline and candidate.get("enum") != baseline["enum"]:
        findings.append("{0}: enum changed".format(location))

    baseline_required = set(baseline.get("required", []))
    candidate_required = set(candidate.get("required", []))
    missing_required = baseline_required - candidate_required
    new_required = candidate_required - baseline_required
    if missing_required:
        findings.append(
            "{0}: required fields removed: {1}".format(
                location, ", ".join(sorted(missing_required))
            )
        )
    if new_required:
        findings.append(
            "{0}: fields became required: {1}".format(
                location, ", ".join(sorted(new_required))
            )
        )

    for container_key in ("properties", "$defs"):
        baseline_children = baseline.get(container_key, {})
        candidate_children = candidate.get(container_key, {})
        if not isinstance(baseline_children, dict):
            continue
        if not isinstance(candidate_children, dict):
            findings.append("{0}: {1} is no longer an object".format(location, container_key))
            continue
        for name, baseline_child in baseline_children.items():
            child_location = "{0}/{1}/{2}".format(location, container_key, name)
            if name not in candidate_children:
                findings.append("{0}: field or definition was removed or renamed".format(child_location))
                continue
            findings.extend(compare_schema(baseline_child, candidate_children[name], child_location))

    if "items" in baseline:
        if "items" not in candidate:
            findings.append("{0}/items: items schema was removed".format(location))
        else:
            findings.extend(compare_schema(baseline["items"], candidate["items"], "{0}/items".format(location)))
    return findings


def compare_openapi(baseline: JSON_OBJECT, candidate: JSON_OBJECT) -> List[str]:
    """Reject removal or mutation of an existing public v1 operation."""

    findings = []
    baseline_paths = baseline.get("paths", {})
    candidate_paths = candidate.get("paths", {})
    if not isinstance(baseline_paths, dict) or not isinstance(candidate_paths, dict):
        return ["OpenAPI paths must remain objects"]

    for path, baseline_path_item in baseline_paths.items():
        candidate_path_item = candidate_paths.get(path)
        if not isinstance(candidate_path_item, dict):
            findings.append("paths/{0}: path was removed".format(path))
            continue
        if not isinstance(baseline_path_item, dict):
            continue
        for method in HTTP_METHODS:
            baseline_operation = baseline_path_item.get(method)
            if not isinstance(baseline_operation, dict):
                continue
            candidate_operation = candidate_path_item.get(method)
            location = "paths/{0}/{1}".format(path, method)
            if not isinstance(candidate_operation, dict):
                findings.append("{0}: operation was removed".format(location))
                continue
            if candidate_operation.get("operationId") != baseline_operation.get("operationId"):
                findings.append("{0}: operationId changed".format(location))
            if candidate_operation.get("parameters", []) != baseline_operation.get("parameters", []):
                findings.append("{0}: parameters changed".format(location))
            baseline_responses = baseline_operation.get("responses", {})
            candidate_responses = candidate_operation.get("responses", {})
            if not isinstance(baseline_responses, dict) or not isinstance(candidate_responses, dict):
                findings.append("{0}: responses are invalid".format(location))
                continue
            for status, baseline_response in baseline_responses.items():
                candidate_response = candidate_responses.get(status)
                if not isinstance(candidate_response, dict):
                    findings.append("{0}/responses/{1}: response was removed".format(location, status))
                    continue
                baseline_content = baseline_response.get("content", {}) if isinstance(baseline_response, dict) else {}
                candidate_content = candidate_response.get("content", {})
                if baseline_content != candidate_content:
                    findings.append("{0}/responses/{1}: response content changed".format(location, status))
    return findings


def validate_compatibility(repository: ContractRepository) -> List[Finding]:
    """Compare current sources against the frozen v1 compatibility baseline."""

    try:
        baseline = load_json(repository.baseline_path)
    except ContractToolError as error:
        return [
            Finding(
                "compatibility-baseline-unreadable",
                repository.relative(repository.baseline_path),
                str(error),
            )
        ]

    findings = []
    if baseline.get("schemaVersion") != "v1" or baseline.get("baselineKind") != "runtime-platform-contract-v1":
        return [
            Finding(
                "compatibility-baseline-invalid",
                repository.relative(repository.baseline_path),
                "baseline identity is invalid",
            )
        ]
    baseline_schemas = baseline.get("schemas")
    if not isinstance(baseline_schemas, dict):
        return [
            Finding(
                "compatibility-baseline-invalid",
                repository.relative(repository.baseline_path),
                "baseline schemas must be an object",
            )
        ]

    for relative_path, baseline_schema in sorted(baseline_schemas.items()):
        current_path = repository.contracts_root / relative_path
        location = "schemas/{0}".format(relative_path)
        if not current_path.is_file():
            findings.append(Finding("compatibility-schema-removed", location, "schema source was removed"))
            continue
        try:
            current_schema = load_json(current_path)
        except ContractToolError as error:
            findings.append(Finding("compatibility-schema-unreadable", location, str(error)))
            continue
        for message in compare_schema(baseline_schema, current_schema):
            findings.append(Finding("compatibility-breaking-schema", location, message))

    baseline_openapi = baseline.get("openapi")
    if not isinstance(baseline_openapi, dict):
        findings.append(
            Finding("compatibility-baseline-invalid", "openapi", "baseline OpenAPI must be an object")
        )
    else:
        try:
            current_openapi = load_json(repository.openapi_path)
            for message in compare_openapi(baseline_openapi, current_openapi):
                findings.append(Finding("compatibility-breaking-openapi", "openapi", message))
        except ContractToolError as error:
            findings.append(Finding("compatibility-openapi-unreadable", "openapi", str(error)))
    return findings


def verify_all(repository: ContractRepository) -> List[Finding]:
    """Run all non-mutating contract checks in a stable order."""

    try:
        repository.load()
    except ContractToolError as error:
        return [Finding("contract-source-unreadable", "contracts", str(error))]

    findings = []
    findings.extend(repository.validate_schema_documents())
    findings.extend(validate_catalog(repository))
    findings.extend(validate_examples(repository))
    findings.extend(validate_operation_policy(repository))
    findings.extend(validate_openapi(repository))
    findings.extend(validate_generated_openapi_bundle(repository))
    findings.extend(validate_compatibility(repository))
    return findings
