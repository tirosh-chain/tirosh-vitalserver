from __future__ import annotations

import hashlib
import importlib.util
import io
import json
import struct
import subprocess
import sys
import tarfile
from pathlib import Path
from types import SimpleNamespace

import pytest

ROOT = Path(__file__).resolve().parents[4]
BUILDER = ROOT / "scripts/build_linux_runtime_bundle.py"
UPDATER = ROOT / "apps/vitalserver-platform-agent/packaging/linux/update-linux.py"
SUPPORT_EXPORTER = (
    ROOT / "apps/vitalserver-platform-agent/packaging/linux/support-export-linux.py"
)
RUNTIME_ENV_MIGRATOR = (
    ROOT / "apps/vitalserver-platform-agent/packaging/linux/migrate-runtime-env.py"
)


def test_linux_runtime_bundle_is_complete_and_deterministic(tmp_path: Path) -> None:
    agent = tmp_path / "agent"
    provider = tmp_path / "provider"
    _write_amd64_elf(agent)
    _write_amd64_elf(provider)
    pwa = tmp_path / "pwa"
    pwa.mkdir()
    (pwa / "index.html").write_text("runtime pwa", encoding="utf-8")
    runtime = tmp_path / "runtime"
    runtime.mkdir()
    (runtime / "compose.yaml").write_text("services: {}\n", encoding="utf-8")
    images = tmp_path / "images.tar"
    _write_docker_archive(images)
    wheelhouse = _write_runtime_controller_wheelhouse(tmp_path)
    first = tmp_path / "first.tar.gz"
    second = tmp_path / "second.tar.gz"

    for output in (first, second):
        subprocess.run(
            [
                sys.executable,
                str(BUILDER),
                "--platform-version",
                "2.0.0",
                "--runtime-bundle-version",
                "2.3.4",
                "--agent-binary",
                str(agent),
                "--provider-binary",
                str(provider),
                "--runtime-controller-wheelhouse",
                str(wheelhouse),
                "--pwa-directory",
                str(pwa),
                "--runtime-bundle-directory",
                str(runtime),
                "--images-archive",
                str(images),
                "--output",
                str(output),
            ],
            check=True,
        )

    assert _sha256(first) == _sha256(second)
    with tarfile.open(first, "r:gz") as archive:
        names = set(archive.getnames())
        assert {
            "VitalServer-Linux/install.sh",
            "VitalServer-Linux/checksums.sha256",
            "VitalServer-Linux/release.json",
            "VitalServer-Linux/bin/vitalserver-platform-agent",
            "VitalServer-Linux/bin/vitalserver-runtime-provider",
            "VitalServer-Linux/runtime-controller/install-guest-tools-runtime.py",
            "VitalServer-Linux/runtime-controller/python-wheels/manifest.json",
            "VitalServer-Linux/runtime-controller/python-wheels/guest-tools/guest-tools-0.1.0-py3-none-any.whl",
            "VitalServer-Linux/runtime-controller/python-wheels/linux-amd64/requirements.txt",
            "VitalServer-Linux/pwa/index.html",
            "VitalServer-Linux/runtime-bundle/compose.yaml",
            "VitalServer-Linux/images/runtime-images.tar",
            "VitalServer-Linux/packaging/runtime.env",
            "VitalServer-Linux/packaging/runtime-controller.toml",
            "VitalServer-Linux/packaging/runtime-settings.json",
            "VitalServer-Linux/packaging/redis-relay.toml",
            "VitalServer-Linux/packaging/migrate-runtime-env.py",
            "VitalServer-Linux/packaging/vitalserver-platform-agent.service",
            "VitalServer-Linux/packaging/vitalserver-runtime-controller.service",
            "VitalServer-Linux/packaging/vitalserver-runtime-provider.service",
            "VitalServer-Linux/packaging/acceptance-linux.py",
            "VitalServer-Linux/packaging/acceptance-reboot-linux.py",
            "VitalServer-Linux/packaging/acceptance-update-rollback-linux.py",
            "VitalServer-Linux/packaging/acceptance-uninstall-reinstall-linux.py",
            "VitalServer-Linux/packaging/rollback-linux.sh",
            "VitalServer-Linux/packaging/rollback-linux.py",
            "VitalServer-Linux/packaging/update-linux.py",
            "VitalServer-Linux/packaging/uninstall-linux.py",
            "VitalServer-Linux/packaging/support-export-linux.py",
            "VitalServer-Linux/packaging/trust-update-linux.py",
        }.issubset(names)
        checksums = archive.extractfile("VitalServer-Linux/checksums.sha256")
        assert checksums is not None
        checksum_text = checksums.read().decode("utf-8")
        assert "  images/runtime-images.tar" in checksum_text
        assert "  runtime-bundle/compose.yaml" in checksum_text
        release = archive.extractfile("VitalServer-Linux/release.json")
        assert release is not None
        assert (
            "runtimeControllerWheelhouseSHA256" in json.loads(release.read())["inputs"]
        )

    summary = subprocess.run(
        [sys.executable, str(UPDATER), "summary", "--bundle", str(first)],
        check=True,
        text=True,
        capture_output=True,
    )
    summary_document = json.loads(summary.stdout)
    assert summary_document["release"]["platformVersion"] == "2.0.0"
    assert "linux/amd64" in summary_document["summary"]
    verified = subprocess.run(
        [sys.executable, str(UPDATER), "verify", "--bundle", str(first)],
        check=True,
        text=True,
        capture_output=True,
    )
    assert json.loads(verified.stdout)["state"] == "verified"


def test_linux_runtime_environment_migration_adds_private_socket_or_blocks_legacy_url(
    tmp_path: Path,
) -> None:
    spec = importlib.util.spec_from_file_location(
        "linux_runtime_environment_migrator",
        RUNTIME_ENV_MIGRATOR,
    )
    assert spec is not None and spec.loader is not None
    migrator = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(migrator)
    environment = tmp_path / "runtime.env"
    legacy = (
        "VITALSERVER_ADMIN_PASSWORD=private\nVITALSERVER_POSTGRES_PASSWORD=private\n"
    )
    environment.write_text(legacy, encoding="utf-8")
    environment.chmod(0o600)

    assert migrator.migrate_runtime_environment(environment) is True
    assert environment.read_text(encoding="utf-8") == (
        legacy
        + "VITALSERVER_RUNTIME_RUN_DIR=/var/lib/vitalserver/run\n"
        + (
            "REDIS_RELAY_STATUS_OWNER_SOCKET="
            "/run/tirosh/status-owner/redis-relay-status-owner.sock\n"
        )
        + "REDIS_RELAY_STATUS_OWNER_URL=\n"
    )
    assert environment.stat().st_mode & 0o777 == 0o600
    assert migrator.migrate_runtime_environment(environment) is False

    blocked = tmp_path / "runtime-legacy-url.env"
    blocked_text = (
        legacy + "REDIS_RELAY_STATUS_OWNER_URL=http://legacy-owner:18330/status\n"
    )
    blocked.write_text(blocked_text, encoding="utf-8")
    blocked.chmod(0o600)

    with pytest.raises(migrator.RuntimeEnvironmentMigrationError) as error:
        migrator.migrate_runtime_environment(blocked)

    assert "refusing to replace" in str(error.value)
    assert blocked.read_text(encoding="utf-8") == blocked_text


