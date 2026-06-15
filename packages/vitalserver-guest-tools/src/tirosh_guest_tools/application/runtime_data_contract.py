from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class RuntimeDataContract:
    disk_image_name: str
    disk_size: str
    filesystem_label: str
    mount_path: str
    docker_data_root: str
    containerd_root: str


def prepare_runtime_data_directories(contract: RuntimeDataContract) -> None:
    docker_data_root = Path(contract.docker_data_root)
    docker_data_root.mkdir(parents=True, exist_ok=True)
    (docker_data_root / "tmp").mkdir(parents=True, exist_ok=True)
    Path(contract.containerd_root).mkdir(parents=True, exist_ok=True)
