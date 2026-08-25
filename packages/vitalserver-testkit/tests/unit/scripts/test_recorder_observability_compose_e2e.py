from __future__ import annotations

import copy
import json
import math
import re
from http.client import RemoteDisconnected
from pathlib import Path
from typing import Any

import pytest
from scripts import recorder_observability_compose_e2e as e2e

REPO = Path(__file__).resolve()
while REPO.parent != REPO and not (REPO / "make/testkit.mk").is_file():
    REPO = REPO.parent
TESTDATA = (
    REPO / "apps/vitalserver-recorder-ingress/contracts/recorder-observability/testdata"
)
MAKEFILE = REPO / "make/testkit.mk"
GUEST_COMPOSE = "apps/vitalserver-macos-runtime/Support/Guest/compose.yaml"
EXPECTED = e2e.ExpectedDetail(
    boot_id="boot-b",
    boot_state="started",
    ordering_state="ordered",
    evidence_health_state="healthy",
    incident_state="reported",
    report_state="missing",
)
QUERY_OWNER: e2e.QueryOwner = "recorder-ingress"


class FakeHttp:
    def __init__(self, responses: list[e2e.HttpResponse | BaseException]) -> None:
        self.responses = list(responses)
        self.calls: list[dict[str, Any]] = []

    def request(
        self,
        method: str,
        url: str,
        *,
        headers: dict[str, str] | None = None,
        body: bytes | None = None,
        timeout: float | None = None,
    ) -> e2e.HttpResponse:
        self.calls.append(
            {
                "method": method,
                "url": url,
                "headers": dict(headers or {}),
                "body": body,
                "timeout": timeout,
            }
        )
        if not self.responses:
            raise AssertionError(f"unexpected HTTP {method} {url}")
        item = self.responses.pop(0)
        if isinstance(item, BaseException):
            raise item
        return item


class FakeCommands:
    def __init__(self) -> None:
        self.calls: list[dict[str, Any]] = []

    def run(self, argv: list[str], *, env: dict[str, str]) -> None:
        self.calls.append({"argv": list(argv), "env": dict(env)})


def json_response(status_code: int, document: dict[str, Any]) -> e2e.HttpResponse:
    return e2e.HttpResponse(
        status_code=status_code,
        body=json.dumps(document).encode("utf-8"),
    )


def admitted(
    *, accepted: int, duplicates: int = 0, quarantined: int = 0
) -> dict[str, Any]:
    return {
        "state": "admitted",
        "requestId": "request-1",
        "accepted": accepted,
        "duplicates": duplicates,
        "quarantined": quarantined,
    }


def loaded_detail(vrcode: str) -> dict[str, Any]:
    return {
        "state": "loaded",
        "vrcode": vrcode,
        "support": {"state": "supported", "source": "accepted_report"},
        "report": {"state": "missing", "readIssueCount": 0},
        "boot": {"state": "started", "orderingState": "ordered", "bootId": "boot-b"},
        "evidenceHealth": {"state": "healthy"},
        "incidentState": {"state": "reported"},
        "readError": None,
    }


def loaded_timeline(vrcode: str) -> dict[str, Any]:
    return {
        "state": "loaded",
        "vrcode": vrcode,
        "supportState": "supported",
        "timeBasis": "receivedAt",
        "buckets": [{"bucketStartedAt": "2026-07-23T01:00:00.000Z", "sampleCount": 1}],
        "readError": None,
    }


def loaded_incidents(vrcode: str, incidents: list[Any] | None = None) -> dict[str, Any]:
    return {
        "state": "loaded",
        "vrcode": vrcode,
        "timeBasis": "receivedAt",
        "incidents": [] if incidents is None else incidents,
        "nextCursor": None,
        "readError": None,
    }


def advancing_clock() -> tuple[Any, Any]:
    clock = {"t": 0.0}

    def monotonic() -> float:
        return clock["t"]

    def sleep(seconds: float) -> None:
        clock["t"] += seconds

    return monotonic, sleep


