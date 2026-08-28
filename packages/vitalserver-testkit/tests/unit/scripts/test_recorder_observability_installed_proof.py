from __future__ import annotations

import json
from pathlib import Path
from typing import Any

import pytest
from scripts import recorder_observability_compose_e2e as e2e
from scripts import recorder_observability_installed_proof as installed

REPO = Path(__file__).resolve()
while REPO.parent != REPO and not (REPO / "make/testkit.mk").is_file():
    REPO = REPO.parent
TESTDATA = (
    REPO / "apps/vitalserver-recorder-ingress/contracts/recorder-observability/testdata"
)
MAKEFILE = REPO / "make/testkit.mk"
INSTALLED_PROOF_TARGET = "testkit/recorder-observability/installed-proof"
ADMISSION_URL = "http://127.0.0.1"
GUEST_CONTROL_URL = "http://127.0.0.1:18330"


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


def loaded_incidents(vrcode: str) -> dict[str, Any]:
    return {
        "state": "loaded",
        "vrcode": vrcode,
        "timeBasis": "receivedAt",
        "incidents": [],
        "nextCursor": None,
        "readError": None,
    }


def recipe_for(text: str, target: str) -> str:
    after = text.split(f"{target}:")[1]
    lines: list[str] = []
    for line in after.splitlines():
        if line.startswith("\t"):
            lines.append(line)
        elif lines:
            break
    return "\n".join(lines)


def proof_argv(*, confirmation: str = "YES") -> list[str]:
    return [
        "--admission-base-url",
        ADMISSION_URL,
        "--guest-control-base-url",
        GUEST_CONTROL_URL,
        "--confirmation",
        confirmation,
    ]


def test_make_installed_proof_target_requires_explicit_named_inputs() -> None:
    text = MAKEFILE.read_text(encoding="utf-8")
    assert f"{INSTALLED_PROOF_TARGET}:" in text
    assert (
        "testkit/recorder-observability/compose-proof "
        "testkit/recorder-observability/installed-proof"
    ) in text
    recipe = recipe_for(text, INSTALLED_PROOF_TARGET)
    assert "-m scripts.recorder_observability_installed_proof" in recipe
    assert '--admission-base-url "$(RECORDER_ADMISSION_BASE_URL)"' in recipe
    assert '--guest-control-base-url "$(RECORDER_GUEST_CONTROL_BASE_URL)"' in recipe
    assert '--confirmation "$(RECORDER_PROOF_CONFIRMATION)"' in recipe
    assert "--start-compose" not in recipe
    assert "--query-owner recorder-ingress" not in recipe
    assert "http://" not in recipe
    assert "18083" not in recipe
    assert "field_proof_preflight" not in recipe
    for variable in (
        "RECORDER_ADMISSION_BASE_URL",
        "RECORDER_GUEST_CONTROL_BASE_URL",
        "RECORDER_PROOF_CONFIRMATION",
    ):
        assert f"{variable} ?=" not in text


def test_confirmation_missing_or_blank_blocks_network_before_post() -> None:
    http = FakeHttp([])
    commands = FakeCommands()
    base = [
        "--admission-base-url",
        ADMISSION_URL,
        "--guest-control-base-url",
        GUEST_CONTROL_URL,
    ]
    for confirmation in ([], ["--confirmation", ""], ["--confirmation", "   "]):
        with pytest.raises(
            installed.InstalledProofError, match="confirmation is missing"
        ):
            installed.main(
                base + confirmation,
                http=http,
                commands=commands,
            )
        assert http.calls == []
        assert commands.calls == []


def test_invalid_nonempty_confirmation_is_distinct_and_blocks_network() -> None:
    http = FakeHttp([])
    commands = FakeCommands()
    for confirmation in ("yes", "Yes", "y", "NO", "1", " YES ", "true"):
        with pytest.raises(
            installed.InstalledProofError, match="confirmation is invalid"
        ) as raised:
            installed.main(
                proof_argv(confirmation=confirmation),
                http=http,
                commands=commands,
            )
        assert "YES" in str(raised.value)
        assert confirmation not in str(raised.value)
        assert http.calls == []
        assert commands.calls == []


