from __future__ import annotations

import base64
import hashlib
import json
import shutil
import tomllib
import zipfile
from email.message import Message
from pathlib import Path
from tempfile import TemporaryDirectory

from tirosh_vitalserver.devtools.core.guest_services import (
    IGNORED_NAMES,
    GuestDeployPlan,
    GuestPythonWheelProject,
    RootfsInputMetadataPlan,
    rootfs_input_metadata_document,
)


def stage_guest_deploy(plan: GuestDeployPlan) -> None:
    copy_tree(plan.support_guest_source, plan.deploy_dir, merge=True)
    for entry in plan.includes:
        if entry.source.is_dir():
            copy_tree(entry.source, entry.destination)
        elif entry.source.is_file():
            copy_file(entry.source, entry.destination)
        else:
            raise SystemExit(f"error: missing guest deploy include: {entry.source}")
    for project in plan.python_wheel_projects:
        stage_python_wheel(project)
    if plan.docker_bundle_source and plan.docker_bundle_destination:
        copy_file(plan.docker_bundle_source, plan.docker_bundle_destination)
    if (
        plan.optional_docker_bundle_source
        and plan.optional_docker_bundle_destination
        and plan.optional_docker_bundle_source.is_file()
    ):
        copy_file(
            plan.optional_docker_bundle_source,
            plan.optional_docker_bundle_destination,
        )


def stage_rootfs_input_metadata(plan: RootfsInputMetadataPlan) -> None:
    metadata = plan.deploy_dir / "build-metadata" / "rootfs-input.json"
    metadata.parent.mkdir(parents=True, exist_ok=True)
    metadata.write_text(
        json.dumps(rootfs_input_metadata_document(plan), indent=2, sort_keys=True)
        + "\n",
        encoding="utf-8",
    )


def ensure_vm_data_dirs(plan: GuestDeployPlan) -> None:
    for directory in plan.vm_data_dirs:
        directory.mkdir(parents=True, exist_ok=True)


def copy_tree(source: Path, destination: Path, *, merge: bool = False) -> None:
    if not source.is_dir():
        raise SystemExit(f"error: missing directory: {source}")
    if destination.exists() and not merge:
        shutil.rmtree(destination)
    shutil.copytree(
        source,
        destination,
        dirs_exist_ok=merge,
        ignore=shutil.ignore_patterns(*IGNORED_NAMES),
    )


def copy_file(source: Path, destination: Path) -> None:
    if not source.is_file():
        raise SystemExit(f"error: missing file: {source}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, destination)


def stage_python_wheel(project: GuestPythonWheelProject) -> None:
    wheel = build_pure_python_wheel(project.source)
    project.destination_directory.mkdir(parents=True, exist_ok=True)
    shutil.copy2(wheel, project.destination_directory / wheel.name)


def build_pure_python_wheel(project: Path) -> Path:
    pyproject = project / "pyproject.toml"
    package_root = project / "src"
    if not pyproject.is_file():
        raise SystemExit(f"error: missing Python project metadata: {pyproject}")
    if not package_root.is_dir():
        raise SystemExit(f"error: missing Python package src directory: {package_root}")

    with pyproject.open("rb") as handle:
        metadata = tomllib.load(handle)
    project_metadata = metadata.get("project")
    if not isinstance(project_metadata, dict):
        raise SystemExit(f"error: missing [project] metadata: {pyproject}")
    name = required_metadata(project_metadata, "name", pyproject)
    version = required_metadata(project_metadata, "version", pyproject)
    description = str(project_metadata.get("description", ""))
    scripts = project_metadata.get("scripts", {})
    if not isinstance(scripts, dict):
        raise SystemExit(f"error: invalid [project.scripts] metadata: {pyproject}")

    distribution = normalize_distribution_name(name)
    wheel_name = f"{distribution}-{version}-py3-none-any.whl"
    dist_info = f"{distribution}-{version}.dist-info"
    with TemporaryDirectory() as temp_dir:
        wheel = Path(temp_dir) / wheel_name
        records: list[tuple[str, str, str]] = []
        with zipfile.ZipFile(wheel, "w", compression=zipfile.ZIP_DEFLATED) as archive:
            for source in sorted(package_root.rglob("*")):
                if not source.is_file() or "__pycache__" in source.parts:
                    continue
                relative = source.relative_to(package_root).as_posix()
                write_archive_file(archive, records, relative, source.read_bytes())
            write_archive_file(
                archive,
                records,
                f"{dist_info}/METADATA",
                package_metadata(
                    name=name,
                    version=version,
                    description=description,
                ).encode(),
            )
            write_archive_file(
                archive,
                records,
                f"{dist_info}/WHEEL",
                b"Wheel-Version: 1.0\nGenerator: vitalserver-devtools\n"
                b"Root-Is-Purelib: true\nTag: py3-none-any\n",
            )
            if scripts:
                write_archive_file(
                    archive,
                    records,
                    f"{dist_info}/entry_points.txt",
                    entry_points(scripts).encode(),
                )
            record_path = f"{dist_info}/RECORD"
            archive.writestr(record_path, record_contents(records, record_path))
        output = project / "dist" / wheel_name
        output.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(wheel, output)
        return output


def write_archive_file(
    archive: zipfile.ZipFile,
    records: list[tuple[str, str, str]],
    path: str,
    content: bytes,
) -> None:
    archive.writestr(path, content)
    digest = base64.urlsafe_b64encode(hashlib.sha256(content).digest()).rstrip(b"=")
    records.append((path, f"sha256={digest.decode()}", str(len(content))))


def record_contents(records: list[tuple[str, str, str]], record_path: str) -> str:
    rows = [*records, (record_path, "", "")]
    output: list[str] = []
    for row in rows:
        output.append(",".join(csv_escape(item) for item in row))
    return "\n".join(output) + "\n"


def csv_escape(value: str) -> str:
    if any(character in value for character in [",", '"', "\n"]):
        return '"' + value.replace('"', '""') + '"'
    return value


def required_metadata(metadata: dict[object, object], key: str, pyproject: Path) -> str:
    value = metadata.get(key)
    if not isinstance(value, str) or not value:
        raise SystemExit(f"error: missing project.{key}: {pyproject}")
    return value


def normalize_distribution_name(name: str) -> str:
    return name.replace("-", "_").replace(".", "_")


def package_metadata(*, name: str, version: str, description: str) -> str:
    message = Message()
    message["Metadata-Version"] = "2.1"
    message["Name"] = name
    message["Version"] = version
    if description:
        message["Summary"] = description
    return message.as_string()


def entry_points(scripts: dict[object, object]) -> str:
    lines = ["[console_scripts]"]
    for name, target in sorted(scripts.items()):
        if not isinstance(name, str) or not isinstance(target, str):
            raise SystemExit("error: invalid project script metadata")
        lines.append(f"{name} = {target}")
    return "\n".join(lines) + "\n"