def test_urllib_http_client_maps_remote_disconnected_to_unavailable(
    monkeypatch: Any,
) -> None:
    def raise_remote_disconnected(*_args: Any, **_kwargs: Any) -> Any:
        raise RemoteDisconnected("Remote end closed connection without response")

    monkeypatch.setattr(e2e, "urlopen", raise_remote_disconnected)
    client = e2e.UrllibHttpClient()

    with pytest.raises(e2e.TransportError, match="unavailable") as error:
        client.request(
            "GET",
            "http://127.0.0.1:18083/recorder-ingress/health",
            timeout=10.0,
        )

    assert error.value.kind == "unavailable"
    assert "closed connection without response" in str(error.value)


def test_urllib_http_client_keeps_timeout_distinct(monkeypatch: Any) -> None:
    def raise_timeout(*_args: Any, **_kwargs: Any) -> Any:
        raise TimeoutError("timed out")

    monkeypatch.setattr(e2e, "urlopen", raise_timeout)
    client = e2e.UrllibHttpClient()

    with pytest.raises(e2e.TransportError, match="timed out") as error:
        client.request(
            "GET",
            "http://127.0.0.1:18083/recorder-ingress/health",
            timeout=10.0,
        )

    assert error.value.kind == "timeout"


def test_wait_for_ingress_health_retries_unavailable_then_accepts_204() -> None:
    http = FakeHttp(
        [
            e2e.TransportError(
                "dependency unavailable: remote end closed connection without response",
                kind="unavailable",
            ),
            json_response(204, {}),
        ]
    )
    monotonic, sleep = advancing_clock()

    e2e.wait_for_ingress_health(
        http,
        "http://127.0.0.1:18083",
        timeout_seconds=90,
        interval_seconds=0.1,
        request_timeout=10.0,
        sleep=sleep,
        monotonic=monotonic,
    )

    assert [call["method"] for call in http.calls] == ["GET", "GET"]
    assert http.calls[0]["url"] == ("http://127.0.0.1:18083/recorder-ingress/health")


def test_wait_for_ingress_health_unavailable_exhaustion_is_failure() -> None:
    http = FakeHttp(
        [
            e2e.TransportError(
                "dependency unavailable: remote end closed connection without response",
                kind="unavailable",
            ),
            e2e.TransportError(
                "dependency unavailable: remote end closed connection without response",
                kind="unavailable",
            ),
        ]
    )
    monotonic, sleep = advancing_clock()

    with pytest.raises(e2e.ProofError, match="admission unavailable"):
        e2e.wait_for_ingress_health(
            http,
            "http://127.0.0.1:18083",
            timeout_seconds=0.1,
            interval_seconds=0.2,
            request_timeout=10.0,
            sleep=sleep,
            monotonic=monotonic,
        )

    assert len(http.calls) == 1


def test_certified_goldens_are_active_contract_v2() -> None:
    observation = e2e.load_certified_document(TESTDATA / "observation-v2-valid.json")
    boot = e2e.load_certified_document(TESTDATA / "boot-event-v2-valid.json")
    expected = e2e.expected_detail_from_goldens(observation, boot)

    assert observation["schemaVersion"] == "v2"
    assert observation["kind"] == "device-health"
    assert boot["schemaVersion"] == "v2"
    assert boot["kind"] == "boot-event"
    assert boot["eventType"] == "boot-started"
    assert observation["deviceId"] == boot["deviceId"]
    assert observation["bootId"] == boot["bootId"]
    assert expected == EXPECTED