def test_confirmation_status_is_exact_yes_only() -> None:
    assert installed.confirmation_status("YES") == installed.CONFIRMATION_CONFIRMED
    for value in (None, "", "   "):
        assert installed.confirmation_status(value) == installed.CONFIRMATION_MISSING
    for value in ("yes", "Yes", "y", "YES ", " YES", "1", "true"):
        assert installed.confirmation_status(value) == installed.CONFIRMATION_INVALID


def test_missing_base_url_is_distinct_and_blocks_network() -> None:
    http = FakeHttp([])
    commands = FakeCommands()
    for argv in (
        ["--guest-control-base-url", GUEST_CONTROL_URL],
        ["--admission-base-url", ADMISSION_URL],
        ["--admission-base-url", "", "--guest-control-base-url", GUEST_CONTROL_URL],
        ["--admission-base-url", "  ", "--guest-control-base-url", GUEST_CONTROL_URL],
    ):
        with pytest.raises(installed.InstalledProofError, match="base URL is missing"):
            installed.main(
                [*argv, "--confirmation", "YES"],
                http=http,
                commands=commands,
            )
        assert http.calls == []
        assert commands.calls == []


def test_invalid_base_url_shape_blocks_network() -> None:
    http = FakeHttp([])
    commands = FakeCommands()
    for value in ("127.0.0.1:18330", "ftp://guest", "//host/path", "http://"):
        with pytest.raises(installed.InstalledProofError, match="base URL is invalid"):
            installed.main(
                [
                    "--admission-base-url",
                    value,
                    "--guest-control-base-url",
                    GUEST_CONTROL_URL,
                    "--confirmation",
                    "YES",
                ],
                http=http,
                commands=commands,
            )
        assert http.calls == []
        assert commands.calls == []


def test_invalid_request_timeout_blocks_network_before_post() -> None:
    http = FakeHttp([])
    commands = FakeCommands()
    with pytest.raises(e2e.ProofError, match="request-timeout is invalid"):
        installed.main(
            [*proof_argv(), "--request-timeout", "0"],
            http=http,
            commands=commands,
        )
    assert http.calls == []
    assert commands.calls == []


def test_installed_proof_admits_and_queries_guest_control_only_after_confirmation(
    capsys: pytest.CaptureFixture[str],
) -> None:
    vrcode = "PROOF-INSTALLED-1"
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

    exit_code = installed.main(
        [
            *proof_argv(),
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
    assert output["proofScope"] == "guest-control-recorder-observability"
    assert output["queryOwner"] == "guest-control"
    assert output["queryBaseUrl"] == GUEST_CONTROL_URL
    assert output["vrcode"] == vrcode
    assert output["profilePosted"] is False
    assert output["admissions"]["observation"]["accepted"] == 1
    assert output["admissions"]["observationDuplicate"]["duplicates"] == 1
    assert output["admissions"]["bootEvent"]["accepted"] == 1
    assert output["detail"]["state"] == "loaded"
    assert output["detail"]["boot"]["bootId"] == "boot-b"
    assert output["detail"]["report"]["state"] == "missing"
    assert output["timeline"]["state"] == "loaded"
    assert output["incidents"]["state"] == "loaded"
    methods = [call["method"] for call in http.calls]
    assert methods == ["POST", "POST", "POST", "GET", "GET", "GET", "GET"]
    assert http.calls[0]["url"].startswith(f"{ADMISSION_URL}/api/v1/recorders/")
    assert http.calls[0]["headers"]["content-type"] == "application/x-ndjson"
    assert http.calls[0]["headers"]["x-device-id"] == "vr-brmh-15"
    assert http.calls[4]["url"].startswith(
        f"{GUEST_CONTROL_URL}/runtime/vitaldb/recorders/"
    )
    assert [call["timeout"] for call in http.calls] == [10.0] * 7


def test_installed_proof_forwards_request_timeout_to_proof_http() -> None:
    vrcode = "PROOF-INSTALLED-2"
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

    installed.main(
        [
            *proof_argv(),
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