def test_linux_update_verifier_rejects_unsafe_archive_member(tmp_path: Path) -> None:
    bundle = tmp_path / "unsafe.tar.gz"
    with tarfile.open(bundle, "w:gz") as archive:
        root = tarfile.TarInfo("VitalServer-Linux")
        root.type = tarfile.DIRTYPE
        archive.addfile(root)
        unsafe = tarfile.TarInfo("VitalServer-Linux/install.sh")
        unsafe.type = tarfile.SYMTYPE
        unsafe.linkname = "../../bin/sh"
        archive.addfile(unsafe)

    result = subprocess.run(
        [sys.executable, str(UPDATER), "verify", "--bundle", str(bundle)],
        text=True,
        capture_output=True,
    )

    assert result.returncode != 0
    document = json.loads(result.stdout)
    assert document["failure"]["kind"] == "updateBundleInvalid"
    assert "unsupported" in document["failure"]["message"]

    operation = tmp_path / "update-operation.json"
    applied = subprocess.run(
        [
            sys.executable,
            str(UPDATER),
            "apply",
            "--bundle",
            str(bundle),
            "--operation-id",
            "update-test-1",
            "--operation-document",
            str(operation),
        ],
        text=True,
        capture_output=True,
    )
    assert applied.returncode != 0
    operation_document = json.loads(operation.read_text(encoding="utf-8"))
    assert operation_document["operationId"] == "update-test-1"
    assert operation_document["state"] == "failed"
    assert operation_document["failure"]["kind"] == "updateApplyFailed"


def test_linux_runtime_bundle_rejects_non_linux_binary(tmp_path: Path) -> None:
    invalid = tmp_path / "agent"
    invalid.write_bytes(b"MZ windows")
    result = subprocess.run(
        [
            sys.executable,
            str(BUILDER),
            "--platform-version",
            "2.0.0",
            "--runtime-bundle-version",
            "2.3.4",
            "--agent-binary",
            str(invalid),
            "--provider-binary",
            str(invalid),
            "--runtime-controller-wheelhouse",
            str(tmp_path),
            "--pwa-directory",
            str(tmp_path),
            "--runtime-bundle-directory",
            str(tmp_path),
            "--images-archive",
            str(tmp_path / "missing.tar"),
            "--output",
            str(tmp_path / "bundle.tar.gz"),
        ],
        text=True,
        capture_output=True,
    )

    assert result.returncode != 0
    assert "not an ELF executable" in result.stderr


def test_linux_runtime_bundle_rejects_arm64_runtime_image(tmp_path: Path) -> None:
    spec = importlib.util.spec_from_file_location("linux_bundle_builder", BUILDER)
    assert spec is not None and spec.loader is not None
    builder = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(builder)
    images = tmp_path / "images.tar"
    _write_docker_archive(images, architecture="arm64")

    try:
        builder._require_docker_image_archive(images)
    except SystemExit as error:
        assert "must target linux/amd64" in str(error)
        assert "example:1.0" in str(error)
    else:
        raise AssertionError("arm64 Runtime image archive was accepted")


def test_linux_runtime_controller_bundle_requires_a_verified_wheelhouse(
    tmp_path: Path,
) -> None:
    spec = importlib.util.spec_from_file_location("linux_bundle_builder", BUILDER)
    assert spec is not None and spec.loader is not None
    builder = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(builder)
    wheelhouse = _write_runtime_controller_wheelhouse(tmp_path)

    builder._require_control_wheelhouse(wheelhouse)

    (wheelhouse / "linux-amd64/requirements.txt").unlink()
    with pytest.raises(SystemExit, match="linux-amd64 requirements"):
        builder._require_control_wheelhouse(wheelhouse)


def test_linux_runtime_controller_bundle_rejects_a_tampered_wheelhouse_manifest(
    tmp_path: Path,
) -> None:
    spec = importlib.util.spec_from_file_location("linux_bundle_builder", BUILDER)
    assert spec is not None and spec.loader is not None
    builder = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(builder)
    wheelhouse = _write_runtime_controller_wheelhouse(tmp_path)
    manifest_path = wheelhouse / "manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    manifest["guestTools"]["sha256"] = "0" * 64
    manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

    with pytest.raises(SystemExit, match="Guest Tools wheel SHA-256 mismatch"):
        builder._require_control_wheelhouse(wheelhouse)


@pytest.mark.parametrize(
    "dependency_wheel_name",
    (
        "alembic-1.16.0-py3-none-any.whl",
        "sqlalchemy-2.0.51-cp312-cp312-manylinux_2_17_x86_64.whl",
        "sqlalchemy-2.0.51-cp312-cp312-manylinux_2_28_x86_64.manylinux2014_x86_64.whl",
    ),
)
def test_linux_runtime_controller_bundle_accepts_cpython312_compatible_wheels(
    tmp_path: Path,
    dependency_wheel_name: str,
) -> None:
    spec = importlib.util.spec_from_file_location("linux_bundle_builder", BUILDER)
    assert spec is not None and spec.loader is not None
    builder = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(builder)

    builder._require_control_wheelhouse(
        _write_runtime_controller_wheelhouse(
            tmp_path,
            dependency_wheel_name=dependency_wheel_name,
        )
    )


@pytest.mark.parametrize(
    "dependency_wheel_name",
    (
        "sqlalchemy-2.0.51-cp312-cp312-manylinux_2_17_aarch64.whl",
        "sqlalchemy-2.0.51-cp312-cp311-manylinux_2_17_x86_64.whl",
        "sqlalchemy-2.0.51-cp312-cp312-manylinux_2_28_x86_64.whl",
        "sqlalchemy-2.0.51-cp312-cp312-linux_x86_64.whl",
    ),
)
def test_linux_runtime_controller_bundle_rejects_incompatible_wheel_tags(
    tmp_path: Path,
    dependency_wheel_name: str,
) -> None:
    spec = importlib.util.spec_from_file_location("linux_bundle_builder", BUILDER)
    assert spec is not None and spec.loader is not None
    builder = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(builder)

    with pytest.raises(
        SystemExit,
        match=r"not compatible with CPython 3\.12 linux/amd64",
    ):
        builder._require_control_wheelhouse(
            _write_runtime_controller_wheelhouse(
                tmp_path,
                dependency_wheel_name=dependency_wheel_name,
            )
        )