def test_expected_detail_rejects_unbound_certified_pair() -> None:
    observation = e2e.load_certified_document(TESTDATA / "observation-v2-valid.json")
    boot = e2e.load_certified_document(TESTDATA / "boot-event-v2-valid.json")

    wrong_schema = copy.deepcopy(observation)
    wrong_schema["schemaVersion"] = "v1"
    with pytest.raises(e2e.ProofError, match="observation golden schemaVersion"):
        e2e.expected_detail_from_goldens(wrong_schema, boot)

    wrong_kind = copy.deepcopy(observation)
    wrong_kind["kind"] = "boot-event"
    with pytest.raises(e2e.ProofError, match="observation golden kind"):
        e2e.expected_detail_from_goldens(wrong_kind, boot)

    wrong_boot_schema = copy.deepcopy(boot)
    wrong_boot_schema["schemaVersion"] = "v1"
    with pytest.raises(e2e.ProofError, match="boot-event golden schemaVersion"):
        e2e.expected_detail_from_goldens(observation, wrong_boot_schema)

    wrong_boot_kind = copy.deepcopy(boot)
    wrong_boot_kind["kind"] = "device-health"
    with pytest.raises(e2e.ProofError, match="boot-event golden kind"):
        e2e.expected_detail_from_goldens(observation, wrong_boot_kind)

    other_device = copy.deepcopy(boot)
    other_device["deviceId"] = "vr-other"
    with pytest.raises(e2e.ProofError, match="distinct deviceId values"):
        e2e.required_device_id(observation, other_device)

    wrong_event = copy.deepcopy(boot)
    wrong_event["eventType"] = "shutdown-clean"
    with pytest.raises(e2e.ProofError, match="boot-event golden eventType"):
        e2e.expected_detail_from_goldens(observation, wrong_event)

    mismatched = copy.deepcopy(observation)
    mismatched["bootId"] = "boot-a"
    with pytest.raises(e2e.ProofError, match="distinct bootId values"):
        e2e.expected_detail_from_goldens(mismatched, boot)

    missing = copy.deepcopy(observation)
    missing["bootId"] = ""
    with pytest.raises(e2e.ProofError, match="observation golden is missing bootId"):
        e2e.expected_detail_from_goldens(missing, boot)


def test_allocate_proof_vrcode_is_unique_and_contract_safe() -> None:
    vrcode = e2e.allocate_proof_vrcode(
        now="2026-08-24T13:00:00+00:00",
        suffix="a1b2c3d4",
    )

    assert vrcode == "PROOF-20260824T130000Z-a1b2c3d4"
    assert e2e.VRCODE_PATTERN.fullmatch(vrcode)


def test_missing_or_invalid_golden_is_not_empty_success(tmp_path: Path) -> None:
    missing = tmp_path / "missing.json"
    invalid = tmp_path / "invalid.json"
    invalid.write_text("{", encoding="utf-8")

    with pytest.raises(e2e.ProofError, match="certified golden is missing"):
        e2e.load_certified_document(missing)
    with pytest.raises(e2e.ProofError, match="certified golden is invalid JSON"):
        e2e.load_certified_document(invalid)


def test_admitted_receipt_requires_explicit_counts_not_http_status_alone() -> None:
    e2e.assert_admitted_not_quarantined(
        json_response(202, admitted(accepted=1)),
        resource="observation",
        expected_accepted=1,
        expected_duplicates=0,
    )
    e2e.assert_admitted_not_quarantined(
        json_response(202, admitted(accepted=0, duplicates=1)),
        resource="observation",
        expected_accepted=0,
        expected_duplicates=1,
    )

    with pytest.raises(e2e.ProofError, match="line receipt quarantined=1"):
        e2e.assert_admitted_not_quarantined(
            json_response(202, admitted(accepted=1, quarantined=1)),
            resource="observation",
        )
    with pytest.raises(e2e.ProofError, match="missing integer field: quarantined"):
        e2e.assert_admitted_not_quarantined(
            json_response(
                202,
                {
                    "state": "admitted",
                    "requestId": "request-1",
                    "accepted": 1,
                    "duplicates": 0,
                },
            ),
            resource="observation",
        )
    with pytest.raises(e2e.ProofError, match="HTTP 202 is not an admission receipt"):
        e2e.assert_admitted_not_quarantined(
            json_response(202, {"ok": True}),
            resource="observation",
        )


