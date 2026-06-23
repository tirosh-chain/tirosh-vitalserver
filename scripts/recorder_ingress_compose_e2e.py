#!/usr/bin/env python3
"""Run recorder-ingress send_data spool/replay checks against Docker Compose."""

from __future__ import annotations

import argparse
import json
import os
import shlex
import subprocess
import sys
import time
import urllib.error
import urllib.request
from dataclasses import dataclass


DEFAULT_PENDING_KEY = "vitalserver:recorder_ingress:send_data:pending"
DEFAULT_IN_FLIGHT_KEY = "vitalserver:recorder_ingress:send_data:in_flight"
DEFAULT_REPLAYED_KEY = "vitalserver:recorder_ingress:send_data:replayed"
DEFAULT_DEAD_LETTER_KEY = "vitalserver:recorder_ingress:send_data:dead_letter"


@dataclass(frozen=True)
class RedisKeys:
    pending: str
    in_flight: str
    replayed: str
    dead_letter: str


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    keys = RedisKeys(
        pending=args.pending_key,
        in_flight=args.in_flight_key,
        replayed=args.replayed_key,
        dead_letter=args.dead_letter_key,
    )
    env = compose_env(args)
    compose = shlex.split(args.compose)
    base_url = f"http://{args.bind_host}:{args.http_port}"

    if args.start_compose:
        run(
            compose
            + [
                "up",
                "-d",
                "--build",
                "--force-recreate",
                "recorder-ingress",
            ],
            env=env,
        )

    wait_for_status(base_url, args.mode, timeout_seconds=args.ready_timeout)
    app_state_before = (
        inspect_compose_container(args.docker, compose, args.app_service, env)
        if args.assert_app_stable
        else None
    )
    reset_redis_lists(compose, keys, env)
    baseline_status = read_status(base_url)

    expected_events = args.recorders * args.max_messages
    min_spooled_events = args.min_spooled_events
    if min_spooled_events is None:
        min_spooled_events = expected_events
    min_replayed_events = args.min_replayed_events
    if min_replayed_events is None:
        min_replayed_events = expected_events
    run_testkit_stream(args, base_url)
    status = wait_for_replay(
        base_url,
        baseline_status,
        min_replayed_events,
        timeout_seconds=args.replay_timeout,
    )

    redis_lengths = redis_list_lengths(compose, keys, env)
    replay = status["replay"]
    spool = status["spool"]
    observed_delta = counter_delta(status, baseline_status, ("sendDataEventsObserved",))
    spooled_delta = counter_delta(status, baseline_status, ("spool", "spooledEvents"))
    rejected_delta = counter_delta(status, baseline_status, ("spool", "rejectedEvents"))
    write_failure_delta = counter_delta(status, baseline_status, ("spool", "writeFailures"))
    replayed_delta = counter_delta(status, baseline_status, ("replay", "replayedEvents"))
    retryable_failure_delta = counter_delta(
        status,
        baseline_status,
        ("replay", "retryableFailures"),
    )
    dead_lettered_delta = counter_delta(
        status,
        baseline_status,
        ("replay", "deadLetteredEvents"),
    )
    assert_condition(spool["mode"] == args.mode, f"unexpected mode: {spool['mode']}")
    assert_condition(
        observed_delta >= expected_events,
        f"sendDataEventsObserved delta={observed_delta} expected>={expected_events}",
    )
    assert_condition(
        spooled_delta >= min_spooled_events,
        f"spooledEvents delta={spooled_delta} expected>={min_spooled_events}",
    )
    assert_condition(
        rejected_delta >= args.min_rejected_events,
        f"rejectedEvents delta={rejected_delta} expected>={args.min_rejected_events}",
    )
    assert_condition(
        write_failure_delta == 0,
        f"writeFailures delta={write_failure_delta}",
    )
    assert_condition(
        replayed_delta >= min_replayed_events,
        f"replayedEvents delta={replayed_delta} expected>={min_replayed_events}",
    )
    assert_condition(
        retryable_failure_delta <= args.max_retryable_failures,
        f"retryableFailures delta={retryable_failure_delta} expected<={args.max_retryable_failures}",
    )
    assert_condition(
        dead_lettered_delta == 0,
        f"deadLetteredEvents delta={dead_lettered_delta}",
    )
    assert_condition(spool["pendingItems"] == 0, f"spool.pendingItems={spool['pendingItems']}")
    assert_condition(spool["pendingBytes"] == 0, f"spool.pendingBytes={spool['pendingBytes']}")
    assert_condition(
        replay["pendingItems"] == 0,
        f"replay.pendingItems={replay['pendingItems']}",
    )
    assert_condition(
        replay["inFlightItems"] == 0,
        f"replay.inFlightItems={replay['inFlightItems']}",
    )
    assert_condition(
        redis_lengths["dead_letter"] == 0,
        f"dead_letter list length={redis_lengths['dead_letter']}",
    )
    assert_condition(
        redis_lengths["replayed"] >= min_replayed_events,
        f"replayed list length={redis_lengths['replayed']} expected>={min_replayed_events}",
    )
    if args.max_replay_lag_seconds is not None:
        assert_condition(
            replay["replayLagSeconds"] <= args.max_replay_lag_seconds,
            (
                f"replayLagSeconds={replay['replayLagSeconds']} "
                f"expected<={args.max_replay_lag_seconds}"
            ),
        )
    app_state_after = (
        inspect_compose_container(args.docker, compose, args.app_service, env)
        if args.assert_app_stable
        else None
    )
    if app_state_before and app_state_after:
        assert_app_stable(app_state_before, app_state_after, args.app_service)

    print(
        json.dumps(
            {
                "ok": True,
                "mode": args.mode,
                "expectedEvents": expected_events,
                "deltas": {
                    "sendDataEventsObserved": observed_delta,
                    "spooledEvents": spooled_delta,
                    "rejectedEvents": rejected_delta,
                    "writeFailures": write_failure_delta,
                    "replayedEvents": replayed_delta,
                    "retryableFailures": retryable_failure_delta,
                    "deadLetteredEvents": dead_lettered_delta,
                },
                "spool": spool,
                "replay": replay,
                "redis": redis_lengths,
                "app": {
                    "before": app_state_before,
                    "after": app_state_after,
                } if args.assert_app_stable else None,
            },
            ensure_ascii=False,
            sort_keys=True,
        )
    )
    return 0


