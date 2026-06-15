from __future__ import annotations

from types import SimpleNamespace

import pytest

from tirosh_vitalserver.devtools.adapters.host_proxy import local_proxy
from tirosh_vitalserver.devtools.application.inputs import HostProxyInput


def test_port_listeners_requires_lsof(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(local_proxy.shutil, "which", lambda _: None)

    with pytest.raises(local_proxy.PortListenerScanError, match="lsof is required"):
        local_proxy.port_listeners("8080")


def test_port_listeners_treats_empty_lsof_exit_one_as_no_listeners(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(local_proxy.shutil, "which", lambda _: "/usr/sbin/lsof")
    monkeypatch.setattr(
        local_proxy.subprocess,
        "run",
        lambda *_, **__: SimpleNamespace(returncode=1, stdout="", stderr=""),
    )

    assert local_proxy.port_listeners("8080") == []


def test_check_port_available_fails_on_unexpected_empty_lsof_exit(
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    monkeypatch.setattr(local_proxy.shutil, "which", lambda _: "/usr/sbin/lsof")
    monkeypatch.setattr(
        local_proxy.subprocess,
        "run",
        lambda *_, **__: SimpleNamespace(returncode=2, stdout="", stderr=""),
    )

    status = local_proxy.check_port_available(host_proxy_input())

    assert status == 1
    assert "failed to inspect proxy port 8080 listeners" in capsys.readouterr().out


def test_port_listeners_rejects_malformed_lsof_output(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(local_proxy.shutil, "which", lambda _: "/usr/sbin/lsof")
    monkeypatch.setattr(
        local_proxy.subprocess,
        "run",
        lambda *_, **__: SimpleNamespace(
            returncode=0,
            stdout="COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME\nmalformed\n",
            stderr="",
        ),
    )

    with pytest.raises(local_proxy.PortListenerScanError, match="malformed"):
        local_proxy.port_listeners("8080")


def test_port_listeners_wraps_lsof_execution_failure(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    def raise_os_error(*_: object, **__: object) -> object:
        raise OSError("permission denied")

    monkeypatch.setattr(local_proxy.shutil, "which", lambda _: "/usr/sbin/lsof")
    monkeypatch.setattr(local_proxy.subprocess, "run", raise_os_error)

    with pytest.raises(local_proxy.PortListenerScanError, match="permission denied"):
        local_proxy.port_listeners("8080")


def host_proxy_input() -> HostProxyInput:
    return HostProxyInput(
        runtime_dir="/tmp/vitalserver-runtime",
        proxy_config="/tmp/vitalserver-runtime/nginx.conf",
        port="8080",
        bind_host="127.0.0.1",
        http_port="8000",
        upstream="127.0.0.1:8000",
        trust_proxy="false",
        nginx_bin="/usr/local/bin/nginx",
        nginx_conf="/tmp/vitalserver-runtime/nginx.conf",
        nginx_prefix="/tmp/vitalserver-runtime",
    )