def test_admission_4xx_and_503_stay_distinct() -> None:
    with pytest.raises(e2e.ProofError, match="request rejected status=400"):
        e2e.assert_admitted_not_quarantined(
            json_response(
                400, {"state": "rejected", "reason": "ndjson_framing_invalid"}
            ),
            resource="observation",
        )
    with pytest.raises(e2e.ProofError, match="admission unavailable status=503"):
        e2e.assert_admitted_not_quarantined(
            json_response(
                503,
                {"state": "failed", "reason": "durable_admission_failed"},
            ),
            resource="observation",
        )


def test_detail_states_stay_distinct() -> None:
    e2e.assert_detail_loaded(
        loaded_detail("PROOF-A"),
        "PROOF-A",
        query_owner=QUERY_OWNER,
        expected=EXPECTED,
    )

    with pytest.raises(
        e2e.ProjectionPendingError, match="projection not loaded: notReported"
    ) as pending:
        e2e.assert_detail_loaded(
            {"state": "notReported", "vrcode": "PROOF-A"},
            "PROOF-A",
            query_owner=QUERY_OWNER,
            expected=EXPECTED,
        )
    assert pending.value.state == "notReported"
    with pytest.raises(e2e.ProofError, match="recorder-ingress query unavailable"):
        e2e.assert_detail_loaded(
            {"state": "unavailable", "vrcode": "PROOF-A", "readError": "down"},
            "PROOF-A",
            query_owner=QUERY_OWNER,
            expected=EXPECTED,
        )
    with pytest.raises(e2e.ProofError, match="HTTP 200 is not a loaded projection"):
        e2e.assert_detail_loaded(
            {"vrcode": "PROOF-A"},
            "PROOF-A",
            query_owner=QUERY_OWNER,
            expected=EXPECTED,
        )


def test_detail_requires_missing_report_and_golden_boot_identity() -> None:
    current = loaded_detail("PROOF-A")
    current["report"]["state"] = "current"
    with pytest.raises(
        e2e.ProofError,
        match=re.escape("report.state='current' expected='missing'"),
    ):
        e2e.assert_detail_loaded(
            current,
            "PROOF-A",
            query_owner=QUERY_OWNER,
            expected=EXPECTED,
        )

    wrong_boot = loaded_detail("PROOF-A")
    wrong_boot["boot"]["bootId"] = "boot-a"
    with pytest.raises(
        e2e.ProofError,
        match=re.escape("boot.bootId='boot-a' expected='boot-b'"),
    ):
        e2e.assert_detail_loaded(
            wrong_boot,
            "PROOF-A",
            query_owner=QUERY_OWNER,
            expected=EXPECTED,
        )


def test_timeline_and_incident_states_stay_distinct() -> None:
    e2e.assert_timeline_loaded(
        loaded_timeline("PROOF-A"), "PROOF-A", query_owner=QUERY_OWNER
    )
    e2e.assert_incidents_loaded(
        loaded_incidents("PROOF-A"), "PROOF-A", query_owner=QUERY_OWNER
    )

    with pytest.raises(e2e.ProofError, match="timeline state=notReported"):
        e2e.assert_timeline_loaded(
            {
                "state": "notReported",
                "vrcode": "PROOF-A",
                "supportState": "unknown",
                "timeBasis": "receivedAt",
                "buckets": [],
                "readError": None,
            },
            "PROOF-A",
            query_owner=QUERY_OWNER,
        )
    with pytest.raises(e2e.ProofError, match="timeline state=unsupported"):
        e2e.assert_timeline_loaded(
            {
                "state": "unsupported",
                "vrcode": "PROOF-A",
                "supportState": "unsupported",
                "timeBasis": "receivedAt",
                "buckets": [],
                "readError": None,
            },
            "PROOF-A",
            query_owner=QUERY_OWNER,
        )
    with pytest.raises(e2e.ProofError, match="empty incidents remain loaded"):
        e2e.assert_incidents_loaded(
            {
                "state": "notReported",
                "vrcode": "PROOF-A",
                "timeBasis": "receivedAt",
                "incidents": [],
                "readError": None,
            },
            "PROOF-A",
            query_owner=QUERY_OWNER,
        )
    with pytest.raises(e2e.ProofError, match="missing incidents list"):
        e2e.assert_incidents_loaded(
            {
                "state": "loaded",
                "vrcode": "PROOF-A",
                "timeBasis": "receivedAt",
                "readError": None,
            },
            "PROOF-A",
            query_owner=QUERY_OWNER,
        )


