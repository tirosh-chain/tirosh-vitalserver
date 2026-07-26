from __future__ import annotations

import importlib.util
import json
import tomllib
from pathlib import Path
from zipfile import ZipFile

import pytest
import yaml

from tirosh_vitalserver.devtools.adapters.build_config import load_config
from tirosh_vitalserver.devtools.adapters.guest_services import deploy_bundle
from tirosh_vitalserver.devtools.adapters.guest_services.deploy_bundle import (
    stage_guest_deploy,
)
from tirosh_vitalserver.devtools.application.guest_service_plans import (
    docker_image_bundle_build_plan,
)
from tirosh_vitalserver.devtools.application.usecases import (
    guest_services as guest_services_usecases,
)
from tirosh_vitalserver.devtools.config.docker_images import load_docker_images_config
from tirosh_vitalserver.devtools.config.guest_deploy import load_guest_deploy_config
from tirosh_vitalserver.devtools.core.guest_deploy import (
    GuestDeployConfig,
    GuestDeployInclude,
)
from tirosh_vitalserver.devtools.core.guest_services import (
    guest_compose_contract_errors,
    guest_deploy_plan,
)

ROOT = Path(__file__).resolve().parents[4]
GUEST_TOOLS_RUNTIME_INSTALLER = (
    ROOT / "apps/vitalserver-macos-runtime/Support/Guest/install-guest-tools-runtime.py"
)
HOST_PYTHON_PACKAGES = (
    ROOT / "packages/vitalserver-core/pyproject.toml",
    ROOT / "packages/vitalserver-guest-tools/pyproject.toml",
    ROOT / "packages/vitalserver-testkit/pyproject.toml",
    ROOT / "packages/vitalserver-vitalfile/pyproject.toml",
    ROOT / "apps/vitalserver-recorder-recovery/pyproject.toml",
)


def test_packaged_guest_configs_use_vitaldb_observer_api_contract() -> None:
    expected_url = "http://127.0.0.1:18084/api/v1/observations"
    config_paths = (
        ROOT
        / (
            "packages/vitalserver-guest-tools/src/tirosh_guest_tools/resources/"
            "guest-tools.toml"
        ),
        ROOT
        / "apps/vitalserver-platform-agent/packaging/linux/runtime-controller.toml",
        ROOT
        / (
            "apps/vitalserver-platform-agent/packaging/windows/hyperv-guest/"
            "guest-tools.toml"
        ),
    )

    for config_path in config_paths:
        config = tomllib.loads(config_path.read_text(encoding="utf-8"))
        assert config["observability"]["vitaldbObserverUrl"] == expected_url


def test_host_python_baseline_matches_guest_runtime_targets() -> None:
    host_python = (ROOT / ".python-version").read_text(encoding="utf-8").strip()
    root_pyproject = tomllib.loads(
        (ROOT / "pyproject.toml").read_text(encoding="utf-8")
    )
    guest_python_versions = {
        f"{target['python_version'][0]}.{target['python_version'][1:]}"
        for target in deploy_bundle.GUEST_RUNTIME_TARGETS.values()
    }

    assert host_python == "3.12"
    assert guest_python_versions == {host_python}
    assert root_pyproject["project"]["requires-python"] == ">=3.12"
    assert root_pyproject["tool"]["ruff"]["target-version"] == "py312"
    assert root_pyproject["tool"]["mypy"]["python_version"] == host_python
    for package_pyproject in HOST_PYTHON_PACKAGES:
        package = tomllib.loads(package_pyproject.read_text(encoding="utf-8"))
        assert package["project"]["requires-python"] == ">=3.12"


def runtime_product_minimal_compose(
    *,
    include_lab: bool = True,
    include_testkit: bool = False,
) -> str:
    services = {
        "postgres": "postgres:16-alpine",
        "postgres-migrate": "vitalserver-postgres-migrator:0.2.0",
        "redis": "redis:3.2.12-alpine",
        "app": "vitalserver:2.3.4",
        "recorder-recovery": "vitalserver-recorder-recovery:0.2.0",
        "recorder-ingress": "vitalserver-recorder-ingress:0.2.1",
        "vitaldb-observer": "vitaldb-observer:0.2.0",
        "redis-relay": "vitalserver-redis-relay:0.2.0",
        "edge": "nginx:1.24-alpine",
    }
    if include_lab:
        services["lab"] = "vitalserver-lab:0.2.0"
    if include_testkit:
        services["testkit"] = "testkit:0.2.0"
    lines = ["services:"]
    for service, image in services.items():
        lines.extend([f"  {service}:", f"    image: {image}"])
    return "\n".join(lines) + "\n"