def parse_args(argv: list[str] | None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Verify recorder-ingress send_data spool/replay in Docker Compose.",
    )
    parser.add_argument("--compose", default=os.environ.get("DOCKER_COMPOSE", "docker compose"))
    parser.add_argument("--docker", default=os.environ.get("DOCKER", "docker"))
    parser.add_argument("--bind-host", default=os.environ.get("VITALSERVER_BIND_HOST", "127.0.0.1"))
    parser.add_argument("--http-port", default=os.environ.get("VITALSERVER_HTTP_PORT", "18080"))
    parser.add_argument("--mode", default="spool_and_replay", choices=["spool_and_replay"])
    parser.add_argument("--recorders", type=int, default=2)
    parser.add_argument("--max-messages", type=int, default=3)
    parser.add_argument("--interval", type=float, default=0.1)
    parser.add_argument("--ready-timeout", type=float, default=90.0)
    parser.add_argument("--replay-timeout", type=float, default=30.0)
    parser.add_argument("--replay-interval-ms", default="250")
    parser.add_argument("--replay-batch-size")
    parser.add_argument("--replay-rate-limit-per-second", default="20")
    parser.add_argument("--max-pending-items")
    parser.add_argument("--max-pending-bytes")
    parser.add_argument("--max-payload-bytes")
    parser.add_argument("--min-spooled-events", type=int)
    parser.add_argument("--min-replayed-events", type=int)
    parser.add_argument("--min-rejected-events", type=int, default=0)
    parser.add_argument("--max-retryable-failures", type=int, default=0)
    parser.add_argument("--max-replay-lag-seconds", type=int)
    parser.add_argument("--assert-app-stable", action="store_true")
    parser.add_argument("--app-service", default="app")
    parser.add_argument("--testkit-command", default=default_testkit_command())
    parser.add_argument("--pending-key", default=DEFAULT_PENDING_KEY)
    parser.add_argument("--in-flight-key", default=DEFAULT_IN_FLIGHT_KEY)
    parser.add_argument("--replayed-key", default=DEFAULT_REPLAYED_KEY)
    parser.add_argument("--dead-letter-key", default=DEFAULT_DEAD_LETTER_KEY)
    parser.add_argument(
        "--no-start-compose",
        action="store_false",
        dest="start_compose",
        help="Use an already running Compose stack instead of recreating recorder-ingress.",
    )
    parser.set_defaults(start_compose=True)
    return parser.parse_args(argv)