def test_parse_args_defaults_to_recorder_ingress_query_owner() -> None:
    args = e2e.parse_args([])

    assert args.compose_file == GUEST_COMPOSE
    assert args.http_port == "18083"
    assert args.bind_host == "127.0.0.1"
    assert args.ingress_base_url == "http://127.0.0.1:18083"
    assert args.query_owner == "recorder-ingress"
    assert args.query_base_url == "http://127.0.0.1:18083"
    assert args.request_timeout == 10.0
    assert args.start_compose is False
    assert args.compose_file.endswith("Guest/compose.yaml")
    assert args.http_port != "18080"
    assert not hasattr(args, "guest_control_base_url")
    assert args.postgres_host_port == 0


def test_postgres_host_port_validation_fails_before_mutation() -> None:
    http = FakeHttp([])
    commands = FakeCommands()
    for value in ("-1", "65536", "notaport", "1.5", ""):
        with pytest.raises(e2e.ProofError, match="postgres-host-port"):
            e2e.main(
                [
                    "--postgres-host-port",
                    value,
                    "--start-compose",
                    "--vrcode",
                    "PROOF-TEST-1",
                    "--testdata",
                    str(TESTDATA),
                ],
                http=http,
                commands=commands,
                sleep=lambda _seconds: None,
            )
        assert http.calls == []
        assert commands.calls == []
    for value in ("0", "15432", "65535"):
        args = e2e.parse_args(["--postgres-host-port", value])
        assert args.postgres_host_port == int(value)


def test_guest_control_query_owner_requires_explicit_base_url() -> None:
    with pytest.raises(e2e.ProofError, match="query-owner=guest-control requires"):
        e2e.parse_args(["--query-owner", "guest-control"])

    args = e2e.parse_args(
        [
            "--query-owner",
            "guest-control",
            "--query-base-url",
            "http://127.0.0.1:18330",
        ]
    )
    assert args.query_owner == "guest-control"
    assert args.query_base_url == "http://127.0.0.1:18330"


def test_make_target_is_dedicated_guest_compose_postgres_proof() -> None:
    text = MAKEFILE.read_text(encoding="utf-8")

    assert "testkit/recorder-observability/compose-proof:" in text
    assert "scripts/recorder_observability_compose_e2e.py" in text
    assert GUEST_COMPOSE in text
    assert "18083" in text
    assert "Mutates dedicated Guest compose PostgreSQL" in text
    recipe = "\n".join(
        line
        for line in text.split("testkit/recorder-observability/compose-proof:")[
            1
        ].splitlines()
        if line.startswith("\t")
    )
    assert "field_proof_preflight" not in recipe
    assert "VITALSERVER_HTTP_PORT" not in recipe
    assert "--start-compose" in recipe
    assert "--query-owner recorder-ingress" in recipe
    assert "--postgres-host-port 0" in recipe
    assert "--guest-control-base-url" not in recipe