@pytest.mark.parametrize(
    "guest_wheel_name",
    (
        "guest_tools-0.1.0-cp312-cp312-manylinux_2_17_aarch64.whl",
        "guest_tools-0.1.0-cp312-cp311-manylinux_2_17_x86_64.whl",
        "guest_tools-0.1.0-cp312-cp312-linux_x86_64.whl",
    ),
)
def test_linux_runtime_controller_bundle_rejects_incompatible_guest_tools_wheel(
    tmp_path: Path,
    guest_wheel_name: str,
) -> None:
    spec = importlib.util.spec_from_file_location("linux_bundle_builder", BUILDER)
    assert spec is not None and spec.loader is not None
    builder = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(builder)

    with pytest.raises(
        SystemExit,
        match=r"not compatible with CPython 3\.12 linux/amd64",
    ):
        builder._require_control_wheelhouse(
            _write_runtime_controller_wheelhouse(
                tmp_path,
                guest_wheel_name=guest_wheel_name,
            )
        )


def test_linux_runtime_controller_bundle_requires_requirements_to_pin_manifest_wheels(
    tmp_path: Path,
) -> None:
    spec = importlib.util.spec_from_file_location("linux_bundle_builder", BUILDER)
    assert spec is not None and spec.loader is not None
    builder = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(builder)
    wheelhouse = _write_runtime_controller_wheelhouse(tmp_path)
    manifest_path = wheelhouse / "manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    requirements = wheelhouse / "linux-amd64/requirements.txt"
    guest_tools = manifest["guestTools"]
    requirements.write_text(
        "../guest-tools/guest-tools-0.1.0-py3-none-any.whl --hash=sha256:"
        + guest_tools["sha256"]
        + "\n",
        encoding="utf-8",
    )
    manifest["targets"]["linux-amd64"]["requirementsSHA256"] = _sha256(requirements)
    manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

    with pytest.raises(
        SystemExit,
        match="requirements do not pin every manifest wheel",
    ):
        builder._require_control_wheelhouse(wheelhouse)


def test_linux_runtime_controller_bundle_ignores_hashes_in_inline_comments(
    tmp_path: Path,
) -> None:
    spec = importlib.util.spec_from_file_location("linux_bundle_builder", BUILDER)
    assert spec is not None and spec.loader is not None
    builder = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(builder)
    requirements = tmp_path / "requirements.txt"
    guest_hash = "a" * 64
    dependency_hash = "b" * 64
    requirements.write_text(
        "guest-tools==0.1.0 --hash=sha256:"
        + guest_hash
        + " # --hash=sha256:"
        + dependency_hash
        + "\n",
        encoding="utf-8",
    )

    with pytest.raises(
        SystemExit,
        match="requirements do not pin every manifest wheel",
    ):
        builder._require_requirements_hash_closure(
            requirements,
            {guest_hash, dependency_hash},
        )


@pytest.mark.parametrize(
    ("requirements_text", "match"),
    [
        (
            "guest-tools==0.1.0 \\\n"
            "  # this physical line ends the continuation\n"
            "  --hash=sha256:{hash}\n",
            "not hash-pinned",
        ),
        (
            "guest-tools==0.1.0 \\ # this is not a continuation\n"
            "--hash=sha256:{hash}\n",
            "malformed line continuation",
        ),
        (
            "https://example.invalid/guest-tools.whl#--hash=sha256:{hash}\n",
            "not hash-pinned",
        ),
    ],
    ids=(
        "comment-after-continuation",
        "inline-comment-after-backslash",
        "url-fragment-is-not-option",
    ),
)
def test_linux_runtime_controller_bundle_matches_pip_requirement_preprocessing(
    tmp_path: Path,
    requirements_text: str,
    match: str,
) -> None:
    spec = importlib.util.spec_from_file_location("linux_bundle_builder", BUILDER)
    assert spec is not None and spec.loader is not None
    builder = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(builder)
    requirements = tmp_path / "requirements.txt"
    guest_hash = "a" * 64
    requirements.write_text(
        requirements_text.format(hash=guest_hash),
        encoding="utf-8",
    )

    with pytest.raises(SystemExit, match=match):
        builder._require_requirements_hash_closure(requirements, {guest_hash})


def test_linux_package_stages_an_amd64_guest_wheelhouse_before_bundling() -> None:
    makefile = (ROOT / "make/platform-agent.mk").read_text(encoding="utf-8")

    assert "platform-agent/build/linux-guest-wheelhouse:" in makefile
    assert 'rm -rf "$(LINUX_GUEST_RUNTIME_WHEELHOUSE)"' in makefile
    assert "scripts/stage_guest_runtime_wheelhouse.py" in makefile
    assert "--target linux-amd64" in makefile
    assert '--output "$(LINUX_GUEST_RUNTIME_WHEELHOUSE)"' in makefile
    assert (
        "platform-agent/package/linux: platform-agent/build/linux "
        "platform-agent/build/linux-provider "
        "platform-agent/build/linux-guest-wheelhouse pwa/build"
    ) in makefile
    assert (
        '--runtime-controller-wheelhouse "$(LINUX_GUEST_RUNTIME_WHEELHOUSE)"'
        in makefile
    )
    assert "--runtime-controller-source" not in makefile


def test_linux_installer_creates_every_hardened_runtime_directory() -> None:
    packaging = ROOT / "apps/vitalserver-platform-agent/packaging/linux"
    installer = (packaging / "install.sh").read_text(encoding="utf-8")
    agent_unit = (packaging / "vitalserver-platform-agent.service").read_text(
        encoding="utf-8"
    )
    controller_unit = (packaging / "vitalserver-runtime-controller.service").read_text(
        encoding="utf-8"
    )

    assert "install -d -m 0750 /var/log/vitalserver" in installer
    assert "ReadOnlyPaths=/etc/vitalserver /opt/vitalserver" in agent_unit
    assert "/usr/share/vitalserver" not in agent_unit
    assert "/etc/vitalserver/runtime-settings.json" in controller_unit
    assert "/etc/vitalserver/runtime-config.json" in controller_unit
    assert "runtime-controller/venv/bin/tirosh-vitalserver-guest-control-api" in (
        controller_unit
    )
    assert (
        "ExecStartPre=/opt/vitalserver/current/runtime-controller/venv/bin/"
        "tirosh-guest-tools-migrate-control-store"
    ) in controller_unit
    assert "--control-state-dir" not in controller_unit
    assert (
        'cp -a bin pwa runtime-bundle runtime-controller "$staging_root/"' in installer
    )
    assert "install-guest-tools-runtime.py" in installer
    assert (
        'python3 "$release_root/runtime-controller/install-guest-tools-runtime.py"'
        in installer
    )
    assert (
        'python3 "$staging_root/runtime-controller/install-guest-tools-runtime.py"'
        not in installer
    )
    assert installer.index('mv "$staging_root" "$release_root"') < installer.rindex(
        "if ! install_release_guest_tools; then"
    )
    controller_settings = (packaging / "runtime-controller.toml").read_text(
        encoding="utf-8"
    )
    assert 'guestToolsHome = "/opt/vitalserver/current/runtime-controller"' in (
        controller_settings
    )
    assert (
        'pythonWheelDir = "/opt/vitalserver/current/runtime-controller/python-wheels"'
        in controller_settings
    )
    assert (
        '[controlStore]\nroot = "/var/lib/vitalserver"\nrequiresMount = false'
        in controller_settings
    )
    assert '"$var_root/proof/linux-native-acceptance.json"' in installer
    assert '"installedAcceptanceRunId"' in installer


