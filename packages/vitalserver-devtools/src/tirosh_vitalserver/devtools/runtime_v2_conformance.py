from __future__ import annotations

from dataclasses import dataclass
import json
from typing import Any, Callable, Mapping
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


PLATFORM_SERVICE_ROLES = frozenset(
    {
        "runtime-provider",
        "public-proxy",
        "log-sync",
        "sleep-prevention",
        "watchdog",
    }
)

PLATFORM_SERVICE_STATES = frozenset(
    {
        "running",
        "stopped",
        "not-installed",
        "unavailable",
        "read-failed",
        "permission-denied",
        "failed",
    }
)

PLATFORM_CAPABILITIES = frozenset(
    {
        "canInstallRuntime",
        "canUninstallRuntime",
        "canApplyBundle",
        "canRollback",
        "canRollbackRelease",
        "canEditRuntimeProviderResources",
        "canEditNetworkExposure",
        "canResetAdminPassword",
        "canOpenLocalFiles",
        "canStreamLogs",
        "canControlRuntimeServices",
        "canExportLogs",
        "canViewReleaseMetadata",
    }
)

LEGACY_PLATFORM_FIELDS = frozenset(
    {
        "runtimeState",
        "runtimeVersion",
        "vmState",
        "vmErrors",
        "guestAddressRead",
        "vmIP",
        "guestHTTP",
        "hostProxyHTTP",
        "runtimeControlHTTP",
        "runtimeControlStartedAt",
        "redisUIHTTP",
        "swaggerUIHTTP",
        "proxyPort",
        "failureReasons",
        "canEditVMResources",
    }
)


class ConformanceTransportError(RuntimeError):
    pass


@dataclass(frozen=True)
class ConformanceIssue:
    resource: str
    message: str


@dataclass(frozen=True)
class ConformanceReport:
    checked_resources: tuple[str, ...]
    issues: tuple[ConformanceIssue, ...]

    @property
    def passed(self) -> bool:
        return not self.issues


JSONGetter = Callable[[str], Mapping[str, Any]]


class RuntimeV2ConformanceSuite:
    def __init__(self, get_json: JSONGetter) -> None:
        self._get_json = get_json

    def run(self, *, platform: bool = True, runtime: bool = True) -> ConformanceReport:
        resources: list[tuple[str, Callable[[Mapping[str, Any]], list[str]]]] = []
        if platform:
            resources.extend(
                [
                    ("/platform", validate_platform_state),
                    ("/platform/capabilities", validate_platform_capabilities),
                    ("/platform/operations", validate_platform_operations),
                    ("/platform/runtime-endpoint", validate_explicit_resource),
                    ("/platform/runtime-provider", validate_explicit_resource),
                ]
            )
        if runtime:
            resources.extend(
                [
                    ("/runtime/capabilities", validate_runtime_capabilities),
                    ("/runtime/services", validate_runtime_services),
                    ("/runtime/stack", validate_runtime_stack),
                ]
            )

        checked: list[str] = []
        issues: list[ConformanceIssue] = []
        for resource, validator in resources:
            checked.append(resource)
            try:
                document = self._get_json(resource)
            except ConformanceTransportError as error:
                issues.append(ConformanceIssue(resource, str(error)))
                continue
            except Exception as error:  # caller failures remain visible and classified
                issues.append(
                    ConformanceIssue(
                        resource,
                        f"unclassified transport failure: {type(error).__name__}: {error}",
                    )
                )
                continue
            for message in validator(document):
                issues.append(ConformanceIssue(resource, message))
        return ConformanceReport(tuple(checked), tuple(issues))


def http_json_getter(
    *, base_url: str, timeout_seconds: float, bearer_token: str | None = None
) -> JSONGetter:
    normalized_base = base_url.rstrip("/")

    def get_json(path: str) -> Mapping[str, Any]:
        headers = {"Accept": "application/json"}
        if bearer_token is not None:
            headers["Authorization"] = f"Bearer {bearer_token}"
        request = Request(f"{normalized_base}{path}", headers=headers, method="GET")
        try:
            with urlopen(request, timeout=timeout_seconds) as response:
                status = response.status
                body = response.read()
        except HTTPError as error:
            body = error.read().decode("utf-8", errors="replace")
            raise ConformanceTransportError(
                f"HTTP failure status={error.code} body={body}"
            ) from error
        except URLError as error:
            raise ConformanceTransportError(f"network failure: {error.reason}") from error
        except TimeoutError as error:
            raise ConformanceTransportError("network timeout") from error

        if status < 200 or status >= 300:
            raise ConformanceTransportError(f"HTTP failure status={status}")
        try:
            value = json.loads(body)
        except (UnicodeDecodeError, json.JSONDecodeError) as error:
            raise ConformanceTransportError(f"JSON decode failure: {error}") from error
        if not isinstance(value, dict):
            raise ConformanceTransportError(
                f"JSON contract failure: expected object, got {type(value).__name__}"
            )
        return value

    return get_json