def test_main_proves_admission_and_recorder_ingress_query(
    capsys: pytest.CaptureFixture[str],
) -> None:
    vrcode = "PROOF-TEST-1"
    http = FakeHttp(
        [
            json_response(202, admitted(accepted=1)),
            json_response(202, admitted(accepted=1)),
            json_response(202, admitted(accepted=0, duplicates=1)),
            json_response(404, {"state": "not_found", "vrcode": vrcode}),
            json_response(200, loaded_detail(vrcode)),
            json_response(200, loaded_timeline(vrcode)),
            json_response(200, loaded_incidents(vrcode)),
        ]
    )
    commands = FakeCommands()

    exit_code = e2e.main(
        [
            "--vrcode",
            vrcode,
            "--testdata",
            str(TESTDATA),
            "--projection-timeout",
            "1",
        ],
        http=http,
        commands=commands,
        sleep=lambda _seconds: None,
    )
    output = json.loads(capsys.readouterr().out)

    assert exit_code == 0
    assert commands.calls == []
    assert output["ok"] is True
    assert output["vrcode"] == vrcode
    assert output["queryOwner"] == "recorder-ingress"
    assert output["queryBaseUrl"] == "http://127.0.0.1:18083"
    assert output["proofScope"] == "guest-compose-recorder-observability"
    assert output["profilePosted"] is False
    assert output["admissions"]["observation"]["accepted"] == 1
    assert output["admissions"]["observationDuplicate"]["duplicates"] == 1
    assert output["admissions"]["bootEvent"]["quarantined"] == 0
    assert output["detail"]["state"] == "loaded"
    assert output["detail"]["boot"]["state"] == "started"
    assert output["detail"]["boot"]["orderingState"] == "ordered"
    assert output["detail"]["boot"]["bootId"] == "boot-b"
    assert output["detail"]["report"]["state"] == "missing"
    assert output["detail"]["evidenceHealth"]["state"] == "healthy"
    assert output["detail"]["incidentState"]["state"] == "reported"
    assert output["timeline"]["state"] == "loaded"
    assert output["timeline"]["timeBasis"] == "receivedAt"
    assert output["incidents"]["state"] == "loaded"
    assert output["incidents"]["empty"] is True
    assert [call["method"] for call in http.calls] == [
        "POST",
        "POST",
        "POST",
        "GET",
        "GET",
        "GET",
        "GET",
    ]
    assert http.calls[0]["url"].endswith(f"/api/v1/recorders/{vrcode}/observations")
    assert http.calls[0]["headers"]["content-type"] == "application/x-ndjson"
    assert http.calls[0]["headers"]["x-device-id"] == "vr-brmh-15"
    assert http.calls[1]["url"].endswith(f"/api/v1/recorders/{vrcode}/boot-events")
    assert "/runtime/vitaldb/recorders/" in http.calls[4]["url"]
    assert http.calls[4]["url"].endswith("/observability")
    assert "observability/timeline" in http.calls[5]["url"]
    assert "observability/incidents" in http.calls[6]["url"]
    assert [call["timeout"] for call in http.calls] == [10.0] * 7


def test_main_fails_on_transport_unavailable_without_inferring_success() -> None:
    http = FakeHttp(
        [
            e2e.TransportError(
                "recorder-ingress is unavailable: connection refused",
                kind="unavailable",
            )
        ]
    )

    with pytest.raises(e2e.ProofError, match="unavailable"):
        e2e.main(
            ["--vrcode", "PROOF-TEST-1", "--testdata", str(TESTDATA)],
            http=http,
            commands=FakeCommands(),
            sleep=lambda _seconds: None,
        )