def test_linux_installer_removes_only_the_release_created_by_failed_workflow() -> None:
    installer = (
        ROOT / "apps/vitalserver-platform-agent/packaging/linux/install.sh"
    ).read_text(encoding="utf-8")

    assert "release_created=0" in installer
    assert 'if ! mv "$staging_root" "$release_root"; then' in installer
    assert (
        'release_created=1\n  if ! sync_directory "$opt_root/releases"; then'
        in installer
    )
    assert 'if [ "$release_created" -eq 1 ]; then' in installer
    assert 'rm -rf "$release_root"' in installer
    assert "trap rollback_install EXIT" in installer
    assert "trap 'rollback_install 129' HUP" in installer
    assert "trap 'rollback_install 130' INT" in installer
    assert "trap 'rollback_install 143' TERM" in installer


def test_linux_installer_requires_transaction_and_completion_proofs() -> None:
    installer = (
        ROOT / "apps/vitalserver-platform-agent/packaging/linux/install.sh"
    ).read_text(encoding="utf-8")

    assert 'install_transaction_document="$etc_root/install-transaction.json"' in (
        installer
    )
    assert 'release_completion_root="$etc_root/release-complete"' in installer
    assert 'release_completion_document="$release_completion_root/$version.json"' in (
        installer
    )
    assert "read_install_transaction()" in installer
    assert "finish_published_install_transaction()" in installer
    assert "begin_install_transaction()" in installer
    assert "install_transaction_resuming_first_install" not in installer
    assert "require_release_completion_proof()" in installer
    assert "write_release_completion_proof()" in installer
    assert '"state": "installing"' in installer
    assert '"state": "complete"' in installer
    assert "require_root_owned_regular_file()" in installer
    assert (
        "Installed release is incomplete without a matching Linux install transaction"
        in installer
    )
    assert "read_installed_owner_previous_release >/dev/null" in installer
    assert '[ "$current_target" != "$candidate_target" ] ||' in installer
    assert 'if document.get("platformVersion") != version:' in installer
    assert 'print("pending")' in installer
    assert 'print("committed")' in installer
    assert (
        "Linux install owner previousRelease does not match the active transaction"
        in installer
    )
    assert "previous_target=$current_target" in installer
    assert installer.index("finish_published_install_transaction;") < installer.index(
        "require_previous_release_artifacts()"
    )
    assert installer.index('! begin_install_transaction "$current_target"; then') < (
        installer.rindex('install -d -m 0755 "$etc_root" "$unit_root"')
    )
    assert installer.rindex("write_release_completion_proof") < installer.index(
        'ln -s "releases/$version" "$current_link.next.$$"'
    )
    assert installer.index('mv -f "$install_document" "$var_root/install.json"') < (
        installer.rindex('rm -f "$install_transaction_document"')
    )
    candidate_cleanup_guard = (
        'if [ "$release_created" -eq 1 ]; then\n'
        "    candidate_cleanup_required=1\n"
        '  elif [ "$install_transaction_active" -eq 1 ] && \\\n'
        '    [ "$release_root_exists" -eq 1 ] && \\\n'
        '    [ "$install_transaction_previous_target" != "releases/$version" ]; then'
    )
    assert candidate_cleanup_guard in installer
    assert installer.index("candidate_cleanup_required=0") < installer.index(
        'if [ "$install_transaction_active" -eq 1 ]; then',
        installer.index("candidate_cleanup_required=0"),
    )


def test_linux_installer_preserves_every_resumed_transaction_owner_for_retry() -> None:
    installer = (
        ROOT / "apps/vitalserver-platform-agent/packaging/linux/install.sh"
    ).read_text(encoding="utf-8")

    assert "install_transaction_preserve_for_retry=0" in installer
    read_transaction = installer[
        installer.index("read_install_transaction()") : installer.index(
            "begin_install_transaction()"
        )
    ]
    assert "install_transaction_preserve_for_retry=1" in read_transaction

    reconciler = installer[
        installer.index("finish_published_install_transaction()") : installer.index(
            "read_install_transaction()"
        )
    ]
    fresh_transaction = installer[
        installer.index("begin_install_transaction()") : installer.index(
            "validate_install_transaction_current_target()"
        )
    ]
    assert "install_transaction_preserve_for_retry=0" in reconciler
    assert "install_transaction_preserve_for_retry=0" in fresh_transaction

    rollback = installer[
        installer.index("rollback_install() {") : installer.index(
            "trap rollback_install EXIT"
        )
    ]
    preserve_guard = 'if [ "$install_transaction_preserve_for_retry" -eq 1 ]; then'
    assert preserve_guard in rollback
    assert "rollbackState=preserved-for-retry" in rollback
    assert rollback.index(preserve_guard) < rollback.index("rollback_failed=0")
    assert rollback.index(preserve_guard) < rollback.index('rm -f "$current_link"')
    assert rollback.index(preserve_guard) < rollback.index(
        'rm -f "$install_transaction_document"'
    )


def test_linux_installer_trusts_ancestors_and_commits_owner_before_cleanup() -> None:
    installer = (
        ROOT / "apps/vitalserver-platform-agent/packaging/linux/install.sh"
    ).read_text(encoding="utf-8")

    assert '"$opt_root" "Linux release root" 0755' in installer
    assert '"$opt_root/releases" "Linux releases root" 0755' in installer
    assert '"$var_root" "Linux install owner root" 0755' in installer
    assert 'current_target=$(readlink "$current_link")' in installer
    assert installer.index('"$opt_root/releases" "Linux releases root" 0755') < (
        installer.index("read_install_transaction;")
    )
    assert installer.index('"$var_root" "Linux install owner root" 0755') < (
        installer.rindex('install -d -m 0755 "$var_root/run"')
    )
    assert installer.count('if document.get("schemaVersion") != 1:') >= 2

    owner_document_sync = installer.index('sync "$install_document"')
    owner_publish_boundary = installer.index(
        "trap - EXIT HUP INT TERM", owner_document_sync
    )
    owner_rename = installer.index('mv -f "$install_document" "$var_root/install.json"')
    owner_directory_sync = installer.index(
        'if ! sync_directory "$var_root"; then', owner_rename
    )
    transaction_cleanup = installer.index(
        'if ! rm -f "$install_transaction_document"; then', owner_directory_sync
    )
    transaction_directory_sync = installer.index(
        'if ! sync_directory "$etc_root"; then', transaction_cleanup
    )
    assert (
        owner_document_sync
        < owner_publish_boundary
        < owner_rename
        < owner_directory_sync
        < transaction_cleanup
        < transaction_directory_sync
    )
    assert "phase=install-owner-publish reason=rename" in installer
    assert "phase=install-owner-publish reason=directory-durability" in installer
    assert "phase=install-transaction-cleanup reason=remove" in installer
    assert "transactionState=cleanup-durability-unknown" in installer


