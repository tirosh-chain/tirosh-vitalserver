#!/usr/bin/env python3
"""Prove Recorder observability on Guest compose PostgreSQL.

Default query owner is recorder-ingress on 127.0.0.1:18083, which implements
the same /runtime/vitaldb paths as the VM Guest Control systemd proxy on
:18330. This script does not claim that recorder-ingress owns Guest Control.
Installed Guest Control, Helper, and PWA remain unproven.

The proof composes with an ephemeral published PostgreSQL host port
(--postgres-host-port 0) because neither the proof nor product services
consume the host-published PostgreSQL port. The Guest production default
15432 stays the compose default via VITALSERVER_POSTGRES_BIND_PORT.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import re
import shlex
import socket
import subprocess
import sys
import time
import uuid
from collections.abc import Callable, Mapping
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from http.client import RemoteDisconnected
from pathlib import Path
from typing import Any, Literal, Protocol
from urllib.error import HTTPError, URLError
from urllib.parse import quote, urlencode
from urllib.request import Request, urlopen

REPO_ROOT = Path(__file__).resolve().parent.parent
GUEST_COMPOSE_FILE = "apps/vitalserver-macos-runtime/Support/Guest/compose.yaml"
DEFAULT_COMPOSE_PROJECT = "vitalserver-recorder-observability-proof"
DEFAULT_BIND_HOST = "127.0.0.1"
DEFAULT_HTTP_PORT = "18083"
DEFAULT_TESTDATA = (
    REPO_ROOT
    / "apps/vitalserver-recorder-ingress/contracts/recorder-observability/testdata"
)
OBSERVATION_GOLDEN = "observation-v2-valid.json"
BOOT_EVENT_GOLDEN = "boot-event-v2-valid.json"
GUEST_COMPOSE_SERVICES = (
    "postgres",
    "postgres-migrate",
    "redis",
    "app",
    "recorder-recovery",
    "recorder-ingress",
)
QUERY_OWNERS = ("recorder-ingress", "guest-control")
QueryOwner = Literal["recorder-ingress", "guest-control"]
DEFAULT_REQUEST_TIMEOUT_SECONDS = 10.0
VRCODE_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$")
JsonObject = dict[str, Any]


class ProofError(RuntimeError):
    """Explicit proof failure. Missing, invalid, and unavailable stay distinct."""


class ProjectionPendingError(ProofError):
    """Whole current projection is absent. Nested loaded fields are not pending."""

    def __init__(self, state: str) -> None:
        super().__init__(f"projection not loaded: {state}")
        self.state = state


class TransportError(ProofError):
    def __init__(self, message: str, *, kind: str) -> None:
        super().__init__(message)
        self.kind = kind


@dataclass(frozen=True)
class HttpResponse:
    status_code: int
    body: bytes


@dataclass(frozen=True)
class ExpectedDetail:
    boot_id: str
    boot_state: str
    ordering_state: str
    evidence_health_state: str
    incident_state: str
    report_state: str


class HttpClient(Protocol):
    def request(
        self,
        method: str,
        url: str,
        *,
        headers: dict[str, str] | None = None,
        body: bytes | None = None,
        timeout: float | None = None,
    ) -> HttpResponse: ...


class CommandRunner(Protocol):
    def run(self, argv: list[str], *, env: dict[str, str]) -> None: ...


class UrllibHttpClient:
    def request(
        self,
        method: str,
        url: str,
        *,
        headers: dict[str, str] | None = None,
        body: bytes | None = None,
        timeout: float | None = None,
    ) -> HttpResponse:
        request = Request(
            url,
            data=body,
            method=method,
            headers=headers or {},
        )
        try:
            with urlopen(request, timeout=timeout) as response:
                return HttpResponse(response.status, response.read())
        except HTTPError as error:
            return HttpResponse(error.code, error.read())
        except TimeoutError as error:
            raise TransportError(
                "dependency timed out",
                kind="timeout",
            ) from error
        except RemoteDisconnected as error:
            raise TransportError(
                "dependency unavailable: remote end closed connection without response",
                kind="unavailable",
            ) from error
        except URLError as error:
            if isinstance(error.reason, TimeoutError | socket.timeout):
                raise TransportError(
                    "dependency timed out",
                    kind="timeout",
                ) from error
            raise TransportError(
                f"dependency unavailable: {error.reason}",
                kind="unavailable",
            ) from error


class SubprocessCommandRunner:
    def run(self, argv: list[str], *, env: dict[str, str]) -> None:
        completed = subprocess.run(argv, env=env, check=False)
        if completed.returncode != 0:
            raise ProofError(
                f"command failed status={completed.returncode}: {shlex.join(argv)}"
            )


def main(
    argv: list[str] | None = None,
    *,
    http: HttpClient | None = None,
    commands: CommandRunner | None = None,
    sleep: Callable[[float], None] = time.sleep,
    monotonic: Callable[[], float] = time.monotonic,
    clock: Callable[[], datetime] | None = None,
) -> int:
    args = parse_args(argv)
    http_client = http or UrllibHttpClient()
    command_runner = commands or SubprocessCommandRunner()
    now = clock or (lambda: datetime.now(UTC))
    observation = load_certified_document(Path(args.testdata) / OBSERVATION_GOLDEN)
    boot_event = load_certified_document(Path(args.testdata) / BOOT_EVENT_GOLDEN)
    device_id = required_device_id(observation, boot_event)
    expected = expected_detail_from_goldens(observation, boot_event)
    vrcode = args.vrcode or allocate_proof_vrcode(
        now=now().isoformat(),
        suffix=uuid.uuid4().hex[:8],
    )
    if VRCODE_PATTERN.fullmatch(vrcode) is None:
        raise ProofError(f"vrcode is invalid: {vrcode}")

    if args.start_compose:
        start_guest_compose(args, command_runner)
        wait_for_ingress_health(
            http_client,
            args.ingress_base_url,
            timeout_seconds=args.ready_timeout,
            interval_seconds=args.projection_interval,
            request_timeout=args.request_timeout,
            sleep=sleep,
            monotonic=monotonic,
        )

    observation_receipt = post_certified_line(
        http_client,
        args.ingress_base_url,
        vrcode,
        "observations",
        observation,
        device_id,
        expected_accepted=1,
        expected_duplicates=0,
        request_timeout=args.request_timeout,
    )
    boot_receipt = post_certified_line(
        http_client,
        args.ingress_base_url,
        vrcode,
        "boot-events",
        boot_event,
        device_id,
        expected_accepted=1,
        expected_duplicates=0,
        request_timeout=args.request_timeout,
    )
    duplicate_receipt = post_certified_line(
        http_client,
        args.ingress_base_url,
        vrcode,
        "observations",
        observation,
        device_id,
        expected_accepted=0,
        expected_duplicates=1,
        request_timeout=args.request_timeout,
    )
    detail = wait_for_projection_loaded(
        http_client,
        args.query_base_url,
        vrcode,
        query_owner=args.query_owner,
        expected=expected,
        timeout_seconds=args.projection_timeout,
        interval_seconds=args.projection_interval,
        request_timeout=args.request_timeout,
        sleep=sleep,
        monotonic=monotonic,
    )
    window = query_window(now())
    timeline = get_json(
        http_client,
        observability_query_url(
            args.query_base_url,
            vrcode,
            "timeline",
            {
                "from": window["from"],
                "until": window["until"],
                "bucketSeconds": "900",
            },
        ),
        query_owner=args.query_owner,
        what="timeline",
        request_timeout=args.request_timeout,
    )
    assert_timeline_loaded(timeline, vrcode, query_owner=args.query_owner)
    incidents = get_json(
        http_client,
        observability_query_url(
            args.query_base_url,
            vrcode,
            "incidents",
            {
                "from": window["from"],
                "until": window["until"],
                "limit": "50",
            },
        ),
        query_owner=args.query_owner,
        what="incidents",
        request_timeout=args.request_timeout,
    )
    assert_incidents_loaded(incidents, vrcode, query_owner=args.query_owner)

    print(
        json.dumps(
            {
                "ok": True,
                "proofScope": "guest-compose-recorder-observability",
                "queryOwner": args.query_owner,
                "queryBaseUrl": args.query_base_url,
                "vrcode": vrcode,
                "deviceId": device_id,
                "profilePosted": False,
                "admissions": {
                    "observation": observation_receipt,
                    "bootEvent": boot_receipt,
                    "observationDuplicate": duplicate_receipt,
                },
                "detail": {
                    "state": detail["state"],
                    "vrcode": detail["vrcode"],
                    "boot": detail["boot"],
                    "report": {"state": detail["report"]["state"]},
                    "evidenceHealth": {"state": detail["evidenceHealth"]["state"]},
                    "incidentState": {"state": detail["incidentState"]["state"]},
                },
                "timeline": {
                    "state": timeline["state"],
                    "vrcode": timeline["vrcode"],
                    "timeBasis": timeline["timeBasis"],
                    "supportState": timeline["supportState"],
                    "bucketCount": len(timeline["buckets"]),
                },
                "incidents": {
                    "state": incidents["state"],
                    "vrcode": incidents["vrcode"],
                    "empty": incidents["incidents"] == [],
                },
            },
            ensure_ascii=False,
            sort_keys=True,
        )
    )
    return 0


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Prove certified Recorder observability NDJSON through Guest "
            "compose recorder-ingress PostgreSQL and a direct "
            "recorder-ingress query of /runtime/vitaldb paths. Mutates "
            "dedicated compose PostgreSQL. Root send_data compose has no "
            "PostgreSQL and must not be used. VM Guest Control :18330 is a "
            "separate systemd proxy and stays unproven unless "
            "--query-owner guest-control is set with an explicit "
            "--query-base-url."
        )
    )
    parser.add_argument(
        "--compose",
        default=os.environ.get("DOCKER_COMPOSE", "docker compose"),
    )
    parser.add_argument("--compose-file", default=GUEST_COMPOSE_FILE)
    parser.add_argument("--compose-project", default=DEFAULT_COMPOSE_PROJECT)
    parser.add_argument(
        "--postgres-host-port",
        default=os.environ.get(
            "VITALSERVER_POSTGRES_BIND_PORT",
            "0",
        ),
        help=(
            "Published PostgreSQL host port for Guest compose. 0 selects an "
            "ephemeral Docker host port because the proof does not consume the "
            "host-published PostgreSQL port. 15432 preserves the Guest "
            "production default. Valid range is 0..65535."
        ),
    )
    parser.add_argument("--bind-host", default=DEFAULT_BIND_HOST)
    parser.add_argument("--http-port", default=DEFAULT_HTTP_PORT)
    parser.add_argument("--ingress-base-url")
    parser.add_argument(
        "--query-owner",
        choices=QUERY_OWNERS,
        default="recorder-ingress",
    )
    parser.add_argument("--query-base-url")
    parser.add_argument("--testdata", default=str(DEFAULT_TESTDATA))
    parser.add_argument("--vrcode")
    parser.add_argument("--start-compose", action="store_true")
    parser.add_argument("--ready-timeout", type=float, default=90.0)
    parser.add_argument("--projection-timeout", type=float, default=30.0)
    parser.add_argument("--projection-interval", type=float, default=0.25)
    parser.add_argument(
        "--request-timeout",
        type=float,
        default=DEFAULT_REQUEST_TIMEOUT_SECONDS,
        help=(
            "Positive urllib timeout in seconds for every health, admission, "
            "and query HTTP call. Default 10 is for local Guest compose. "
            "Zero, negative, and non-finite values are invalid."
        ),
    )
    args = parser.parse_args(argv)
    args.request_timeout = require_positive_timeout(
        args.request_timeout, field="request-timeout"
    )
    args.postgres_host_port = require_bind_port(
        args.postgres_host_port, field="postgres-host-port"
    )
    if not args.ingress_base_url:
        args.ingress_base_url = f"http://{args.bind_host}:{args.http_port}"
    if args.query_owner == "recorder-ingress":
        if not args.query_base_url:
            args.query_base_url = args.ingress_base_url
    elif not args.query_base_url:
        raise ProofError(
            "query-owner=guest-control requires an explicit --query-base-url "
            "for an already-running Guest Control endpoint"
        )
    return args


def load_certified_document(path: Path) -> JsonObject:
    if not path.is_file():
        raise ProofError(f"certified golden is missing: {path}")
    try:
        document = json.loads(path.read_text(encoding="utf-8"))
    except OSError as error:
        raise ProofError(f"certified golden is unreadable: {path}: {error}") from error
    except json.JSONDecodeError as error:
        raise ProofError(
            f"certified golden is invalid JSON: {path}: {error}"
        ) from error
    if not isinstance(document, dict):
        raise ProofError(f"certified golden is not a JSON object: {path}")
    return document


def allocate_proof_vrcode(*, now: str, suffix: str) -> str:
    moment = datetime.fromisoformat(now)
    if moment.tzinfo is None:
        raise ProofError(f"proof clock is missing timezone: {now}")
    stamp = moment.astimezone(UTC).strftime("%Y%m%dT%H%M%SZ")
    vrcode = f"PROOF-{stamp}-{suffix}"
    if VRCODE_PATTERN.fullmatch(vrcode) is None:
        raise ProofError(f"allocated vrcode is invalid: {vrcode}")
    return vrcode


def required_device_id(observation: JsonObject, boot_event: JsonObject) -> str:
    observation_id = observation.get("deviceId")
    boot_id = boot_event.get("deviceId")
    if not isinstance(observation_id, str) or observation_id.strip() == "":
        raise ProofError("observation golden is missing deviceId")
    if observation_id != boot_id:
        raise ProofError(
            "certified goldens have distinct deviceId values: "
            f"observation={observation_id!r} bootEvent={boot_id!r}"
        )
    return observation_id


def expected_detail_from_goldens(
    observation: JsonObject,
    boot_event: JsonObject,
) -> ExpectedDetail:
    if observation.get("schemaVersion") != "v2":
        raise ProofError("observation golden schemaVersion is not v2")
    if observation.get("kind") != "device-health":
        raise ProofError("observation golden kind is not device-health")
    if boot_event.get("schemaVersion") != "v2":
        raise ProofError("boot-event golden schemaVersion is not v2")
    if boot_event.get("kind") != "boot-event":
        raise ProofError("boot-event golden kind is not boot-event")
    if boot_event.get("eventType") != "boot-started":
        raise ProofError("boot-event golden eventType is not boot-started")
    observation_boot_id = required_golden_string(
        observation, "bootId", what="observation"
    )
    boot_event_boot_id = required_golden_string(boot_event, "bootId", what="boot-event")
    if observation_boot_id != boot_event_boot_id:
        raise ProofError(
            "certified goldens have distinct bootId values: "
            f"observation={observation_boot_id!r} bootEvent={boot_event_boot_id!r}"
        )
    boot_id = observation_boot_id
    payload = required_object(observation, "payload")
    evidence = required_object(payload, "evidenceHealth")
    if evidence.get("state") != "healthy":
        raise ProofError("observation golden evidenceHealth.state is not healthy")
    incident = required_object(payload, "incidentState")
    if incident.get("policyVersion") != "recorder-incident/v1":
        raise ProofError(
            "observation golden incidentState.policyVersion is not recorder-incident/v1"
        )
    return ExpectedDetail(
        boot_id=boot_id,
        boot_state="started",
        ordering_state="ordered",
        evidence_health_state="healthy",
        incident_state="reported",
        report_state="missing",
    )


def start_guest_compose(
    args: argparse.Namespace,
    commands: CommandRunner,
) -> None:
    compose = shlex.split(args.compose)
    env = os.environ.copy()
    env["VITALSERVER_POSTGRES_BIND_PORT"] = str(args.postgres_host_port)
    commands.run(
        [
            *compose,
            "--project-name",
            args.compose_project,
            "--project-directory",
            str(REPO_ROOT),
            "--file",
            args.compose_file,
            "up",
            "-d",
            "--build",
            *GUEST_COMPOSE_SERVICES,
        ],
        env=env,
    )


def wait_for_ingress_health(
    http: HttpClient,
    ingress_base_url: str,
    *,
    timeout_seconds: float,
    interval_seconds: float,
    request_timeout: float,
    sleep: Callable[[float], None],
    monotonic: Callable[[], float],
) -> None:
    deadline = monotonic() + timeout_seconds
    last_error = "recorder-ingress health was not observed"
    while monotonic() <= deadline:
        try:
            response = http.request(
                "GET",
                f"{ingress_base_url}/recorder-ingress/health",
                headers={"Accept": "application/json"},
                timeout=request_timeout,
            )
        except TransportError as error:
            last_error = str(error)
        else:
            if response.status_code == 204:
                return
            last_error = f"recorder-ingress health status={response.status_code}"
        if monotonic() >= deadline:
            break
        sleep(interval_seconds)
    raise ProofError(f"admission unavailable: {last_error}")


def post_certified_line(
    http: HttpClient,
    ingress_base_url: str,
    vrcode: str,
    resource: str,
    document: JsonObject,
    device_id: str,
    *,
    expected_accepted: int,
    expected_duplicates: int,
    request_timeout: float,
) -> JsonObject:
    payload = json.dumps(document, ensure_ascii=False, separators=(",", ":"))
    response = http.request(
        "POST",
        f"{ingress_base_url}/api/v1/recorders/{quote(vrcode, safe='')}/{resource}",
        headers={
            "content-type": "application/x-ndjson",
            "x-device-id": device_id,
            "Accept": "application/json",
        },
        body=f"{payload}\n".encode(),
        timeout=request_timeout,
    )
    return assert_admitted_not_quarantined(
        response,
        resource=resource,
        expected_accepted=expected_accepted,
        expected_duplicates=expected_duplicates,
    )


def assert_admitted_not_quarantined(
    response: HttpResponse,
    *,
    resource: str,
    expected_accepted: int | None = None,
    expected_duplicates: int | None = None,
) -> JsonObject:
    if 400 <= response.status_code < 500:
        document = optional_json_object(response)
        reason = document.get("reason") if document else None
        raise ProofError(
            f"request rejected status={response.status_code} "
            f"resource={resource} reason={reason}"
        )
    if response.status_code == 503:
        document = optional_json_object(response)
        reason = document.get("reason") if document else None
        raise ProofError(
            f"admission unavailable status=503 resource={resource} reason={reason}"
        )
    if response.status_code != 202:
        raise ProofError(
            f"admission status={response.status_code} resource={resource} "
            "is not a durable 202 receipt"
        )
    document = parse_json_object(response, what=f"{resource} admission")
    if document.get("state") != "admitted":
        raise ProofError("HTTP 202 is not an admission receipt")
    request_id = document.get("requestId")
    if not isinstance(request_id, str) or request_id.strip() == "":
        raise ProofError("missing string field: requestId")
    accepted = required_int(document, "accepted")
    duplicates = required_int(document, "duplicates")
    quarantined = required_int(document, "quarantined")
    if quarantined != 0:
        raise ProofError(f"line receipt quarantined={quarantined}")
    if expected_accepted is not None and accepted != expected_accepted:
        raise ProofError(f"{resource} accepted={accepted} expected={expected_accepted}")
    if expected_duplicates is not None and duplicates != expected_duplicates:
        raise ProofError(
            f"{resource} duplicates={duplicates} expected={expected_duplicates}"
        )
    return document


def wait_for_projection_loaded(
    http: HttpClient,
    query_base_url: str,
    vrcode: str,
    *,
    query_owner: QueryOwner,
    expected: ExpectedDetail,
    timeout_seconds: float,
    interval_seconds: float,
    request_timeout: float,
    sleep: Callable[[float], None],
    monotonic: Callable[[], float],
) -> JsonObject:
    deadline = monotonic() + timeout_seconds
    last_error = ProjectionPendingError("missing")
    while monotonic() <= deadline:
        try:
            document = read_detail(
                http,
                query_base_url,
                vrcode,
                query_owner=query_owner,
                request_timeout=request_timeout,
            )
            assert_detail_loaded(
                document,
                vrcode,
                query_owner=query_owner,
                expected=expected,
            )
            return document
        except ProjectionPendingError as error:
            last_error = error
        if monotonic() >= deadline:
            break
        sleep(interval_seconds)
    raise last_error


def read_detail(
    http: HttpClient,
    query_base_url: str,
    vrcode: str,
    *,
    query_owner: QueryOwner,
    request_timeout: float,
) -> JsonObject:
    url = (
        f"{query_base_url}/runtime/vitaldb/recorders/"
        f"{quote(vrcode, safe='')}/observability"
    )
    response = http.request(
        "GET",
        url,
        headers={"Accept": "application/json"},
        timeout=request_timeout,
    )
    if response.status_code == 503:
        document = optional_json_object(response)
        raise ProofError(query_unavailable(query_owner, document))
    if response.status_code not in {200, 404}:
        raise ProofError(
            f"{query_owner} detail status={response.status_code} "
            "is not a loaded projection"
        )
    document = parse_json_object(response, what=f"{query_owner} detail")
    if response.status_code == 404:
        state = document.get("state")
        pending = state if isinstance(state, str) and state else "not_found"
        raise ProjectionPendingError(pending)
    return document


def assert_detail_loaded(
    document: Mapping[str, Any],
    vrcode: str,
    *,
    query_owner: QueryOwner,
    expected: ExpectedDetail,
) -> None:
    state = document.get("state")
    if state == "unavailable":
        raise ProofError(query_unavailable(query_owner, document))
    if state in {"notReported", "not_found"}:
        raise ProjectionPendingError(str(state))
    if state != "loaded":
        raise ProofError("HTTP 200 is not a loaded projection")
    if document.get("vrcode") != vrcode:
        raise ProofError(
            f"detail vrcode={document.get('vrcode')!r} expected={vrcode!r}"
        )
    if "readError" not in document or document["readError"] is not None:
        raise ProofError("loaded detail readError is not null")
    boot = required_object(document, "boot")
    report = required_object(document, "report")
    evidence = required_object(document, "evidenceHealth")
    incident = required_object(document, "incidentState")
    if boot.get("state") != expected.boot_state:
        raise ProofError(
            f"boot.state={boot.get('state')!r} expected={expected.boot_state!r}"
        )
    if boot.get("orderingState") != expected.ordering_state:
        raise ProofError(
            f"boot.orderingState={boot.get('orderingState')!r} "
            f"expected={expected.ordering_state!r}"
        )
    if boot.get("bootId") != expected.boot_id:
        raise ProofError(
            f"boot.bootId={boot.get('bootId')!r} expected={expected.boot_id!r}"
        )
    if report.get("state") != expected.report_state:
        raise ProofError(
            f"report.state={report.get('state')!r} expected={expected.report_state!r}"
        )
    if evidence.get("state") != expected.evidence_health_state:
        raise ProofError(
            f"evidenceHealth.state={evidence.get('state')!r} "
            f"expected={expected.evidence_health_state!r}"
        )
    if incident.get("state") != expected.incident_state:
        raise ProofError(
            f"incidentState.state={incident.get('state')!r} "
            f"expected={expected.incident_state!r}"
        )


def assert_timeline_loaded(
    document: Mapping[str, Any],
    vrcode: str,
    *,
    query_owner: QueryOwner,
) -> None:
    state = document.get("state")
    if state == "unavailable":
        raise ProofError(query_unavailable(query_owner, document))
    if state == "notReported":
        raise ProofError("timeline state=notReported")
    if state == "unsupported":
        raise ProofError("timeline state=unsupported")
    if state != "loaded":
        raise ProofError(f"timeline state={state!r} is not loaded")
    if document.get("vrcode") != vrcode:
        raise ProofError(
            f"timeline vrcode={document.get('vrcode')!r} expected={vrcode!r}"
        )
    if document.get("timeBasis") != "receivedAt":
        raise ProofError("timeline timeBasis is not receivedAt")
    if document.get("supportState") not in {"supported", "unsupported", "unknown"}:
        raise ProofError("timeline supportState is missing")
    buckets = document.get("buckets")
    if not isinstance(buckets, list) or buckets == []:
        raise ProofError("loaded timeline is missing buckets")
    if "readError" not in document or document["readError"] is not None:
        raise ProofError("loaded timeline readError is not null")


def assert_incidents_loaded(
    document: Mapping[str, Any],
    vrcode: str,
    *,
    query_owner: QueryOwner,
) -> None:
    state = document.get("state")
    if state == "unavailable":
        raise ProofError(query_unavailable(query_owner, document))
    if state != "loaded":
        raise ProofError(f"empty incidents remain loaded; state={state}")
    if "incidents" not in document or not isinstance(document["incidents"], list):
        raise ProofError("missing incidents list")
    if document.get("vrcode") != vrcode:
        raise ProofError(
            f"incidents vrcode={document.get('vrcode')!r} expected={vrcode!r}"
        )
    if document.get("timeBasis") != "receivedAt":
        raise ProofError("incidents timeBasis is not receivedAt")
    if "readError" not in document or document["readError"] is not None:
        raise ProofError("loaded incidents readError is not null")


def get_json(
    http: HttpClient,
    url: str,
    *,
    query_owner: QueryOwner,
    what: str,
    request_timeout: float,
) -> JsonObject:
    response = http.request(
        "GET",
        url,
        headers={"Accept": "application/json"},
        timeout=request_timeout,
    )
    if response.status_code == 503:
        document = optional_json_object(response)
        raise ProofError(query_unavailable(query_owner, document))
    if response.status_code == 400:
        document = optional_json_object(response)
        raise ProofError(
            f"request rejected status=400 reason={(document or {}).get('reason')}"
        )
    if response.status_code != 200:
        raise ProofError(f"{query_owner} {what} status={response.status_code}")
    return parse_json_object(response, what=f"{query_owner} {what}")


def observability_query_url(
    base_url: str,
    vrcode: str,
    resource: str,
    query: Mapping[str, str],
) -> str:
    path = (
        f"{base_url}/runtime/vitaldb/recorders/"
        f"{quote(vrcode, safe='')}/observability/{resource}"
    )
    return f"{path}?{urlencode(query)}"


def query_window(moment: datetime) -> dict[str, str]:
    if moment.tzinfo is None:
        raise ProofError("proof clock is missing timezone")
    until = moment.astimezone(UTC)
    started = until - timedelta(hours=1)
    return {
        "from": started.strftime("%Y-%m-%dT%H:%M:%SZ"),
        "until": (until + timedelta(hours=1)).strftime("%Y-%m-%dT%H:%M:%SZ"),
    }


def query_unavailable(
    query_owner: str,
    document: Mapping[str, Any] | None,
) -> str:
    detail = None if document is None else document.get("reason")
    if detail is None and document is not None:
        detail = document.get("readError")
    return f"{query_owner} query unavailable: {detail}"


def parse_json_object(response: HttpResponse, *, what: str) -> JsonObject:
    try:
        document = json.loads(response.body.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ProofError(f"{what} returned invalid JSON: {error}") from error
    if not isinstance(document, dict):
        raise ProofError(f"{what} returned a non-object JSON document")
    return document


def optional_json_object(response: HttpResponse) -> JsonObject | None:
    if not response.body:
        return None
    try:
        document = json.loads(response.body.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError):
        return None
    return document if isinstance(document, dict) else None


def required_object(document: Mapping[str, Any], field: str) -> JsonObject:
    value = document.get(field)
    if not isinstance(value, dict):
        raise ProofError(f"missing object field: {field}")
    return value


def require_positive_timeout(value: float, *, field: str) -> float:
    if type(value) is bool or not isinstance(value, int | float):
        raise ProofError(f"{field} is invalid: {value!r}")
    timeout = float(value)
    if not math.isfinite(timeout) or timeout <= 0:
        raise ProofError(f"{field} is invalid: {value!r}")
    return timeout


def require_bind_port(value: str, *, field: str) -> int:
    if isinstance(value, bool):
        raise ProofError(f"{field} is invalid: {value!r}")
    try:
        port = int(value)
    except (TypeError, ValueError) as error:
        raise ProofError(f"{field} is invalid: {value!r}") from error
    if not 0 <= port <= 65535:
        raise ProofError(f"{field} is out of range 0..65535: {port}")
    return port


def required_golden_string(
    document: Mapping[str, Any],
    field: str,
    *,
    what: str,
) -> str:
    value = document.get(field)
    if not isinstance(value, str) or value.strip() == "":
        raise ProofError(f"{what} golden is missing {field}")
    return value


def required_int(document: Mapping[str, Any], field: str) -> int:
    value = document.get(field)
    if type(value) is not int or isinstance(value, bool):
        raise ProofError(f"missing integer field: {field}")
    if value < 0:
        raise ProofError(f"{field}={value} is not a count")
    return value


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ProofError as error:
        print(str(error), file=sys.stderr)
        raise SystemExit(1) from error