def test_start_compose_uses_guest_compose_command_seam() -> None:
    vrcode = "PROOF-TEST-1"
    http = FakeHttp(
        [
            json_response(204, {}),
            json_response(202, admitted(accepted=1)),
            json_response(202, admitted(accepted=1)),
            json_response(202, admitted(accepted=0, duplicates=1)),
            json_response(200, loaded_detail(vrcode)),
            json_response(200, loaded_timeline(vrcode)),
            json_response(200, loaded_incidents(vrcode)),
        ]
    )
    commands = FakeCommands()

    e2e.main(
        [
            "--vrcode",
            vrcode,
            "--testdata",
            str(TESTDATA),
            "--start-compose",
            "--compose-file",
            GUEST_COMPOSE,
            "--compose-project",
            "vitalserver-recorder-observability-proof",
        ],
        http=http,
        commands=commands,
        sleep=lambda _seconds: None,
    )

    assert commands.calls, "start-compose must invoke the command seam"
    argv = commands.calls[0]["argv"]
    assert commands.calls[0]["env"]["VITALSERVER_POSTGRES_BIND_PORT"] == "0"
    assert argv[argv.index("--file") + 1] == GUEST_COMPOSE
    assert argv.count("--file") == 1
    assert "vitalserver-recorder-observability-proof" in argv
    assert argv[-6:] == [
        "postgres",
        "postgres-migrate",
        "redis",
        "app",
        "recorder-recovery",
        "recorder-ingress",
    ]
    joined = " ".join(argv)
    assert "Support/Guest/compose.yaml" in joined
    assert " --file compose.yaml" not in f" {joined} "


def test_wait_retries_only_typed_projection_pending() -> None:
    vrcode = "PROOF-A"
    http = FakeHttp(
        [
            json_response(404, {"state": "not_found", "vrcode": vrcode}),
            json_response(200, loaded_detail(vrcode)),
        ]
    )
    monotonic, sleep = advancing_clock()

    document = e2e.wait_for_projection_loaded(
        http,
        "http://127.0.0.1:18083",
        vrcode,
        query_owner=QUERY_OWNER,
        expected=EXPECTED,
        timeout_seconds=1,
        interval_seconds=0.1,
        request_timeout=10.0,
        sleep=sleep,
        monotonic=monotonic,
    )

    assert document["state"] == "loaded"
    assert [call["method"] for call in http.calls] == ["GET", "GET"]


def test_wait_does_not_retry_unavailable_or_invalid_json() -> None:
    unavailable = FakeHttp(
        [
            json_response(
                503,
                {
                    "state": "failed",
                    "reason": "recorder_observability_query_failed",
                },
            ),
            json_response(200, loaded_detail("PROOF-A")),
        ]
    )
    invalid = FakeHttp(
        [
            e2e.HttpResponse(200, b"{"),
            json_response(200, loaded_detail("PROOF-A")),
        ]
    )
    monotonic, sleep = advancing_clock()

    with pytest.raises(e2e.ProofError, match="recorder-ingress query unavailable"):
        e2e.wait_for_projection_loaded(
            unavailable,
            "http://127.0.0.1:18083",
            "PROOF-A",
            query_owner=QUERY_OWNER,
            expected=EXPECTED,
            timeout_seconds=1,
            interval_seconds=0.1,
            request_timeout=10.0,
            sleep=sleep,
            monotonic=monotonic,
        )
    assert len(unavailable.calls) == 1

    monotonic, sleep = advancing_clock()
    with pytest.raises(e2e.ProofError, match="invalid JSON"):
        e2e.wait_for_projection_loaded(
            invalid,
            "http://127.0.0.1:18083",
            "PROOF-A",
            query_owner=QUERY_OWNER,
            expected=EXPECTED,
            timeout_seconds=1,
            interval_seconds=0.1,
            request_timeout=10.0,
            sleep=sleep,
            monotonic=monotonic,
        )
    assert len(invalid.calls) == 1