def validate_platform_state(document: Mapping[str, Any]) -> list[str]:
    issues = _required_types(
        document,
        {
            "runtimeInstallationState": str,
            "services": list,
        },
    )
    legacy = sorted(LEGACY_PLATFORM_FIELDS.intersection(document))
    if legacy:
        issues.append(f"legacy or platform-specific fields present: {', '.join(legacy)}")

    services = document.get("services")
    if isinstance(services, list):
        roles: list[str] = []
        for index, service in enumerate(services):
            if not isinstance(service, dict):
                issues.append(f"services[{index}] must be an object")
                continue
            issues.extend(
                f"services[{index}].{message}"
                for message in _required_types(service, {"role": str, "state": str})
            )
            issues.extend(
                f"services[{index}].{message}"
                for message in _required_nullable(service, "readError", str)
            )
            role = service.get("role")
            if isinstance(role, str):
                roles.append(role)
            state = service.get("state")
            read_error = service.get("readError")
            if isinstance(state, str) and state not in PLATFORM_SERVICE_STATES:
                issues.append(f"services[{index}].state has unknown value: {state}")
            if state in {"unavailable", "read-failed", "permission-denied", "failed"} and (
                not isinstance(read_error, str) or not read_error.strip()
            ):
                issues.append(f"services[{index}].readError must explain unavailable or failed state")
            if state in {"running", "stopped", "not-installed"} and read_error is not None:
                issues.append(
                    f"services[{index}].readError must be null for successful state"
                )
        duplicates = sorted({role for role in roles if roles.count(role) > 1})
        if duplicates:
            issues.append(f"duplicate Platform service roles: {', '.join(duplicates)}")
        unknown = sorted(set(roles) - PLATFORM_SERVICE_ROLES)
        if unknown:
            issues.append(f"unknown Platform service roles: {', '.join(unknown)}")
        missing = sorted(PLATFORM_SERVICE_ROLES - set(roles))
        if missing:
            issues.append(f"missing Platform service roles: {', '.join(missing)}")
    return issues


def validate_platform_capabilities(document: Mapping[str, Any]) -> list[str]:
    issues: list[str] = []
    actual = set(document)
    missing = sorted(PLATFORM_CAPABILITIES - actual)
    extra = sorted(actual - PLATFORM_CAPABILITIES)
    if missing:
        issues.append(f"missing capabilities: {', '.join(missing)}")
    if extra:
        issues.append(f"unexpected capabilities: {', '.join(extra)}")
    for capability in sorted(PLATFORM_CAPABILITIES.intersection(actual)):
        if not isinstance(document[capability], bool):
            issues.append(f"{capability} must be boolean")
    return issues


def validate_platform_operations(document: Mapping[str, Any]) -> list[str]:
    issues = _required_nullable(document, "activeOperation", str)
    for name in ("install", "lease"):
        value = document.get(name)
        if not isinstance(value, dict):
            issues.append(f"{name} must be an object")
            continue
        issues.extend(
            f"{name}.{message}"
            for message in _required_types(value, {"state": str})
        )
        issues.extend(f"{name}.{message}" for message in _required_nullable(value, "document", dict))
        issues.extend(f"{name}.{message}" for message in _required_nullable(value, "readError", str))
    lease = document.get("lease")
    if isinstance(lease, dict):
        issues.extend(
            f"lease.{message}" for message in _required_nullable(lease, "staleReason", str)
        )
    return issues


def validate_explicit_resource(document: Mapping[str, Any]) -> list[str]:
    issues = _required_types(document, {"state": str})
    if "readError" not in document:
        issues.append("readError is required and must be explicit null or string")
    elif document["readError"] is not None and not isinstance(document["readError"], str):
        issues.append("readError must be explicit null or string")
    if "read" not in document and "document" not in document:
        issues.append("read or document field is required")
    return issues


def validate_runtime_capabilities(document: Mapping[str, Any]) -> list[str]:
    issues = _required_types(document, {"schemaVersion": int, "capabilities": list})
    values = document.get("capabilities")
    if isinstance(values, list):
        if not all(isinstance(value, str) and value for value in values):
            issues.append("capabilities must contain non-empty strings")
        if len(values) != len(set(value for value in values if isinstance(value, str))):
            issues.append("capabilities must not contain duplicates")
    return issues


def validate_runtime_services(document: Mapping[str, Any]) -> list[str]:
    issues = _required_types(document, {"services": list})
    services = document.get("services")
    if isinstance(services, list):
        if not all(isinstance(service, str) and service for service in services):
            issues.append("services must contain non-empty strings")
        if len(services) != len(set(service for service in services if isinstance(service, str))):
            issues.append("services must not contain duplicates")
    return issues


def validate_runtime_stack(document: Mapping[str, Any]) -> list[str]:
    issues = _required_types(
        document,
        {"state": str, "observedAt": str, "services": list, "probeErrors": list},
    )
    services = document.get("services")
    if isinstance(services, list):
        for index, service in enumerate(services):
            if not isinstance(service, dict):
                issues.append(f"services[{index}] must be an object")
                continue
            issues.extend(
                f"services[{index}].{message}"
                for message in _required_types(
                    service,
                    {"service": str, "state": str, "health": str, "observedAt": str},
                )
            )
    return issues


def _required_types(
    document: Mapping[str, Any], requirements: Mapping[str, type]
) -> list[str]:
    issues: list[str] = []
    for field, expected_type in requirements.items():
        if field not in document:
            issues.append(f"{field} is required")
        elif not isinstance(document[field], expected_type):
            issues.append(f"{field} must be {expected_type.__name__}")
    return issues


def _required_nullable(
    document: Mapping[str, Any], field: str, expected_type: type
) -> list[str]:
    if field not in document:
        return [f"{field} is required and must be explicit null or {expected_type.__name__}"]
    value = document[field]
    if value is not None and not isinstance(value, expected_type):
        return [f"{field} must be explicit null or {expected_type.__name__}"]
    return []
