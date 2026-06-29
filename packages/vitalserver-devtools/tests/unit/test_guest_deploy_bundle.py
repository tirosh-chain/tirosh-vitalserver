from __future__ import annotations

from pathlib import Path
from zipfile import ZipFile

from tirosh_vitalserver.devtools.adapters.guest_services.deploy_bundle import (
    stage_guest_deploy,
)
from tirosh_vitalserver.devtools.core.guest_deploy import (
    GuestDeployConfig,
    GuestDeployInclude,
)
from tirosh_vitalserver.devtools.core.guest_services import guest_deploy_plan


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