def release_guest_compose_contract_errors(
    *,
    compose_text: str,
    deploy_include_sources: list[Path] | None = None,
) -> tuple[str, ...]:
    config = load_config(ROOT / "config/vm-build.toml")
    docker_config = load_docker_images_config(config, ROOT)
    deploy_config = load_guest_deploy_config(config)
    plan = docker_image_bundle_build_plan(
        root=ROOT,
        docker_config=docker_config,
        bundle_path=None,
        platform=None,
        compression_threads=None,
    )
    return guest_compose_contract_errors(
        root=ROOT,
        compose_text=compose_text,
        image_plan=plan.image_plan,
        known_images=set(docker_config.images) | set(docker_config.optional_images),
        deploy_include_sources=(
            deploy_include_sources
            if deploy_include_sources is not None
            else [entry.source for entry in deploy_config.includes]
        ),
        optional_images=set(docker_config.optional_images),
        include_optional=False,
    )


def test_guest_compose_contract_accepts_release_declared_services() -> None:
    compose_text = (
        ROOT / "apps/vitalserver-macos-runtime/Support/Guest/compose.yaml"
    ).read_text(encoding="utf-8")

    assert release_guest_compose_contract_errors(compose_text=compose_text) == ()


def test_packaged_redis_startup_preserves_corrupt_aof_for_explicit_repair() -> None:
    compose_path = ROOT / "apps/vitalserver-macos-runtime/Support/Guest/compose.yaml"
    document = yaml.safe_load(compose_path.read_text(encoding="utf-8"))
    redis = document["services"]["redis"]
    startup_script = redis["command"][2]

    assert "redis-check-aof /data/appendonly.aof" in startup_script
    assert "redis-check-aof --fix" not in startup_script
    assert "cp /data/appendonly.aof" not in startup_script
    assert "automatic repair is disabled" in startup_script
    assert "exit 1" in startup_script


def test_vitalfile_package_is_guest_deploy_and_rootfs_contract_input() -> None:
    config = load_config(ROOT / "config/vm-build.toml")
    deploy_config = load_guest_deploy_config(config)
    deploy_sources = {entry.source for entry in deploy_config.includes}
    rootfs_makefile = (ROOT / "make/vm/package.mk").read_text(encoding="utf-8")

    assert Path("packages/vitalserver-vitalfile") in deploy_sources
    assert "\tpackages/vitalserver-vitalfile \\" in rootfs_makefile


def test_guest_compose_contract_rejects_missing_runtime_product_service() -> None:
    errors = release_guest_compose_contract_errors(
        compose_text=runtime_product_minimal_compose(include_lab=False),
    )

    assert any("missing=['lab']" in error for error in errors)


def test_guest_compose_contract_rejects_testkit_runtime_service() -> None:
    errors = release_guest_compose_contract_errors(
        compose_text=runtime_product_minimal_compose(include_testkit=True),
    )

    assert any("forbidden=['testkit']" in error for error in errors)


def test_guest_compose_contract_rejects_stale_product_image_tag() -> None:
    errors = release_guest_compose_contract_errors(
        compose_text=runtime_product_minimal_compose().replace(
            "vitalserver-recorder-recovery:0.2.0",
            "vitalserver-recorder-recovery:0.1.0",
        ),
    )

    assert any(
        "Guest compose image is not declared in VM Docker image config: "
        "service=recorder-recovery image=vitalserver-recorder-recovery:0.1.0" in error
        for error in errors
    )


def test_guest_compose_contract_rejects_missing_redis_relay_deploy_include() -> None:
    config = load_config(ROOT / "config/vm-build.toml")
    deploy_config = load_guest_deploy_config(config)
    compose_text = (
        ROOT / "apps/vitalserver-macos-runtime/Support/Guest/compose.yaml"
    ).read_text(encoding="utf-8")

    errors = release_guest_compose_contract_errors(
        compose_text=compose_text,
        deploy_include_sources=[
            entry.source
            for entry in deploy_config.includes
            if entry.source != Path("apps/vitalserver-redis-relay")
        ],
    )

    assert any(
        "Guest compose Dockerfile is not covered by Guest deploy includes: "
        "service=redis-relay" in error
        for error in errors
    )