def test_linux_installer_durably_publishes_release_current_and_snapshot() -> None:
    installer = (
        ROOT / "apps/vitalserver-platform-agent/packaging/linux/install.sh"
    ).read_text(encoding="utf-8")

    snapshot_publish = installer.index('mv "$temporary_snapshot" "$snapshot_root"')
    snapshot_sync = installer.index(
        'if ! sync_directory "$release_systemd_snapshot_root/releases"; then',
        snapshot_publish,
    )
    release_publish = installer.index('if ! mv "$staging_root" "$release_root"; then')
    release_sync = installer.index(
        'if ! sync_directory "$opt_root/releases"; then', release_publish
    )
    current_publish = installer.index(
        'if ! ln -s "releases/$version" "$current_link.next.$$" ||'
    )
    current_sync = installer.index(
        'if ! sync_directory "$opt_root"; then', current_publish
    )
    rollback_current_publish = installer.index(
        'if ! ln -s "$previous_target" "$current_link.rollback.$$" ||'
    )
    rollback_current_sync = installer.index(
        '! sync_directory "$opt_root"; then', rollback_current_publish
    )

    assert snapshot_publish < snapshot_sync
    assert release_publish < release_sync < current_publish
    assert current_publish < current_sync
    assert rollback_current_publish < rollback_current_sync


def test_linux_acceptance_uses_runtime_provider_lifecycle_timestamp() -> None:
    acceptance = (
        ROOT / "apps/vitalserver-platform-agent/packaging/linux/acceptance-linux.py"
    ).read_text(encoding="utf-8")

    assert '("schemaVersion", "state", "updatedAt")' in acceptance
    assert '("schemaVersion", "state", "observedAt")' not in acceptance


def test_linux_installer_places_probe_timeout_only_in_native_provider_config() -> None:
    installer = (
        ROOT / "apps/vitalserver-platform-agent/packaging/linux/install.sh"
    ).read_text(encoding="utf-8")
    provider_marker = 'if [ ! -f "$etc_root/native-runtime-provider.json" ]; then'

    assert installer.count('"readinessProbeTimeoutSeconds": 20') == 1
    assert installer.index('"readinessProbeTimeoutSeconds": 20') > installer.index(
        provider_marker
    )


def test_linux_first_install_rollback_removes_every_created_control_owner() -> None:
    installer = (
        ROOT / "apps/vitalserver-platform-agent/packaging/linux/install.sh"
    ).read_text(encoding="utf-8")

    for flag in (
        "configuration_created",
        "runtime_settings_created",
        "redis_relay_configuration_created",
        "platform_agent_configuration_created",
        "native_provider_configuration_created",
        "runtime_controller_configuration_created",
    ):
        assert f"{flag}=0" in installer
        assert f'[ "${flag}" -eq 1 ]' in installer
    assert '"$etc_root/native-runtime-provider.json"' in installer
    assert '"$etc_root/platform-agent.json"' in installer
    assert '"$etc_root/runtime-controller.toml"' in installer
    assert 'rm -rf "$var_root/run" "$var_root/proof"' in installer
    assert '"$unit_root/vitalserver-runtime-provider.service"' in installer


def test_linux_installer_gives_expensive_runtime_reads_an_explicit_timeout() -> None:
    installer = (
        ROOT / "apps/vitalserver-platform-agent/packaging/linux/install.sh"
    ).read_text(encoding="utf-8")
    acceptance = (
        ROOT / "apps/vitalserver-platform-agent/packaging/linux/acceptance-linux.py"
    ).read_text(encoding="utf-8")

    assert "--http-timeout-seconds 120" in installer
    assert (
        'parser.add_argument("--http-timeout-seconds", type=int, default=60)'
        in acceptance
    )
    assert "urlopen(request, timeout=timeout_seconds)" in acceptance


def test_linux_same_version_reapply_preserves_rollback_lineage() -> None:
    installer = (
        ROOT / "apps/vitalserver-platform-agent/packaging/linux/install.sh"
    ).read_text(encoding="utf-8")

    assert (
        'if [ "$previous_release_for_owner" = "releases/$version" ]; then' in installer
    )
    assert "install_transaction_previous_target" in installer
    assert 'document.get("platformVersion") != version' in installer
    assert 'document.get("previousRelease")' in installer
    assert 'previous_release == f"releases/{version}"' in installer
    assert '"$previous_release_for_owner"' in installer


def test_linux_installer_migrates_and_rolls_back_platform_delivery_config() -> None:
    packaging = ROOT / "apps/vitalserver-platform-agent/packaging/linux"
    installer = (packaging / "install.sh").read_text(encoding="utf-8")
    rollback = (packaging / "rollback-linux.sh").read_text(encoding="utf-8")

    assert 'rollback_tool_path="$release_root/tools/rollback-linux.py"' in installer
    assert '"rollbackTool": "$rollback_tool_path"' in installer
    assert '"$etc_root/platform-agent.json" "$api_token" "$rollback_tool_path"' in (
        installer
    )
    assert (
        'legacy_rollback_tool = "/opt/vitalserver/current/tools/rollback-linux.py"'
        in installer
    )
    assert "Platform Agent configuration migration rollbackTool is invalid" in installer
    assert (
        "Platform Agent configuration migration rollbackTool is unavailable"
        in installer
    )
    assert 'delivery["rollbackTool"] = rollback_tool_path' in installer
    assert "Release-owned Linux rollback tool is missing or not executable" in installer
    assert "platform-agent.json" not in rollback
    assert (
        '"uninstallTool": "/opt/vitalserver/current/tools/uninstall-linux.py"'
        in installer
    )
    assert (
        '"supportExportTool": "/opt/vitalserver/current/tools/support-export-linux.py"'
        in installer
    )
    assert (
        "install -m 0755 packaging/support-export-linux.py "
        '"$staging_root/tools/support-export-linux.py"'
    ) in installer
    assert (
        "install -m 0755 packaging/support-export-linux.py "
        '"$staging_root/tools/support-export-linux.py"' in installer
    )
    assert '"schedulerKind": "systemd-transient"' in installer
    assert 'document.get("apiToken") != api_token' in installer
    assert "platform_agent_configuration_backed_up=1" in installer
    assert "Platform Agent configuration restoration failed" in installer
    assert installer.index(
        "Platform Agent configuration restoration failed"
    ) < installer.index("systemctl restart vitalserver-platform-agent.service")
    assert "trap - EXIT HUP INT TERM" in installer