def test_projection_timeout_keeps_notReported_distinct_from_loaded() -> None:
    vrcode = "PROOF-TEST-1"
    http = FakeHttp(
        [
            json_response(202, admitted(accepted=1)),
            json_response(202, admitted(accepted=1)),
            json_response(202, admitted(accepted=0, duplicates=1)),
            json_response(200, {"state": "notReported", "vrcode": vrcode}),
            json_response(200, {"state": "notReported", "vrcode": vrcode}),
        ]
    )
    monotonic, sleep = advancing_clock()

    with pytest.raises(
        e2e.ProjectionPendingError, match="projection not loaded: notReported"
    ):
        e2e.main(
            [
                "--vrcode",
                vrcode,
                "--testdata",
                str(TESTDATA),
                "--projection-timeout",
                "0.5",
                "--projection-interval",
                "0.4",
            ],
            http=http,
            commands=FakeCommands(),
            sleep=sleep,
            monotonic=monotonic,
        )


def test_wait_fails_immediately_on_loaded_nested_notReported() -> None:
    vrcode = "PROOF-A"
    nested = loaded_detail(vrcode)
    nested["boot"]["state"] = "notReported"
    http = FakeHttp(
        [
            json_response(200, nested),
            json_response(200, loaded_detail(vrcode)),
        ]
    )
    monotonic, sleep = advancing_clock()

    with pytest.raises(
        e2e.ProofError,
        match=re.escape("boot.state='notReported' expected='started'"),
    ) as raised:
        e2e.wait_for_projection_loaded(
            http,
            "http://127.0.0.1:18083",
            vrcode,
            query_owner=QUERY_OWNER,
            expected=EXPECTED,
            timeout_seconds=1,
            interval_seconds=0.1,
            request_timeout=10.0,
            sleep=sleep,
            monotonic=monotonic,
        )
    assert len(http.calls) == 1
    assert not isinstance(raised.value, e2e.ProjectionPendingError)


def test_loaded_nested_notReported_is_not_projection_pending() -> None:
    for path, expected_field in (
        (("boot", "state"), "boot.state"),
        (("evidenceHealth", "state"), "evidenceHealth.state"),
        (("incidentState", "state"), "incidentState.state"),
    ):
        document = loaded_detail("PROOF-A")
        cursor: dict[str, Any] = document
        for key in path[:-1]:
            nested = cursor[key]
            assert isinstance(nested, dict)
            cursor = nested
        cursor[path[-1]] = "notReported"
        with pytest.raises(e2e.ProofError, match=expected_field) as raised:
            e2e.assert_detail_loaded(
                document,
                "PROOF-A",
                query_owner=QUERY_OWNER,
                expected=EXPECTED,
            )
        assert not isinstance(raised.value, e2e.ProjectionPendingError)


def test_http_calls_use_explicit_request_timeout() -> None:
    vrcode = "PROOF-TEST-1"
    http = FakeHttp(
        [
            json_response(202, admitted(accepted=1)),
            json_response(202, admitted(accepted=1)),
            json_response(202, admitted(accepted=0, duplicates=1)),
            json_response(200, loaded_detail(vrcode)),
            json_response(200, loaded_timeline(vrcode)),
            json_response(200, loaded_incidents(vrcode)),
        ]
    )

    e2e.main(
        [
            "--vrcode",
            vrcode,
            "--testdata",
            str(TESTDATA),
            "--request-timeout",
            "7.5",
        ],
        http=http,
        commands=FakeCommands(),
        sleep=lambda _seconds: None,
    )

    assert [call["timeout"] for call in http.calls] == [7.5] * 6


def test_invalid_request_timeout_fails_before_mutation() -> None:
    http = FakeHttp([])
    commands = FakeCommands()
    for value in ("0", "-1", "nan", "inf"):
        with pytest.raises(e2e.ProofError, match="request-timeout is invalid"):
            e2e.main(
                [
                    "--request-timeout",
                    value,
                    "--start-compose",
                    "--vrcode",
                    "PROOF-TEST-1",
                    "--testdata",
                    str(TESTDATA),
                ],
                http=http,
                commands=commands,
                sleep=lambda _seconds: None,
            )
        assert http.calls == []
        assert commands.calls == []
    with pytest.raises(e2e.ProofError, match="request-timeout is invalid"):
        e2e.parse_args(["--request-timeout", str(math.nan)])