def compose_env(args: argparse.Namespace) -> dict[str, str]:
    env = os.environ.copy()
    env["VITALSERVER_BIND_HOST"] = args.bind_host
    env["VITALSERVER_HTTP_PORT"] = str(args.http_port)
    env["RECORDER_INGRESS_SEND_DATA_MODE"] = args.mode
    env["RECORDER_INGRESS_SEND_DATA_REPLAY_ENABLED"] = "1"
    env["RECORDER_INGRESS_SEND_DATA_REPLAY_INTERVAL_MS"] = str(args.replay_interval_ms)
    if args.replay_batch_size is not None:
        env["RECORDER_INGRESS_SEND_DATA_REPLAY_BATCH_SIZE"] = str(args.replay_batch_size)
    env["RECORDER_INGRESS_SEND_DATA_REPLAY_RATE_LIMIT_PER_SECOND"] = str(
        args.replay_rate_limit_per_second
    )
    if args.max_pending_items is not None:
        env["RECORDER_INGRESS_SEND_DATA_MAX_PENDING_ITEMS"] = str(args.max_pending_items)
    if args.max_pending_bytes is not None:
        env["RECORDER_INGRESS_SEND_DATA_MAX_PENDING_BYTES"] = str(args.max_pending_bytes)
    if args.max_payload_bytes is not None:
        env["RECORDER_INGRESS_SEND_DATA_MAX_PAYLOAD_BYTES"] = str(args.max_payload_bytes)
    env["RECORDER_INGRESS_SEND_DATA_REDIS_LIST"] = args.pending_key
    env["RECORDER_INGRESS_SEND_DATA_IN_FLIGHT_REDIS_LIST"] = args.in_flight_key
    env["RECORDER_INGRESS_SEND_DATA_REPLAYED_REDIS_LIST"] = args.replayed_key
    env["RECORDER_INGRESS_SEND_DATA_DEAD_LETTER_REDIS_LIST"] = args.dead_letter_key
    return env


def default_testkit_command() -> str:
    configured = os.environ.get("TESTKIT_CLI")
    if configured:
        return configured
    if os.path.exists(".venv/bin/python"):
        return ".venv/bin/python -m tirosh_vitalserver.testkit.adapters.inbound.cli"
    return "python3 -m tirosh_vitalserver.testkit.adapters.inbound.cli"


def run_testkit_stream(args: argparse.Namespace, base_url: str) -> None:
    command = shlex.split(args.testkit_command) + [
        "stream-recorder",
        "--vitalserver-url",
        base_url,
        "--timeout",
        "60",
        "--recorders",
        str(args.recorders),
        "--interval",
        str(args.interval),
        "--max-messages",
        str(args.max_messages),
    ]
    for index in range(args.recorders):
        command.extend(["--bed-room-name", f"compose-e2e-bed-{index + 1}"])
    run(command, env=os.environ.copy())


def wait_for_status(base_url: str, mode: str, *, timeout_seconds: float) -> None:
    started = time.monotonic()
    last_error = ""
    while time.monotonic() - started < timeout_seconds:
        try:
            status = read_status(base_url)
            spool = status.get("spool") or {}
            replay = status.get("replay") or {}
            if spool.get("mode") == mode and replay.get("status") in {"idle", "replaying"}:
                return
            last_error = f"mode={spool.get('mode')} replay.status={replay.get('status')}"
        except Exception as exc:  # noqa: BLE001 - diagnostic boundary, not domain state.
            last_error = str(exc)
        time.sleep(1)
    raise RuntimeError(f"recorder-ingress status was not ready: {last_error}")


def wait_for_replay(
    base_url: str,
    baseline_status: dict[str, object],
    expected_events: int,
    *,
    timeout_seconds: float,
) -> dict[str, object]:
    started = time.monotonic()
    last_status: dict[str, object] = {}
    while time.monotonic() - started < timeout_seconds:
        status = read_status(base_url)
        spool = status["spool"]
        replay = status["replay"]
        last_status = replay
        if (
            counter_delta(status, baseline_status, ("replay", "replayedEvents")) >= expected_events
            and spool["pendingItems"] == 0
            and spool["pendingBytes"] == 0
            and replay["pendingItems"] == 0
            and replay["inFlightItems"] == 0
            and counter_delta(status, baseline_status, ("replay", "deadLetteredEvents")) == 0
        ):
            return status
        time.sleep(0.5)
    raise RuntimeError(f"send_data replay did not complete: {json.dumps(last_status)}")