def test_linux_installer_migrates_existing_runtime_environment_transactionally() -> (
    None
):
    installer = (
        ROOT / "apps/vitalserver-platform-agent/packaging/linux/install.sh"
    ).read_text(encoding="utf-8")

    assert "runtime_environment_backed_up=0" in installer
    assert (
        'runtime_environment_backup="$etc_root/.runtime.env.rollback.$$"' in installer
    )
    assert (
        'install -m 0600 "$runtime_environment" "$runtime_environment_backup"'
        in installer
    )
    assert 'python3 "$bundle_dir/packaging/migrate-runtime-env.py"' in installer
    assert '--path "$runtime_environment"' in installer
    assert "Linux Runtime environment transport migration failed" in installer
    assert 'if [ "$runtime_environment_backed_up" -eq 1 ]; then' in installer
    assert (
        'install -m 0600 "$runtime_environment_backup" "$etc_root/runtime.env"'
        in installer
    )
    assert installer.index(
        "Linux install rollback Runtime environment restoration failed"
    ) < installer.index("systemctl restart vitalserver-runtime-controller.service")
    assert (
        'rm -f "$runtime_environment_backup"\nruntime_environment_backed_up=0'
        in installer
    )
    assert "units_backed_up=0" in installer
    assert (
        'runtime_controller_unit_backup="$unit_root/.vitalserver-runtime-controller.service.rollback.$$"'
        in installer
    )
    assert 'if [ -n "$previous_target" ]; then' in installer
    assert (
        'install -m 0644 "$unit_root/vitalserver-runtime-controller.service" \\\n'
        '    "$runtime_controller_unit_backup"'
    ) in installer
    assert 'if [ "$units_backed_up" -eq 1 ]; then' in installer
    assert (
        'install -m 0644 "$runtime_controller_unit_backup" \\\n'
        '      "$unit_root/vitalserver-runtime-controller.service"'
    ) in installer
    assert installer.index(
        "Linux install rollback systemd unit restoration failed"
    ) < installer.index("Linux install rollback systemd reload failed")
    platform_agent_unit_cleanup = 'rm -f \\\n  "$platform_agent_unit_backup"'
    assert installer.rindex(platform_agent_unit_cleanup) < installer.rindex(
        "units_backed_up=0"
    )


def test_linux_update_uses_explicit_non_nested_support_acceptance_mode() -> None:
    installer = (
        ROOT / "apps/vitalserver-platform-agent/packaging/linux/install.sh"
    ).read_text(encoding="utf-8")
    updater = UPDATER.read_text(encoding="utf-8")
    acceptance = (
        ROOT / "apps/vitalserver-platform-agent/packaging/linux/acceptance-linux.py"
    ).read_text(encoding="utf-8")

    assert (
        '--acceptance-support-export-mode "$acceptance_support_export_mode"'
        not in installer
    )
    assert '--support-export-mode "$acceptance_support_export_mode"' in installer
    assert '"--acceptance-support-export-mode",' in updater
    assert '"capability-only",' in updater
    assert 'choices=("execute", "capability-only")' in acceptance
    assert 'args.support_export_mode == "capability-only"' in acceptance


def test_linux_rollback_restores_the_target_release_systemd_units() -> None:
    packaging = ROOT / "apps/vitalserver-platform-agent/packaging/linux"
    installer = (packaging / "install.sh").read_text(encoding="utf-8")
    rollback = (packaging / "rollback-linux.sh").read_text(encoding="utf-8")

    assert 'install -d -m 0755 "$staging_root/tools/systemd"' in installer
    assert (
        '"$staging_root/tools/systemd/vitalserver-runtime-controller.service"'
        in installer
    )
    assert "snapshot_release_systemd_units()" in installer
    assert 'snapshot_release_systemd_units "$previous_target"' in installer
    assert (
        'release_systemd_snapshot_root="$etc_root/release-systemd-units"' in installer
    )
    assert "release_systemd_snapshot_root=$etc_root/release-systemd-units" in rollback
    assert "$var_root/release-systemd-units" not in installer
    assert "$var_root/release-systemd-units" not in rollback
    controller_unit = (packaging / "vitalserver-runtime-controller.service").read_text(
        encoding="utf-8"
    )
    assert "ReadOnlyPaths=/etc/vitalserver" in controller_unit
    assert "/etc/vitalserver/release-systemd-units" not in controller_unit
    assert (
        'temporary_snapshot="$release_systemd_snapshot_root/releases/'
        '.${release_version}.systemd.snapshot.$$"'
    ) in installer
    assert 'snapshot_root="$release_systemd_snapshot_root/$release"' in installer
    assert 'cmp -s "$unit_root/$unit" "$snapshot_root/$unit"' in installer
    assert 'temporary_snapshot="$opt_root/$release/tools/' not in installer
    assert "release_systemd_snapshot_created=0" in installer
    assert 'release_systemd_snapshot_temporary=""' in installer
    assert "created systemd snapshot cleanup failed" in installer
    assert installer.index('snapshot_release_systemd_units "$previous_target"') < (
        installer.index(
            'install -m 0644 "$unit_root/vitalserver-platform-agent.service"'
        )
    )
    assert "require_previous_release_artifacts()" in installer
    assert 'require_previous_release_artifacts "$previous_target"' in installer
    assert "Existing Linux release rollback acceptance tool is missing" in installer
    assert installer.index('require_previous_release_artifacts "$previous_target"') < (
        installer.index('snapshot_release_systemd_units "$previous_target"')
    )
    assert "resolve_release_unit_directory()" in rollback
    assert "restore_release_units()" in rollback
    assert (
        'current_unit_source=$(resolve_release_unit_directory "$current_target")'
        in rollback
    )
    assert (
        'previous_unit_source=$(resolve_release_unit_directory "$previous_target")'
        in rollback
    )
    assert 'migration_snapshot="$release_systemd_snapshot_root/$release"' in rollback
    assert (
        'restore_release_units "$previous_target" "$previous_unit_source"' in rollback
    )
    target_unit_restore = (
        'restore_release_units "$previous_target" "$previous_unit_source"'
    )
    restart_services = (
        "systemctl daemon-reload\n"
        "systemctl restart vitalserver-runtime-provider.service"
    )
    assert rollback.index(target_unit_restore) < rollback.index(restart_services)
    current_unit_restore = (
        'if ! restore_release_units "$current_target" "$current_unit_source"; then'
    )
    assert rollback.index(current_unit_restore) < rollback.index(
        'if [ "$release_restored" -eq 1 ] && [ "$document_restored" -eq 1 ]'
    )
    assert "|| true" not in rollback
    assert "rollback systemd unit restoration failed" in rollback
    assert (
        "original service restart skipped because restoration is incomplete" in rollback
    )
    assert "restoreState=$restore_state" in rollback
    assert "trap 'restore_current 129' HUP" in rollback