def test_docker_compile_rejects_invalid_compose_before_docker(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    runtime_dir = tmp_path / "runtime"
    compose_path = runtime_dir / "Support/Guest/compose.yaml"
    compose_path.parent.mkdir(parents=True)
    compose_path.write_text(
        runtime_product_minimal_compose(include_lab=False),
        encoding="utf-8",
    )
    monkeypatch.setattr(
        guest_services_usecases,
        "run_docker_image_bundle",
        lambda **_: pytest.fail("invalid Guest compose must stop before Docker"),
    )

    with pytest.raises(SystemExit, match="Guest compose compile contract failed"):
        guest_services_usecases.build_configured_docker_image_bundles(
            root=ROOT,
            config=ROOT / "config/vm-build.toml",
            runtime_dir=runtime_dir,
            bundle_path=tmp_path / "images.tar.gz",
            platform=None,
            compression_threads=None,
            include_optional=False,
        )


def test_stage_guest_deploy_uses_configured_includes(tmp_path: Path) -> None:
    root = tmp_path / "repo"
    runtime_dir = root / "apps/runtime"
    deploy_dir = tmp_path / "vm-home/data/deploy"
    (runtime_dir / "Support/Guest").mkdir(parents=True)
    (runtime_dir / "Support/Guest/bootstrap.sh").write_text("bootstrap\n")
    (runtime_dir / "Support/Guest/runtime-settings.json").write_text(
        '{"recorderIngressSendDataMode":"spool_and_replay"}\n'
    )
    (root / "apps/service").mkdir(parents=True)
    (root / "apps/service/app.py").write_text("service\n")
    wheel_project = root / "packages/guest-tools"
    (wheel_project / "src/guest_tools/observability").mkdir(parents=True)
    (wheel_project / "src/guest_tools/resources").mkdir(parents=True)
    (wheel_project / "src/guest_tools/__init__.py").write_text("\n")
    (wheel_project / "src/guest_tools/observability/__init__.py").write_text("\n")
    (wheel_project / "src/guest_tools/resources/guest-tools.toml").write_text(
        'guestHostname = "guest"\n'
    )
    (wheel_project / "src/guest_tools/observability/cli.py").write_text(
        "def main():\n    return 0\n"
    )
    (wheel_project / "src/guest_tools/observability/container_logs.py").write_text(
        "def main():\n    return 0\n"
    )
    (wheel_project / "pyproject.toml").write_text(
        "\n".join(
            [
                "[project]",
                'name = "guest-tools"',
                'version = "0.1.0"',
                'requires-python = ">=3.11"',
                "[project.scripts]",
                'guest-observe = "guest_tools.observability.cli:main"',
            ]
        )
    )
    (root / "docs").mkdir()
    (root / "docs/openapi.yaml").write_text("openapi\n")
    docker_bundle = tmp_path / "images.tar.gz"
    docker_bundle.write_text("images\n")
    optional_docker_bundle = tmp_path / "optional-images.tar.gz"
    optional_docker_bundle.write_text("optional-images\n")

    plan = guest_deploy_plan(
        root=root,
        runtime_dir=runtime_dir,
        deploy_dir=deploy_dir,
        vm_home=tmp_path / "vm-home",
        config=GuestDeployConfig(
            docker_image_bundle_destination=Path("docker-images/images.tar.gz"),
            optional_docker_image_bundle_destination=Path(
                "optional-docker-images/optional-images.tar.gz"
            ),
            python_wheel_destination=Path("python-wheels"),
            python_wheel_projects=[Path("packages/guest-tools")],
            includes=[
                GuestDeployInclude(
                    source=Path("apps/service"),
                    destination=Path("apps/service"),
                ),
                GuestDeployInclude(
                    source=Path("docs/openapi.yaml"),
                    destination=Path("docs/openapi.yaml"),
                ),
            ],
            optional_includes=[],
        ),
        docker_bundle=docker_bundle,
        optional_docker_bundle=optional_docker_bundle,
    )
    stage_guest_deploy(plan)

    assert (deploy_dir / "bootstrap.sh").read_text() == "bootstrap\n"
    assert (
        deploy_dir / "runtime-settings.json"
    ).read_text() == '{"recorderIngressSendDataMode":"spool_and_replay"}\n'
    assert (deploy_dir / "apps/service/app.py").read_text() == "service\n"
    assert (deploy_dir / "docs/openapi.yaml").read_text() == "openapi\n"
    assert not (wheel_project / "dist").exists()
    wheel = deploy_dir / "python-wheels/guest_tools-0.1.0-py3-none-any.whl"
    assert wheel.is_file()
    with ZipFile(wheel) as archive:
        archive_names = {info.filename for info in archive.infolist()}
        assert "guest_tools/observability/container_logs.py" in archive_names
        assert "guest_tools/resources/guest-tools.toml" in archive_names
    assert (deploy_dir / "docker-images/images.tar.gz").read_text() == "images\n"
    assert (
        deploy_dir / "optional-docker-images/optional-images.tar.gz"
    ).read_text() == "optional-images\n"


def test_stage_guest_deploy_stages_verified_runtime_wheelhouse(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    root = tmp_path / "repo"
    runtime_dir = root / "apps/runtime"
    deploy_dir = tmp_path / "deploy"
    (runtime_dir / "Support/Guest").mkdir(parents=True)
    (runtime_dir / "Support/Guest/bootstrap.sh").write_text("bootstrap\n")
    project = root / "packages/guest-tools"
    (project / "src/guest_tools").mkdir(parents=True)
    (project / "src/guest_tools/__init__.py").write_text("\n")
    (project / "pyproject.toml").write_text(
        "\n".join(
            [
                "[project]",
                'name = "guest-tools"',
                'version = "0.1.0"',
                'requires-python = ">=3.11"',
                'dependencies = ["SQLAlchemy==2.0.51"]',
            ]
        )
        + "\n",
        encoding="utf-8",
    )
    requirements = project / "requirements"
    requirements.mkdir()
    for target in ("linux-aarch64", "linux-amd64"):
        (requirements / f"guest-runtime-{target}.txt").write_text(
            "sqlalchemy==2.0.51 --hash=sha256:deadbeef\n",
            encoding="utf-8",
        )

    def fake_download(
        lock: Path,
        destination: Path,
        target: deploy_bundle.GuestRuntimeTarget,
    ) -> None:
        del lock
        target_name = target["platforms"][-1].replace("manylinux2014_", "")
        (destination / f"sqlalchemy-{target_name}.whl").write_bytes(b"wheel")

    monkeypatch.setattr(
        deploy_bundle,
        "download_guest_runtime_wheels",
        fake_download,
    )
    monkeypatch.setattr(
        deploy_bundle,
        "validate_guest_runtime_wheelhouse",
        lambda **_: None,
    )
    plan = guest_deploy_plan(
        root=root,
        runtime_dir=runtime_dir,
        deploy_dir=deploy_dir,
        vm_home=tmp_path / "vm-home",
        config=GuestDeployConfig(
            docker_image_bundle_destination=Path("images.tar"),
            optional_docker_image_bundle_destination=None,
            python_wheel_destination=Path("python-wheels"),
            python_wheel_projects=[Path("packages/guest-tools")],
            includes=[],
            optional_includes=[],
        ),
        docker_bundle=None,
    )

    stage_guest_deploy(plan)

    wheelhouse = deploy_dir / "python-wheels"
    assert not (project / "dist").exists()
    manifest = json.loads((wheelhouse / "manifest.json").read_text())
    assert manifest["guestPython"] == {"major": 3, "minor": 12}
    assert set(manifest["targets"]) == {"linux-aarch64", "linux-amd64"}
    requirements_text = (
        wheelhouse / manifest["targets"]["linux-amd64"]["requirementsPath"]
    ).read_text()
    assert requirements_text.startswith(
        "../guest-tools/guest_tools-0.1.0-py3-none-any.whl"
    )
    guest_wheel = wheelhouse / manifest["guestTools"]["path"]
    with ZipFile(guest_wheel) as archive:
        metadata = archive.read("guest_tools-0.1.0.dist-info/METADATA").decode()
    assert "Requires-Python: >=3.11" in metadata
    assert "Requires-Dist: SQLAlchemy==2.0.51" in metadata


def test_guest_runtime_wheelhouse_stages_declared_local_core_dependency(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    root = tmp_path / "repo"
    guest_project = root / "packages/guest-tools"
    core_project = root / "packages/vitalserver-core"
    for project, package_name, distribution_name in (
        (guest_project, "guest_tools", "guest-tools"),
        (core_project, "tirosh_vitalserver", "tirosh-vitalserver-core"),
    ):
        (project / f"src/{package_name}").mkdir(parents=True)
        (project / f"src/{package_name}/__init__.py").write_text("\n")
        dependencies = (
            '["SQLAlchemy==2.0.51", "tirosh-vitalserver-core"]'
            if project == guest_project
            else "[]"
        )
        (project / "pyproject.toml").write_text(
            "\n".join(
                [
                    "[project]",
                    f'name = "{distribution_name}"',
                    'version = "0.1.0"',
                    'requires-python = ">=3.12"',
                    f"dependencies = {dependencies}",
                ]
            )
            + "\n",
            encoding="utf-8",
        )
    requirements = guest_project / "requirements"
    requirements.mkdir()
    for target in ("linux-aarch64", "linux-amd64"):
        (requirements / f"guest-runtime-{target}.txt").write_text(
            "sqlalchemy==2.0.51 --hash=sha256:deadbeef\n",
            encoding="utf-8",
        )

    monkeypatch.setattr(
        deploy_bundle,
        "download_guest_runtime_wheels",
        lambda _lock, destination, _target: (
            destination / "sqlalchemy.whl"
        ).write_bytes(b"wheel"),
    )
    monkeypatch.setattr(
        deploy_bundle,
        "validate_guest_runtime_wheelhouse",
        lambda **_: None,
    )

    destination = tmp_path / "wheelhouse"
    deploy_bundle.stage_guest_python_wheelhouse(guest_project, destination)

    manifest = json.loads((destination / "manifest.json").read_text())
    assert [item["path"] for item in manifest["localDependencies"]] == [
        "guest-tools/tirosh_vitalserver_core-0.1.0-py3-none-any.whl"
    ]
    requirements_text = (
        destination / manifest["targets"]["linux-amd64"]["requirementsPath"]
    ).read_text()
    assert "../guest-tools/tirosh_vitalserver_core-0.1.0-py3-none-any.whl" in (
        requirements_text
    )


def test_guest_runtime_wheelhouse_validation_reports_missing_dependency(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    requirements = tmp_path / "linux-aarch64/requirements.txt"
    requirements.parent.mkdir(parents=True)
    requirements.write_text(
        "../guest-tools/guest_tools-0.1.0-py3-none-any.whl --hash=sha256:deadbeef\n",
        encoding="utf-8",
    )
    guest_tools_directory = tmp_path / "guest-tools"
    guest_tools_directory.mkdir()

    def fail_validation(command: list[str], **_: object) -> None:
        assert "--no-index" in command
        assert "--require-hashes" in command
        assert "manylinux_2_28_aarch64" in command
        raise deploy_bundle.subprocess.CalledProcessError(
            returncode=1,
            cmd=command,
            stderr="No matching distribution found for psycopg==3.3.4",
        )

    monkeypatch.setattr(deploy_bundle.subprocess, "run", fail_validation)

    with pytest.raises(
        SystemExit,
        match=(
            r"Guest Python runtime wheelhouse dependency closure is invalid.*"
            r"No matching distribution found for psycopg==3\.3\.4"
        ),
    ):
        deploy_bundle.validate_guest_runtime_wheelhouse(
            requirements=requirements,
            target_directory=requirements.parent,
            guest_tools_directory=guest_tools_directory,
            target=deploy_bundle.GUEST_RUNTIME_TARGETS["linux-aarch64"],
        )


def test_guest_runtime_wheelhouse_rejects_newer_python_syntax(
    tmp_path: Path,
) -> None:
    wheel = tmp_path / "guest_tools-0.2.0-py3-none-any.whl"
    with ZipFile(wheel, "w") as archive:
        archive.writestr(
            "tirosh_guest_tools/adapter.py",
            "try:\n    pass\nexcept ValueError, TypeError:\n    pass\n",
        )

    with pytest.raises(
        SystemExit,
        match=(
            r"not compatible with CPython 3\.12.*"
            r"module=tirosh_guest_tools/adapter\.py line=3"
        ),
    ):
        deploy_bundle.validate_guest_python_wheel_syntax(
            wheel,
            python_version="312",
        )


def test_guest_tools_runtime_installer_does_not_initialize_control_state() -> None:
    installer = GUEST_TOOLS_RUNTIME_INSTALLER.read_text(encoding="utf-8")

    assert "SQLiteControlRepository" not in installer
    assert ".migrate_schema(" not in installer
    assert '"controlStore"' not in installer


def test_guest_tools_runtime_installer_resolves_local_requirements_from_wheelhouse(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    spec = importlib.util.spec_from_file_location(
        "guest_tools_runtime_installer",
        GUEST_TOOLS_RUNTIME_INSTALLER,
    )
    assert spec is not None and spec.loader is not None
    installer = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(installer)
    requirements = tmp_path / "python-wheels/linux-aarch64/requirements.txt"
    requirements.parent.mkdir(parents=True)
    requirements.write_text(
        "../guest-tools/guest-tools-0.2.0-py3-none-any.whl "
        "--hash=sha256:" + "a" * 64 + "\n",
        encoding="utf-8",
    )
    guest_wheel = (
        tmp_path / "python-wheels/guest-tools/guest-tools-0.2.0-py3-none-any.whl"
    )
    guest_wheel.parent.mkdir(parents=True)
    guest_wheel.write_bytes(b"guest-tools-wheel")
    commands: list[tuple[list[str], object | None]] = []

    monkeypatch.setattr(installer, "read_manifest", lambda _: {})
    monkeypatch.setattr(installer, "guest_runtime_target", lambda: "linux-aarch64")
    monkeypatch.setattr(
        installer,
        "validate_wheelhouse",
        lambda *_args, **_kwargs: (requirements, guest_wheel),
    )
    monkeypatch.setattr(installer, "rewrite_entrypoint_shebangs", lambda **_: None)
    monkeypatch.setattr(
        installer,
        "installed_dependency_versions",
        lambda _: {"alembic": "1.16.5", "sqlalchemy": "2.0.51"},
    )
    monkeypatch.setattr(installer, "publish_venv", lambda **_: None)

    def record_run(command: list[str], **kwargs: object) -> None:
        commands.append((command, kwargs.get("cwd")))

    monkeypatch.setattr(installer.subprocess, "run", record_run)

    installer.install_guest_tools_runtime(
        wheel_dir=tmp_path / "python-wheels",
        guest_tools_home=tmp_path / "guest-tools-home",
    )

    pip_install = next(command for command in commands if "-r" in command[0])
    assert pip_install[1] == requirements.parent


def test_guest_tools_runtime_installer_rewrites_entrypoints_before_publish(
    tmp_path: Path,
) -> None:
    spec = importlib.util.spec_from_file_location(
        "guest_tools_runtime_installer",
        GUEST_TOOLS_RUNTIME_INSTALLER,
    )
    assert spec is not None and spec.loader is not None
    installer = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(installer)
    next_venv = tmp_path / "guest-tools/venv.next"
    current_venv = tmp_path / "guest-tools/venv"
    entrypoint = next_venv / "bin/tirosh-vitalserver-rootfs-smoke"
    entrypoint.parent.mkdir(parents=True)
    entrypoint.write_text(
        f"#!{next_venv / 'bin/python3.12'}\nprint('rootfs smoke')\n",
        encoding="utf-8",
    )

    installer.rewrite_entrypoint_shebangs(
        next_venv=next_venv,
        current_venv=current_venv,
    )

    assert entrypoint.read_text(encoding="utf-8").startswith(
        f"#!{current_venv / 'bin/python3.12'}\n"
    )


def test_guest_deploy_material_digest_excludes_only_run_scoped_contracts(
    tmp_path: Path,
) -> None:
    deploy = write_materialized_guest_deploy_source(tmp_path / "deploy")

    initial = deploy_bundle.guest_deploy_material_sha256(deploy)
    (deploy / "host-time.json").write_text(
        '{"updatedAt":"2026-06-11T00:00:01Z"}\n',
        encoding="utf-8",
    )
    metadata_path = deploy / "build-metadata/rootfs-input.json"
    metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
    metadata["guestClockUtc"] = "2026-06-11T00:00:02Z"
    metadata["runId"] = "new-run"
    metadata["runtimeBootSmoke"] = {"enabled": True, "runId": "smoke-run"}
    metadata_path.write_text(json.dumps(metadata), encoding="utf-8")

    assert deploy_bundle.guest_deploy_material_sha256(deploy) == initial

    (deploy / "bootstrap.sh").write_text("changed\n", encoding="utf-8")

    assert deploy_bundle.guest_deploy_material_sha256(deploy) != initial


def test_guest_deploy_material_digest_binds_rootfs_static_metadata(
    tmp_path: Path,
) -> None:
    deploy = write_materialized_guest_deploy_source(tmp_path / "deploy")
    initial = deploy_bundle.guest_deploy_material_sha256(deploy)
    metadata_path = deploy / "build-metadata/rootfs-input.json"
    metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
    metadata["ubuntu"]["aptSnapshot"] = "20260611T000000Z"
    metadata_path.write_text(json.dumps(metadata), encoding="utf-8")

    assert deploy_bundle.guest_deploy_material_sha256(deploy) != initial


def test_guest_deploy_material_digest_ignores_finder_metadata(
    tmp_path: Path,
) -> None:
    deploy = write_materialized_guest_deploy_source(tmp_path / "deploy")
    initial = deploy_bundle.guest_deploy_material_sha256(deploy)
    (deploy / ".DS_Store").write_bytes(b"root finder metadata")
    nested = deploy / "build-metadata/__pycache__"
    nested.mkdir(parents=True)
    (nested / "module.pyc").write_bytes(b"cache")
    (deploy / "build-metadata/._rootfs-input.json").write_bytes(b"apple double")

    assert deploy_bundle.guest_deploy_material_sha256(deploy) == initial


def test_guest_deploy_material_digest_rejects_symlink(
    tmp_path: Path,
) -> None:
    deploy = write_materialized_guest_deploy_source(tmp_path / "deploy")
    (deploy / "unsafe-link").symlink_to(deploy / "bootstrap.sh")

    with pytest.raises(SystemExit, match="must not contain symlinks"):
        deploy_bundle.guest_deploy_material_sha256(deploy)


def test_guest_deploy_material_digest_rejects_missing_rootfs_input_metadata(
    tmp_path: Path,
) -> None:
    deploy = tmp_path / "deploy"
    deploy.mkdir()

    with pytest.raises(SystemExit, match="missing rootfs input metadata"):
        deploy_bundle.guest_deploy_material_sha256(deploy)


def test_stage_materialized_guest_deploy_removes_volatile_contracts(
    tmp_path: Path,
) -> None:
    source = write_materialized_guest_deploy_source(tmp_path / "compiled-deploy")
    (source / ".DS_Store").write_bytes(b"finder metadata")
    (source / "vendor").mkdir()
    (source / "vendor/.DS_Store").write_bytes(b"finder metadata")
    destination = tmp_path / "package/deploy"

    deploy_bundle.stage_materialized_guest_deploy(source, destination)

    assert (destination / "bootstrap.sh").read_text(encoding="utf-8") == "#!/bin/sh\n"
    assert not (destination / "host-time.json").exists()
    assert not (destination / "build-metadata/rootfs-input.json").exists()
    assert not (destination / ".DS_Store").exists()
    assert not (destination / "vendor/.DS_Store").exists()


def test_stage_materialized_guest_deploy_rejects_same_path(tmp_path: Path) -> None:
    source = write_materialized_guest_deploy_source(tmp_path / "compiled-deploy")

    with pytest.raises(SystemExit, match="source and destination must not overlap"):
        deploy_bundle.stage_materialized_guest_deploy(source, source)


def test_stage_materialized_guest_deploy_rejects_nested_destination(
    tmp_path: Path,
) -> None:
    source = write_materialized_guest_deploy_source(tmp_path / "compiled-deploy")

    with pytest.raises(SystemExit, match="source and destination must not overlap"):
        deploy_bundle.stage_materialized_guest_deploy(source, source / "nested")


def write_materialized_guest_deploy_source(deploy: Path) -> Path:
    (deploy / "build-metadata").mkdir(parents=True)
    (deploy / "build-metadata/rootfs-input.json").write_text(
        json.dumps(
            {
                "schemaVersion": 1,
                "guestClockUtc": "2026-06-11T00:00:00Z",
                "runtimeBootSmoke": {"enabled": False},
                "dockerImages": {"platform": "linux/arm64"},
                "runtimeData": {
                    "diskImageName": "runtime-data.img",
                    "diskSize": "16G",
                    "filesystemLabel": "vital-runtime",
                    "mountPath": "/mnt/runtime",
                    "dockerDataRoot": "/mnt/runtime/docker",
                    "containerdRoot": "/mnt/runtime/containerd",
                },
                "ubuntu": {
                    "aptSnapshot": "20250515T000000Z",
                    "baseUrl": "https://example.invalid/noble",
                    "cacheKey": "noble-example",
                },
            }
        )
        + "\n",
        encoding="utf-8",
    )
    (deploy / "host-time.json").write_text(
        '{"updatedAt":"2026-06-11T00:00:00Z"}\n',
        encoding="utf-8",
    )
    (deploy / "bootstrap.sh").write_text("#!/bin/sh\n", encoding="utf-8")
    return deploy


def test_guest_tools_runtime_installer_requires_hash_pinned_manifest_wheel_closure(
    tmp_path: Path,
) -> None:
    spec = importlib.util.spec_from_file_location(
        "guest_tools_runtime_installer",
        GUEST_TOOLS_RUNTIME_INSTALLER,
    )
    assert spec is not None and spec.loader is not None
    installer = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(installer)
    requirements = tmp_path / "requirements.txt"
    guest_hash = "a" * 64
    dependency_hash = "b" * 64
    requirements.write_text(
        f"guest-tools==0.1.0 \\\n  --hash=sha256:{guest_hash}\n",
        encoding="utf-8",
    )

    with pytest.raises(
        installer.GuestToolsInstallError,
        match="requirements do not pin every manifest wheel",
    ):
        installer.require_requirements_hash_closure(
            requirements,
            {guest_hash, dependency_hash},
        )


def test_guest_tools_runtime_installer_includes_local_dependency_manifest_wheels(
    tmp_path: Path,
) -> None:
    spec = importlib.util.spec_from_file_location(
        "guest_tools_runtime_installer_local_dependencies",
        GUEST_TOOLS_RUNTIME_INSTALLER,
    )
    assert spec is not None and spec.loader is not None
    installer = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(installer)

    guest_tools_directory = tmp_path / "guest-tools"
    target_directory = tmp_path / "linux-aarch64"
    guest_tools_directory.mkdir()
    target_directory.mkdir()
    guest_wheel = guest_tools_directory / "guest_tools-0.1.0-py3-none-any.whl"
    local_wheel = guest_tools_directory / "core-0.1.0-py3-none-any.whl"
    target_wheel = target_directory / "dependency-0.1.0-py3-none-any.whl"
    guest_wheel.write_bytes(b"guest tools")
    local_wheel.write_bytes(b"local dependency")
    target_wheel.write_bytes(b"target dependency")
    requirements = target_directory / "requirements.txt"
    requirements.write_text(
        "\n".join(
            (
                "../guest-tools/" + guest_wheel.name + " --hash=sha256:"
                + installer.file_sha256(guest_wheel),
                "../guest-tools/" + local_wheel.name + " --hash=sha256:"
                + installer.file_sha256(local_wheel),
                target_wheel.name + " --hash=sha256:"
                + installer.file_sha256(target_wheel),
            )
        )
        + "\n",
        encoding="utf-8",
    )
    manifest = {
        "guestTools": {
            "path": guest_wheel.relative_to(tmp_path).as_posix(),
            "sha256": installer.file_sha256(guest_wheel),
        },
        "localDependencies": [
            {
                "path": local_wheel.relative_to(tmp_path).as_posix(),
                "sha256": installer.file_sha256(local_wheel),
            }
        ],
        "targets": {
            "linux-aarch64": {
                "requirementsPath": requirements.relative_to(tmp_path).as_posix(),
                "requirementsSHA256": installer.file_sha256(requirements),
                "wheels": [
                    {
                        "path": target_wheel.name,
                        "sha256": installer.file_sha256(target_wheel),
                    }
                ],
            }
        },
    }

    actual_requirements, actual_guest_wheel = installer.validate_wheelhouse(
        tmp_path,
        manifest,
        target="linux-aarch64",
    )

    assert actual_requirements == requirements
    assert actual_guest_wheel == guest_wheel


def test_guest_tools_runtime_installer_ignores_hashes_in_inline_comments(
    tmp_path: Path,
) -> None:
    spec = importlib.util.spec_from_file_location(
        "guest_tools_runtime_installer",
        GUEST_TOOLS_RUNTIME_INSTALLER,
    )
    assert spec is not None and spec.loader is not None
    installer = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(installer)
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
        installer.GuestToolsInstallError,
        match="requirements do not pin every manifest wheel",
    ):
        installer.require_requirements_hash_closure(
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
def test_guest_tools_runtime_installer_matches_pip_requirement_preprocessing(
    tmp_path: Path,
    requirements_text: str,
    match: str,
) -> None:
    spec = importlib.util.spec_from_file_location(
        "guest_tools_runtime_installer",
        GUEST_TOOLS_RUNTIME_INSTALLER,
    )
    assert spec is not None and spec.loader is not None
    installer = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(installer)
    requirements = tmp_path / "requirements.txt"
    guest_hash = "a" * 64
    requirements.write_text(
        requirements_text.format(hash=guest_hash),
        encoding="utf-8",
    )

    with pytest.raises(installer.GuestToolsInstallError, match=match):
        installer.require_requirements_hash_closure(requirements, {guest_hash})
