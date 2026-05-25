from __future__ import annotations

from pathlib import Path

from tirosh_vitalserver.devtools.config.guest_deploy import (
    GuestDeployConfig,
    GuestDeployInclude,
)
from tirosh_vitalserver.devtools.guest_services.deploy_bundle import stage_guest_deploy


def test_stage_guest_deploy_uses_configured_includes(tmp_path: Path) -> None:
    root = tmp_path / "repo"
    runtime_dir = root / "apps/runtime"
    deploy_dir = tmp_path / "vm-home/data/deploy"
    (runtime_dir / "Support/Guest").mkdir(parents=True)
    (runtime_dir / "Support/Guest/bootstrap.sh").write_text("bootstrap\n")
    (root / "apps/service").mkdir(parents=True)
    (root / "apps/service/app.py").write_text("service\n")
    (root / "docs").mkdir()
    (root / "docs/openapi.yaml").write_text("openapi\n")
    docker_bundle = tmp_path / "images.tar.gz"
    docker_bundle.write_text("images\n")

    stage_guest_deploy(
        root=root,
        runtime_dir=runtime_dir,
        deploy_dir=deploy_dir,
        config=GuestDeployConfig(
            docker_image_bundle_destination=Path("docker-images/images.tar.gz"),
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
        ),
        docker_bundle=docker_bundle,
    )

    assert (deploy_dir / "bootstrap.sh").read_text() == "bootstrap\n"
    assert (deploy_dir / "apps/service/app.py").read_text() == "service\n"
    assert (deploy_dir / "docs/openapi.yaml").read_text() == "openapi\n"
    assert (deploy_dir / "docker-images/images.tar.gz").read_text() == "images\n"