def test_linux_resumed_transaction_uses_snapshot_prestate() -> None:
    installer = (
        ROOT / "apps/vitalserver-platform-agent/packaging/linux/install.sh"
    ).read_text(encoding="utf-8")
    snapshot = installer[
        installer.index("snapshot_release_systemd_units() {") : installer.index(
            "if ! ensure_root_owned_nonwritable_directory"
        )
    ]
    unit_directory = installer[
        installer.index("require_systemd_unit_directory() {") : installer.index(
            "ensure_release_systemd_snapshot_root() {"
        )
    ]
    existing_snapshot = snapshot[
        snapshot.index(
            'if [ -e "$snapshot_root" ] || [ -L "$snapshot_root" ]; then'
        ) : snapshot.index("if ! ensure_release_systemd_snapshot_root; then")
    ]
    resumed_guard = 'if [ "$install_transaction_preserve_for_retry" -eq 1 ]; then'

    assert (
        'require_root_owned_nonwritable_directory "$directory" "$label"'
        in unit_directory
    )
    assert (
        'require_root_owned_regular_file "$directory/$unit" "$label unit"'
        in unit_directory
    )
    assert resumed_guard in existing_snapshot
    assert existing_snapshot.index(resumed_guard) < existing_snapshot.index(
        'if ! cmp -s "$unit_root/$unit" "$snapshot_root/$unit"; then'
    )

    missing_snapshot = snapshot[
        snapshot.index(
            resumed_guard,
            snapshot.index(resumed_guard) + len(resumed_guard),
        ) : snapshot.index("if ! ensure_release_systemd_snapshot_root; then")
    ]
    assert (
        "migration snapshot is unavailable for resumed transaction" in missing_snapshot
    )
    assert "return 1" in missing_snapshot


def test_linux_update_rollback_does_not_restart_a_partially_restored_release() -> None:
    installer = (
        ROOT / "apps/vitalserver-platform-agent/packaging/linux/install.sh"
    ).read_text(encoding="utf-8")

    assert "release_restored=1" in installer
    assert "owner_configuration_restored=1" in installer
    assert "units_restored=1" in installer
    assert (
        "rollback service restart skipped because owner restoration is incomplete"
        in installer
    )
    restoration_guard = (
        'if [ "$release_restored" -eq 1 ] && \\\n'
        '      [ "$owner_configuration_restored" -eq 1 ] && \\\n'
        '      [ "$units_restored" -eq 1 ]; then'
    )
    assert restoration_guard in installer
    assert installer.index(restoration_guard) < installer.index(
        "systemctl daemon-reload"
    )


def test_linux_install_rollback_preserves_legacy_unit_snapshot_when_restore_fails() -> (
    None
):
    installer = (
        ROOT / "apps/vitalserver-platform-agent/packaging/linux/install.sh"
    ).read_text(encoding="utf-8")

    snapshot_cleanup = 'if [ "$release_systemd_snapshot_created" -eq 1 ]; then'
    assert snapshot_cleanup in installer
    assert 'if [ "$rollback_failed" -eq 0 ]; then' in installer
    assert "preserves systemd migration snapshot because restoration is incomplete" in (
        installer
    )
    assert installer.index(snapshot_cleanup) > installer.index(
        'if [ "$release_created" -eq 1 ]; then'
    )


def test_linux_resumed_first_install_uses_the_shared_preserve_for_retry_path() -> None:
    installer = (
        ROOT / "apps/vitalserver-platform-agent/packaging/linux/install.sh"
    ).read_text(encoding="utf-8")

    assert "install_transaction_resuming_first_install" not in installer
    rollback = installer[
        installer.index("rollback_install() {") : installer.index(
            "trap rollback_install EXIT"
        )
    ]
    preserve_guard = 'if [ "$install_transaction_preserve_for_retry" -eq 1 ]; then'
    assert rollback.index(preserve_guard) < rollback.index(
        "Linux first-install rollback service stop failed"
    )
    assert rollback.index(preserve_guard) < rollback.index(
        "Linux first-install rollback current release removal failed"
    )


def test_linux_uninstall_preserves_runtime_data_only_in_standard_mode() -> None:
    uninstall = (
        ROOT / "apps/vitalserver-platform-agent/packaging/linux/uninstall-linux.py"
    ).read_text(encoding="utf-8")

    for required in (
        'choices=("standard", "clean")',
        'expected_target = f"releases/{platform_version}"',
        'release.get("platformVersion") != platform_version',
        'delivery.get("uninstallTool")',
        '"composeProjectName": "vitalserver"',
        'compose.append("--volumes")',
        'run(["systemctl", "disable", *UNITS])',
        "remove_tree(OPT_ROOT)",
        '"runtimeDataPreserved": args.mode == "standard"',
        '"kind": "uninstall"',
        '"kind": "uninstallFailed"',
        "EXTERNAL_PROOF_ROOT",
        "runtime-controller/venv/bin/",
        "tirosh-vitalserver-guest-control-api",
    ):
        assert required in uninstall
    assert "vitalserver-runtime-controller.pyz" not in uninstall
    assert 'compose.append("--volumes")' in uninstall.split('if mode == "clean":', 1)[1]


def test_linux_update_trust_requires_out_of_band_digest_and_restores_owners() -> None:
    script = (
        ROOT / "apps/vitalserver-platform-agent/packaging/linux/trust-update-linux.py"
    ).read_text(encoding="utf-8")

    for required in (
        'parser.add_argument("--expected-sha256", required=True)',
        "actual = digest.hexdigest()",
        "actual != expected",
        'delivery["applyPolicy"] = "sha256-allowlist"',
        'delivery["trustedBundleDigests"] = str(args.catalog)',
        'configured_inbox = delivery.get("trustedBundleInbox")',
        "stage_trusted_bundle(",
        'default=Path("/var/lib/vitalserver/inbox")',
        'destination = inbox / f"trusted-{expected}.bundle"',
        'run(["systemctl", "restart", args.service])',
        "restore_owner(args.config, original_config)",
        "args.catalog.unlink(missing_ok=True)",
    ):
        assert required in script
    assert "expected = actual" not in script