def counter_delta(
    current: dict[str, object],
    baseline: dict[str, object],
    path: tuple[str, ...],
) -> int:
    return numeric_field(current, path) - numeric_field(baseline, path)


def numeric_field(document: dict[str, object], path: tuple[str, ...]) -> int:
    value: object = document
    for key in path:
        if not isinstance(value, dict):
            return 0
        value = value.get(key, 0)
    return int(value) if isinstance(value, (int, float)) else 0


def read_status(base_url: str) -> dict[str, object]:
    request = urllib.request.Request(f"{base_url}/recorder-ingress/status")
    try:
        with urllib.request.urlopen(request, timeout=5) as response:
            if response.status != 200:
                raise RuntimeError(f"status HTTP {response.status}")
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.URLError as exc:
        raise RuntimeError(f"status read failed: {exc}") from exc


def reset_redis_lists(compose: list[str], keys: RedisKeys, env: dict[str, str]) -> None:
    run(
        compose
        + [
            "exec",
            "-T",
            "redis",
            "redis-cli",
            "DEL",
            keys.pending,
            keys.in_flight,
            keys.replayed,
            keys.dead_letter,
        ],
        env=env,
    )


def redis_list_lengths(compose: list[str], keys: RedisKeys, env: dict[str, str]) -> dict[str, int]:
    return {
        "pending": redis_llen(compose, keys.pending, env),
        "in_flight": redis_llen(compose, keys.in_flight, env),
        "replayed": redis_llen(compose, keys.replayed, env),
        "dead_letter": redis_llen(compose, keys.dead_letter, env),
    }


def redis_llen(compose: list[str], key: str, env: dict[str, str]) -> int:
    result = run(
        compose + ["exec", "-T", "redis", "redis-cli", "LLEN", key],
        env=env,
        capture=True,
    )
    return int(result.stdout.strip())


def inspect_compose_container(
    docker: str,
    compose: list[str],
    service: str,
    env: dict[str, str],
) -> dict[str, object]:
    container_id = run(compose + ["ps", "-q", service], env=env, capture=True).stdout.strip()
    if not container_id:
        raise RuntimeError(f"compose service has no container: {service}")
    result = run([docker, "inspect", container_id], env=env, capture=True)
    documents = json.loads(result.stdout)
    if not documents:
        raise RuntimeError(f"docker inspect returned no document for service: {service}")
    document = documents[0]
    state = document.get("State") or {}
    return {
        "containerId": container_id,
        "oomKilled": bool(state.get("OOMKilled")),
        "restartCount": int(document.get("RestartCount") or 0),
        "status": state.get("Status") or "unknown",
        "exitCode": int(state.get("ExitCode") or 0),
    }


def assert_app_stable(
    before: dict[str, object],
    after: dict[str, object],
    service: str,
) -> None:
    assert_condition(
        after["oomKilled"] is False,
        f"{service} container oomKilled=true",
    )
    assert_condition(
        after["restartCount"] == before["restartCount"],
        (
            f"{service} restartCount changed "
            f"{before['restartCount']}->{after['restartCount']}"
        ),
    )
    assert_condition(
        after["status"] == "running",
        f"{service} container status={after['status']}",
    )


def run(
    command: list[str],
    *,
    env: dict[str, str],
    capture: bool = False,
) -> subprocess.CompletedProcess[str]:
    print("> " + " ".join(shlex.quote(part) for part in command), flush=True)
    try:
        return subprocess.run(
            command,
            check=True,
            env=env,
            text=True,
            capture_output=capture,
        )
    except FileNotFoundError as exc:
        executable = command[0] if command else "<empty>"
        raise RuntimeError(
            f"required command not found: {executable}. "
            "Set --compose or DOCKER_COMPOSE to the Docker Compose command available on this host."
        ) from exc


def assert_condition(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv[1:]))
    except (AssertionError, RuntimeError, subprocess.CalledProcessError) as exc:
        print(f"recorder-ingress compose e2e failed: {exc}", file=sys.stderr)
        raise SystemExit(1) from None
