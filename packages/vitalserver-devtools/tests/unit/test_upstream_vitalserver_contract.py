from __future__ import annotations

from tirosh_vitalserver.devtools.core.upstream_vitalserver_contract import (
    UpstreamVitalServerState,
    manifest_from_dict,
    verify_upstream_vitalserver_contract,
)

APP_JS = """
io.on("connection", function(socket) {
  socket.on("send_data", function(payload) {});
  socket.on("join_vr", function(vrcode) {
    client.set("ip_" + vrcode, socket.handshake.address);
  });
  socket.on("join_bed", function(bedid, vrcode) {
    client.get("ip_" + vrcode);
    socket.emit("recv_vr_ipaddr", bedid, "127.0.0.1");
  });
});
"""


def test_approved_upstream_contract_passes() -> None:
    result = verify_upstream_vitalserver_contract(
        manifest(),
        state(),
        "approved",
    )

    assert result.ok


def test_candidate_mode_allows_unapproved_compatible_commit() -> None:
    result = verify_upstream_vitalserver_contract(
        manifest(),
        state(commit="9999999999999999999999999999999999999999"),
        "candidate",
    )

    assert result.ok
    assert any("not in approvedCommits" in item.message for item in result.observations)


def test_candidate_remote_provenance_accepts_remote_commit() -> None:
    result = verify_upstream_vitalserver_contract(
        manifest(),
        state(
            commit="9999999999999999999999999999999999999999",
            remote_commit_present=True,
        ),
        "candidate",
        require_remote_commit=True,
    )

    assert result.ok
    assert any(item.stage == "remote-commit" for item in result.observations)


def test_candidate_remote_provenance_rejects_local_only_commit() -> None:
    result = verify_upstream_vitalserver_contract(
        manifest(),
        state(
            commit="9999999999999999999999999999999999999999",
            remote_commit_present=False,
        ),
        "candidate",
        require_remote_commit=True,
    )

    assert any(issue.stage == "remote-commit" for issue in result.issues)


def test_candidate_remote_provenance_reports_lookup_error() -> None:
    result = verify_upstream_vitalserver_contract(
        manifest(),
        state(
            commit="9999999999999999999999999999999999999999",
            remote_commit_error="network unavailable",
        ),
        "candidate",
        require_remote_commit=True,
    )

    assert result.issues[0].stage == "remote-commit"
    assert result.issues[0].actual == "network unavailable"


def test_approved_mode_rejects_unapproved_commit() -> None:
    result = verify_upstream_vitalserver_contract(
        manifest(),
        state(commit="9999999999999999999999999999999999999999"),
        "approved",
    )

    assert [issue.stage for issue in result.issues] == ["commit"]


def test_wrong_remote_fails_without_becoming_missing_state() -> None:
    result = verify_upstream_vitalserver_contract(
        manifest(),
        state(submodule_url="https://github.com/tirosh-chain/vitalserver.git"),
        "approved",
    )

    assert result.issues[0].stage == "remote"
    assert result.issues[0].actual == "https://github.com/tirosh-chain/vitalserver.git"


def test_dirty_submodule_fails() -> None:
    result = verify_upstream_vitalserver_contract(
        manifest(),
        state(dirty_status=" M vitalserver-old/service/app.js"),
        "approved",
    )

    assert any(issue.stage == "dirty-submodule" for issue in result.issues)


def test_required_file_missing_fails() -> None:
    current = state()
    current.files.pop("vitalserver-old/service/include/monitor.js")
    current.file_errors["vitalserver-old/service/include/monitor.js"] = "missing"

    result = verify_upstream_vitalserver_contract(
        manifest(),
        current,
        "approved",
    )

    assert any(issue.stage == "required-file" for issue in result.issues)


def test_required_contract_missing_fails() -> None:
    current = state(app_js='socket.on("join_vr", function() {});')

    result = verify_upstream_vitalserver_contract(
        manifest(),
        current,
        "approved",
    )

    assert any(
        issue.stage == "required-contract" and issue.rule_id == "redis.vrcode_ip.write"
        for issue in result.issues
    )


def test_forbidden_proxy_header_patch_marker_fails() -> None:
    current = state(app_js=APP_JS + '\nconst source = "x-forwarded-for";\n')

    result = verify_upstream_vitalserver_contract(
        manifest(),
        current,
        "approved",
    )

    assert any(
        issue.stage == "forbidden-marker"
        and issue.rule_id == "upstream.proxy_header_ip_patch"
        for issue in result.issues
    )


def test_git_read_failures_are_reported_explicitly() -> None:
    result = verify_upstream_vitalserver_contract(
        manifest(),
        state(commit=None, commit_error="fatal: not a git repository"),
        "approved",
    )

    assert result.issues[0].stage == "commit"
    assert result.issues[0].actual == "fatal: not a git repository"


def manifest():
    return manifest_from_dict(
        {
            "contractVersion": 1,
            "remote": "https://github.com/vitaldb/vitalserver.git",
            "submodulePath": "vendor/vitalserver",
            "approvedCommits": [
                {
                    "sha": "2059cc543467c1306482589dbcc77a575f79efe9",
                    "label": "initial upstream app snapshot",
                    "verifiedAt": "2026-06-15",
                    "notes": "Baseline",
                }
            ],
            "requiredFiles": [
                "vitalserver-old/service/app.js",
                "vitalserver-old/service/include/db.js",
                "vitalserver-old/service/include/monitor.js",
            ],
            "requiredContracts": [
                {
                    "id": "socketio.join_vr",
                    "file": "vitalserver-old/service/app.js",
                    "patterns": ["join_vr"],
                },
                {
                    "id": "socketio.send_data",
                    "file": "vitalserver-old/service/app.js",
                    "patterns": ["send_data"],
                },
                {
                    "id": "redis.vrcode_ip.write",
                    "file": "vitalserver-old/service/app.js",
                    "patterns": ["client.set", "ip_"],
                },
                {
                    "id": "redis.vrcode_ip.read_and_emit",
                    "file": "vitalserver-old/service/app.js",
                    "patterns": ["join_bed", "client.get", "recv_vr_ipaddr"],
                },
            ],
            "forbiddenMarkers": [
                {
                    "id": "upstream.proxy_header_ip_patch",
                    "file": "vitalserver-old/service/app.js",
                    "patterns": [
                        "x-forwarded-for",
                        "VITALSERVER_TRUST_PROXY",
                        "get_vr_client_ip",
                    ],
                }
            ],
        }
    )


def state(
    *,
    submodule_url: str | None = "https://github.com/vitaldb/vitalserver.git",
    submodule_url_error: str | None = None,
    commit: str | None = "2059cc543467c1306482589dbcc77a575f79efe9",
    commit_error: str | None = None,
    dirty_status: str | None = "",
    dirty_status_error: str | None = None,
    remote_commit_present: bool | None = None,
    remote_commit_error: str | None = None,
    app_js: str = APP_JS,
) -> UpstreamVitalServerState:
    return UpstreamVitalServerState(
        submodule_url=submodule_url,
        submodule_url_error=submodule_url_error,
        commit=commit,
        commit_error=commit_error,
        dirty_status=dirty_status,
        dirty_status_error=dirty_status_error,
        files={
            "vitalserver-old/service/app.js": app_js,
            "vitalserver-old/service/include/db.js": "module.exports = {};",
            "vitalserver-old/service/include/monitor.js": "module.exports = {};",
        },
        file_errors={},
        remote_commit_present=remote_commit_present,
        remote_commit_error=remote_commit_error,
    )