def test_linux_support_export_preserves_each_source_result(
    monkeypatch, tmp_path: Path
) -> None:
    spec = importlib.util.spec_from_file_location(
        "support_export_linux", SUPPORT_EXPORTER
    )
    assert spec is not None and spec.loader is not None
    exporter = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(exporter)

    owner = tmp_path / "install.json"
    owner.write_text('{"schemaVersion": 1}\n', encoding="utf-8")
    missing = tmp_path / "runtime-provider.json"
    operation = tmp_path / "platform-workflow.json"
    support = tmp_path / "support"
    operation_id = "workflow-0123456789abcdef0123456789abcdef"
    monkeypatch.setattr(exporter, "SAFE_OWNER_FILES", (owner, missing))
    monkeypatch.setattr(exporter, "SERVICE_NAMES", ("vitalserver-test.service",))
    monkeypatch.setattr(
        exporter,
        "parse_args",
        lambda: SimpleNamespace(
            operation_id=operation_id,
            operation_document=operation,
            support_directory=support,
        ),
    )
    monkeypatch.setattr(
        exporter.subprocess,
        "run",
        lambda command, **_: subprocess.CompletedProcess(
            command, 1, stdout=b"", stderr=b"service unavailable"
        ),
    )

    assert exporter.main() == 0
    workflow = json.loads(operation.read_text(encoding="utf-8"))
    assert workflow["state"] == "completed"
    assert workflow["artifact"]["path"] == str(
        support / f"vitalserver-support-{operation_id}.tar.gz"
    )
    assert workflow["artifact"]["sha256"] == _sha256(Path(workflow["artifact"]["path"]))
    with tarfile.open(workflow["artifact"]["path"], "r:gz") as archive:
        manifest_file = archive.extractfile("vitalserver-support/manifest.json")
        assert manifest_file is not None
        manifest = json.load(manifest_file)
        collected = manifest["files"]
        assert {
            "source": str(owner),
            "archivePath": "owners/install.json",
            "state": "collected",
            "sizeBytes": owner.stat().st_size,
        } in collected
        assert {
            "source": str(missing),
            "archivePath": None,
            "state": "missing",
        } in collected
        failures = [item for item in collected if item["state"] == "command-failed"]
        assert len(failures) == 2
        assert all(item["archivePath"].startswith("diagnostics/") for item in failures)
        status = next(item for item in failures if item["command"][0] == "systemctl")
        property_argument = next(
            argument
            for argument in status["command"]
            if argument.startswith("--property=")
        )
        assert "Environment" not in property_argument


def test_linux_uninstall_reinstall_acceptance_proves_all_persistent_owners() -> None:
    acceptance = (
        ROOT
        / (
            "apps/vitalserver-platform-agent/packaging/linux/"
            "acceptance-uninstall-reinstall-linux.py"
        )
    ).read_text(encoding="utf-8")

    for required in (
        '"POST", "/platform/uninstall", {"mode": "standard"}',
        "wait_local_operation(",
        'Path("/opt/vitalserver").exists()',
        "subprocess.run([str(installer)]",
        'tree_digest(Path("/etc/vitalserver"), mutable_owner_paths())',
        '["docker", "volume", "inspect", name]',
        "actual_volume != volume",
        '"kind": "uninstall-reinstall-data-preservation"',
        '"reinstall-data-preserved"',
    ):
        assert required in acceptance


def test_linux_rollback_switches_release_owner_and_preserves_mutable_data() -> None:
    rollback = (
        ROOT / "apps/vitalserver-platform-agent/packaging/linux/rollback-linux.sh"
    ).read_text(encoding="utf-8")
    rollback_workflow = (
        ROOT / "apps/vitalserver-platform-agent/packaging/linux/rollback-linux.py"
    ).read_text(encoding="utf-8")

    assert 'document.get("previousRelease")' in rollback
    assert 'mv -Tf "$current_link.rollback.$$" "$current_link"' in rollback
    assert "linux-native-rollback-acceptance.json" in rollback
    assert "--support-export-mode capability-only" in rollback
    assert 'mv -f "$install_document_backup" "$install_document"' in rollback
    assert '"previousRelease": previous_release' in rollback
    assert "rm -rf /var/lib/vitalserver" not in rollback
    assert "rm -rf /etc/vitalserver" not in rollback
    assert '"kind": "rollback"' in rollback_workflow
    assert '"running"' in rollback_workflow
    assert '"completed"' in rollback_workflow
    assert '"rollbackFailed"' in rollback_workflow


def _write_amd64_elf(path: Path) -> None:
    header = bytearray(64)
    header[:4] = b"\x7fELF"
    header[4] = 2
    header[5] = 1
    header[18:20] = struct.pack("<H", 62)
    path.write_bytes(header)
    path.chmod(0o755)


def _write_docker_archive(path: Path, *, architecture: str = "amd64") -> None:
    config_name = "config.json"
    config = json.dumps({"architecture": architecture, "os": "linux"}).encode()
    manifest = json.dumps(
        [{"Config": config_name, "RepoTags": ["example:1.0"], "Layers": []}]
    ).encode()
    with tarfile.open(path, "w") as archive:
        for name, data in (("manifest.json", manifest), (config_name, config)):
            info = tarfile.TarInfo(name)
            info.size = len(data)
            info.mtime = 0
            archive.addfile(info, io.BytesIO(data))


def _write_runtime_controller_wheelhouse(
    tmp_path: Path,
    *,
    guest_wheel_name: str = "guest-tools-0.1.0-py3-none-any.whl",
    dependency_wheel_name: str = (
        "sqlalchemy-2.0.51-cp312-cp312-manylinux_2_17_x86_64.whl"
    ),
) -> Path:
    wheelhouse = tmp_path / "wheelhouse"
    guest_tools = wheelhouse / "guest-tools"
    amd64 = wheelhouse / "linux-amd64"
    guest_tools.mkdir(parents=True)
    amd64.mkdir()
    guest_wheel = guest_tools / guest_wheel_name
    dependency_wheel = amd64 / dependency_wheel_name
    guest_wheel.write_bytes(b"guest")
    dependency_wheel.write_bytes(b"sqlalchemy")
    requirements = amd64 / "requirements.txt"
    requirements.write_text(
        "../guest-tools/"
        + guest_wheel.name
        + " --hash=sha256:"
        + _sha256(guest_wheel)
        + "\n"
        + "sqlalchemy==2.0.51 --hash=sha256:"
        + _sha256(dependency_wheel)
        + "\n",
        encoding="utf-8",
    )
    (wheelhouse / "manifest.json").write_text(
        json.dumps(
            {
                "schemaVersion": 1,
                "guestPython": {"major": 3, "minor": 12},
                "guestTools": {
                    "path": guest_wheel.relative_to(wheelhouse).as_posix(),
                    "sha256": _sha256(guest_wheel),
                },
                "targets": {
                    "linux-amd64": {
                        "requirementsPath": requirements.relative_to(
                            wheelhouse
                        ).as_posix(),
                        "requirementsSHA256": _sha256(requirements),
                        "wheels": [
                            {
                                "path": dependency_wheel.name,
                                "sha256": _sha256(dependency_wheel),
                            }
                        ],
                    }
                },
            }
        ),
        encoding="utf-8",
    )
    return wheelhouse


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()
