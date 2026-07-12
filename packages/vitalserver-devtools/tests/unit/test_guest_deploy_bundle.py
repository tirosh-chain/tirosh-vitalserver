from __future__ import annotations

import importlib.util
import json
from pathlib import Path
from zipfile import ZipFile

import pytest

from tirosh_vitalserver.devtools.adapters.guest_services import deploy_bundle
from tirosh_vitalserver.devtools.adapters.guest_services.deploy_bundle import (
    stage_guest_deploy,
)
from tirosh_vitalserver.devtools.core.guest_deploy import (
    GuestDeployConfig,
    GuestDeployInclude,
)
from tirosh_vitalserver.devtools.core.guest_services import guest_deploy_plan

ROOT = Path(__file__).resolve().parents[4]
GUEST_TOOLS_RUNTIME_INSTALLER = (
    ROOT / "apps/vitalserver-macos-runtime/Support/Guest/install-guest-tools-runtime.py"
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
        "guestHostname = \"guest\"\n"
    )
    (wheel_project / "src/guest_tools/observability/cli.py").write_text(
        "def main():\n    return 0\n"
    )
    (
        wheel_project / "src/guest_tools/observability/container_logs.py"
    ).write_text("def main():\n    return 0\n")
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
        target: dict[str, str],
    ) -> None:
        del lock
        target_name = target["platform"].replace("manylinux2014_", "")
        (destination / f"sqlalchemy-{target_name}.whl").write_bytes(b"wheel")

    monkeypatch.setattr(
        deploy_bundle,
        "download_guest_runtime_wheels",
        fake_download,
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


def test_guest_tools_runtime_installer_does_not_initialize_control_state() -> None:
    installer = GUEST_TOOLS_RUNTIME_INSTALLER.read_text(encoding="utf-8")

    assert "SQLiteControlRepository" not in installer
    assert ".migrate_schema(" not in installer
    assert '"controlStore"' not in installer


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
        "guest-tools==0.1.0 \\\n"
        f"  --hash=sha256:{guest_hash}\n",
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
