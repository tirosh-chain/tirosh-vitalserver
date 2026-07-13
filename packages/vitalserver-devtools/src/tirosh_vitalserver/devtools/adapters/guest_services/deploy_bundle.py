from __future__ import annotations

import base64
import hashlib
import importlib.util
import json
import shutil
import stat
import subprocess
import sys
import tomllib
import zipfile
from email.message import Message
from pathlib import Path
from tempfile import TemporaryDirectory
from typing import TypedDict

from tirosh_vitalserver.devtools.core.guest_services import (
    IGNORED_NAMES,
    GuestDeployPlan,
    GuestPythonWheelProject,
    RootfsInputMetadataPlan,
    rootfs_input_material_document,
    rootfs_input_metadata_document,
)

GUEST_DEPLOY_MATERIAL_DIGEST_VERSION = 2
ROOTFS_INPUT_METADATA_RELATIVE_PATH = "build-metadata/rootfs-input.json"
GUEST_DEPLOY_MATERIAL_EXCLUDED_PATHS = frozenset(
    {
        "host-time.json",
    }
)
GUEST_DEPLOY_MATERIAL_REGENERATED_PATHS = (
    GUEST_DEPLOY_MATERIAL_EXCLUDED_PATHS | {ROOTFS_INPUT_METADATA_RELATIVE_PATH}
)


def stage_materialized_guest_deploy(source: Path, destination: Path) -> None:
    """Stage the exact deploy material compiled into a golden rootfs.

    Host time and rootfs input metadata are intentionally not carried forward.
    The caller owns fresh contracts for its own run.
    """

    guest_deploy_material_sha256(source)
    resolved_source = source.resolve()
    resolved_destination = destination.resolve(strict=False)
    if (
        resolved_source == resolved_destination
        or resolved_source.is_relative_to(resolved_destination)
        or resolved_destination.is_relative_to(resolved_source)
    ):
        raise SystemExit(
            "error: compiled Guest deploy source and destination must not overlap: "
            f"source={source} destination={destination}"
        )
    if destination.is_symlink():
        raise SystemExit(
            "error: compiled Guest deploy destination must not be a symlink: "
            f"{destination}"
        )
    if destination.exists() and not destination.is_dir():
        raise SystemExit(
            "error: compiled Guest deploy destination is not a directory: "
            f"{destination}"
        )
    if destination.exists():
        shutil.rmtree(destination)
    shutil.copytree(source, destination)
    for relative_path in GUEST_DEPLOY_MATERIAL_REGENERATED_PATHS:
        volatile_contract = destination / relative_path
        if volatile_contract.exists():
            if (
                not volatile_contract.is_file()
                or volatile_contract.is_symlink()
            ):
                raise SystemExit(
                    "error: staged volatile Guest deploy contract is unsafe: "
                    f"{volatile_contract}"
                )
            volatile_contract.unlink()
    metadata_dir = destination / "build-metadata"
    if metadata_dir.exists() and not any(metadata_dir.iterdir()):
        metadata_dir.rmdir()


def guest_deploy_material_sha256(deploy_dir: Path) -> str:
    """Return a stable digest for Guest deploy material, excluding volatile contracts.

    The deploy directory is a release input, not an arbitrary archive. Symlinks,
    special files, and a missing rootfs input contract are rejected instead of
    being ignored or followed.
    """

    require_guest_deploy_directory(deploy_dir)
    rootfs_input_material = require_rootfs_input_metadata(deploy_dir)
    try:
        entries = sorted(
            deploy_dir.rglob("*"),
            key=lambda path: path.relative_to(deploy_dir).as_posix(),
        )
    except OSError as error:
        raise SystemExit(
            f"error: Guest deploy material is unreadable: {deploy_dir}: {error}"
        ) from error

    digest = hashlib.sha256()
    digest.update(
        f"vitalserver-guest-deploy-material-v{GUEST_DEPLOY_MATERIAL_DIGEST_VERSION}\n".encode()
    )
    for path in entries:
        relative_path = path.relative_to(deploy_dir).as_posix()
        require_safe_guest_deploy_relative_path(relative_path, deploy_dir)
        try:
            file_status = path.lstat()
        except OSError as error:
            raise SystemExit(
                "error: Guest deploy material entry is unreadable: "
                f"{path}: {error}"
            ) from error
        if stat.S_ISLNK(file_status.st_mode):
            raise SystemExit(
                "error: Guest deploy material must not contain symlinks: "
                f"{path}"
            )
        if relative_path == ROOTFS_INPUT_METADATA_RELATIVE_PATH:
            if not stat.S_ISREG(file_status.st_mode):
                raise SystemExit(
                    "error: Guest deploy rootfs input metadata is not a regular file: "
                    f"{path}"
                )
            digest_guest_deploy_entry(
                digest,
                {
                    "contract": rootfs_input_material,
                    "path": relative_path,
                    "type": "rootfs-input-metadata",
                },
            )
            continue
        if relative_path in GUEST_DEPLOY_MATERIAL_EXCLUDED_PATHS:
            if not stat.S_ISREG(file_status.st_mode):
                raise SystemExit(
                    "error: volatile Guest deploy contract is not a regular file: "
                    f"{path}"
                )
            continue
        if stat.S_ISDIR(file_status.st_mode):
            digest_guest_deploy_entry(
                digest,
                {
                    "mode": stat.S_IMODE(file_status.st_mode),
                    "path": relative_path,
                    "type": "directory",
                },
            )
            continue
        if stat.S_ISREG(file_status.st_mode):
            digest_guest_deploy_entry(
                digest,
                {
                    "bytes": file_status.st_size,
                    "mode": stat.S_IMODE(file_status.st_mode),
                    "path": relative_path,
                    "sha256": sha256_file(path),
                    "type": "file",
                },
            )
            continue
        raise SystemExit(
            "error: Guest deploy material must contain only regular files and "
            f"directories: {path}"
        )
    return digest.hexdigest()


def require_guest_deploy_directory(deploy_dir: Path) -> None:
    try:
        status = deploy_dir.lstat()
    except FileNotFoundError as error:
        raise SystemExit(
            f"error: Guest deploy material is missing: {deploy_dir}"
        ) from error
    except OSError as error:
        raise SystemExit(
            f"error: Guest deploy material is unreadable: {deploy_dir}: {error}"
        ) from error
    if stat.S_ISLNK(status.st_mode):
        raise SystemExit(
            f"error: Guest deploy material must not be a symlink: {deploy_dir}"
        )
    if not stat.S_ISDIR(status.st_mode):
        raise SystemExit(
            f"error: Guest deploy material is not a directory: {deploy_dir}"
        )


def require_rootfs_input_metadata(deploy_dir: Path) -> dict[str, object]:
    metadata = deploy_dir / ROOTFS_INPUT_METADATA_RELATIVE_PATH
    try:
        status = metadata.lstat()
    except FileNotFoundError as error:
        raise SystemExit(
            "error: Guest deploy material is missing rootfs input metadata: "
            f"{metadata}"
        ) from error
    except OSError as error:
        raise SystemExit(
            "error: Guest deploy rootfs input metadata is unreadable: "
            f"{metadata}: {error}"
        ) from error
    if stat.S_ISLNK(status.st_mode) or not stat.S_ISREG(status.st_mode):
        raise SystemExit(
            "error: Guest deploy rootfs input metadata is not a regular file: "
            f"{metadata}"
        )
    try:
        document = json.loads(metadata.read_text(encoding="utf-8"))
    except OSError as error:
        raise SystemExit(
            "error: Guest deploy rootfs input metadata is unreadable: "
            f"{metadata}: {error}"
        ) from error
    except json.JSONDecodeError as error:
        raise SystemExit(
            "error: Guest deploy rootfs input metadata is invalid JSON: "
            f"{metadata}: {error}"
        ) from error
    if not isinstance(document, dict):
        raise SystemExit(
            "error: Guest deploy rootfs input metadata must be an object: "
            f"{metadata}"
        )
    try:
        return rootfs_input_material_document(document)
    except ValueError as error:
        raise SystemExit(
            "error: Guest deploy rootfs input metadata has invalid material "
            f"contract: {metadata}: {error}"
        ) from error


def require_safe_guest_deploy_relative_path(
    relative_path: str,
    deploy_dir: Path,
) -> None:
    parts = relative_path.split("/")
    if not relative_path or any(part in {"", ".", ".."} for part in parts):
        raise SystemExit(
            "error: Guest deploy material contains an unsafe relative path: "
            f"{deploy_dir / relative_path}"
        )


def digest_guest_deploy_entry(
    digest: hashlib._Hash,
    entry: dict[str, object],
) -> None:
    digest.update(
        json.dumps(entry, sort_keys=True, separators=(",", ":")).encode("utf-8")
        + b"\n"
    )


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    try:
        with path.open("rb") as handle:
            for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                digest.update(chunk)
    except OSError as error:
        raise SystemExit(
            f"error: Guest deploy material file is unreadable: {path}: {error}"
        ) from error
    return digest.hexdigest()


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
    with TemporaryDirectory(prefix="tirosh-guest-wheel-") as temporary:
        wheel = build_pure_python_wheel(project.source, Path(temporary))
        if project_runtime_dependencies(project.source):
            stage_guest_python_wheelhouse(
                project.source,
                project.destination_directory,
                wheel=wheel,
            )
            return
        project.destination_directory.mkdir(parents=True, exist_ok=True)
        shutil.copy2(wheel, project.destination_directory / wheel.name)


class GuestRuntimeTarget(TypedDict):
    platforms: tuple[str, ...]
    python_version: str
    implementation: str
    abi: str


GUEST_RUNTIME_TARGETS: dict[str, GuestRuntimeTarget] = {
    "linux-aarch64": {
        "platforms": (
            "manylinux_2_28_aarch64",
            "manylinux2014_aarch64",
        ),
        "python_version": "312",
        "implementation": "cp",
        "abi": "cp312",
    },
    "linux-amd64": {
        "platforms": ("manylinux2014_x86_64",),
        "python_version": "312",
        "implementation": "cp",
        "abi": "cp312",
    },
}


def stage_guest_python_wheelhouse(
    project: Path,
    destination: Path,
    *,
    targets: tuple[str, ...] = ("linux-aarch64", "linux-amd64"),
    wheel: Path | None = None,
) -> None:
    if not project_runtime_dependencies(project):
        raise SystemExit(
            "error: Guest Python runtime wheelhouse requires project dependencies: "
            f"{project}"
        )
    if not targets:
        raise SystemExit("error: Guest Python runtime wheelhouse requires a target")

    if wheel is None:
        with TemporaryDirectory(prefix="tirosh-guest-wheel-") as temporary:
            built_wheel = build_pure_python_wheel(project, Path(temporary))
            stage_guest_python_wheelhouse(
                project,
                destination,
                targets=targets,
                wheel=built_wheel,
            )
        return
    built_wheel = wheel
    guest_tools_directory = destination / "guest-tools"
    reset_generated_wheel_directory(guest_tools_directory)
    staged_guest_wheel = guest_tools_directory / built_wheel.name
    shutil.copy2(built_wheel, staged_guest_wheel)
    guest_wheel_identity = file_identity(staged_guest_wheel)

    target_documents: dict[str, object] = {}
    for target in targets:
        target_config = GUEST_RUNTIME_TARGETS.get(target)
        if target_config is None:
            raise SystemExit(
                f"error: unsupported Guest Python runtime target: {target}"
            )
        lock = project / "requirements" / f"guest-runtime-{target}.txt"
        if not lock.is_file():
            raise SystemExit(f"error: missing Guest runtime dependency lock: {lock}")
        target_directory = destination / target
        reset_generated_wheel_directory(target_directory)
        download_guest_runtime_wheels(lock, target_directory, target_config)
        ensure_only_wheels(target_directory)
        requirements = target_directory / "requirements.txt"
        requirements.write_text(
            "../guest-tools/"
            + staged_guest_wheel.name
            + " --hash=sha256:"
            + str(guest_wheel_identity["sha256"])
            + "\n"
            + lock.read_text(encoding="utf-8"),
            encoding="utf-8",
        )
        validate_guest_runtime_wheelhouse(
            requirements=requirements,
            target_directory=target_directory,
            guest_tools_directory=guest_tools_directory,
            target=target_config,
        )
        target_documents[target] = {
            "requirementsPath": requirements.relative_to(destination).as_posix(),
            "requirementsSHA256": file_identity(requirements)["sha256"],
            "wheels": [
                {
                    "path": item.name,
                    **file_identity(item),
                }
                for item in sorted(target_directory.glob("*.whl"))
            ],
        }

    manifest = {
        "schemaVersion": 1,
        "guestPython": {"major": 3, "minor": 12},
        "guestTools": {
            "path": staged_guest_wheel.relative_to(destination).as_posix(),
            **guest_wheel_identity,
        },
        "targets": target_documents,
    }
    (destination / "manifest.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def download_guest_runtime_wheels(
    lock: Path,
    destination: Path,
    target: GuestRuntimeTarget,
) -> None:
    command = [
        *host_pip_command(),
        "download",
        "--dest",
        str(destination),
        "--only-binary=:all:",
        "--require-hashes",
        *guest_runtime_pip_target_arguments(target),
        "-r",
        str(lock),
    ]
    try:
        subprocess.run(command, check=True, capture_output=True, text=True)
    except subprocess.CalledProcessError as error:
        output = "\n".join(
            item for item in (error.stdout, error.stderr) if item
        ).strip()
        suffix = f"\n{output}" if output else ""
        raise SystemExit(
            "error: failed to stage Guest Python runtime wheelhouse "
            f"lock={lock}{suffix}"
        ) from error


def validate_guest_runtime_wheelhouse(
    *,
    requirements: Path,
    target_directory: Path,
    guest_tools_directory: Path,
    target: GuestRuntimeTarget,
) -> None:
    with TemporaryDirectory(prefix="tirosh-guest-wheel-validation-") as temporary:
        command = [
            *host_pip_command(),
            "download",
            "--dest",
            temporary,
            "--no-index",
            "--find-links",
            str(target_directory),
            "--find-links",
            str(guest_tools_directory),
            "--only-binary=:all:",
            "--require-hashes",
            *guest_runtime_pip_target_arguments(target),
            "-r",
            str(requirements),
        ]
        try:
            subprocess.run(
                command,
                check=True,
                capture_output=True,
                text=True,
                cwd=requirements.parent,
            )
        except subprocess.CalledProcessError as error:
            output = "\n".join(
                item for item in (error.stdout, error.stderr) if item
            ).strip()
            suffix = f": {output}" if output else ""
            raise SystemExit(
                "error: Guest Python runtime wheelhouse dependency closure is "
                f"invalid: requirements={requirements} "
                f"platforms={','.join(target['platforms'])}{suffix}"
            ) from error


def guest_runtime_pip_target_arguments(target: GuestRuntimeTarget) -> list[str]:
    platform_arguments = [
        argument
        for platform in target["platforms"]
        for argument in ("--platform", platform)
    ]
    return [
        *platform_arguments,
        "--python-version",
        target["python_version"],
        "--implementation",
        target["implementation"],
        "--abi",
        target["abi"],
    ]


def host_pip_command() -> list[str]:
    if importlib.util.find_spec("pip") is not None:
        return [sys.executable, "-m", "pip"]
    for executable in ("pip3", "pip"):
        path = shutil.which(executable)
        if path is not None:
            return [path]
    raise SystemExit(
        "error: Guest Python runtime wheelhouse staging requires a pip executable"
    )


def ensure_only_wheels(directory: Path) -> None:
    entries = sorted(item for item in directory.iterdir() if item.is_file())
    if not entries or any(item.suffix != ".whl" for item in entries):
        raise SystemExit(
            "error: Guest Python runtime wheelhouse must contain only wheels: "
            f"{directory}"
        )


def reset_generated_wheel_directory(directory: Path) -> None:
    if directory.exists():
        if not directory.is_dir() or directory.is_symlink():
            raise SystemExit(
                "error: Guest Python runtime wheelhouse path is not a directory: "
                f"{directory}"
            )
        shutil.rmtree(directory)
    directory.mkdir(parents=True, exist_ok=True)


def project_runtime_dependencies(project: Path) -> list[str]:
    metadata = project_metadata(project)
    dependencies = metadata.get("dependencies", [])
    if not isinstance(dependencies, list) or not all(
        isinstance(item, str) and item for item in dependencies
    ):
        raise SystemExit(
            "error: invalid project.dependencies: "
            f"{project / 'pyproject.toml'}"
        )
    return dependencies


def build_pure_python_wheel(project: Path, output_directory: Path) -> Path:
    pyproject = project / "pyproject.toml"
    package_root = project / "src"
    if not pyproject.is_file():
        raise SystemExit(f"error: missing Python project metadata: {pyproject}")
    if not package_root.is_dir():
        raise SystemExit(f"error: missing Python package src directory: {package_root}")

    metadata = project_metadata(project)
    name = required_metadata(metadata, "name", pyproject)
    version = required_metadata(metadata, "version", pyproject)
    description = str(metadata.get("description", ""))
    requires_python = required_metadata(metadata, "requires-python", pyproject)
    dependencies = project_runtime_dependencies(project)
    scripts = metadata.get("scripts", {})
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
                    requires_python=requires_python,
                    dependencies=dependencies,
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
        output = output_directory / wheel_name
        output.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(wheel, output)
        return output


def project_metadata(project: Path) -> dict[object, object]:
    pyproject = project / "pyproject.toml"
    with pyproject.open("rb") as handle:
        metadata = tomllib.load(handle)
    value = metadata.get("project")
    if not isinstance(value, dict):
        raise SystemExit(f"error: missing [project] metadata: {pyproject}")
    return value


def write_archive_file(
    archive: zipfile.ZipFile,
    records: list[tuple[str, str, str]],
    path: str,
    content: bytes,
) -> None:
    info = zipfile.ZipInfo(path, date_time=(1980, 1, 1, 0, 0, 0))
    info.compress_type = zipfile.ZIP_DEFLATED
    info.create_system = 3
    info.external_attr = 0o100644 << 16
    archive.writestr(info, content)
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


def package_metadata(
    *,
    name: str,
    version: str,
    description: str,
    requires_python: str,
    dependencies: list[str],
) -> str:
    message = Message()
    message["Metadata-Version"] = "2.1"
    message["Name"] = name
    message["Version"] = version
    message["Requires-Python"] = requires_python
    for dependency in dependencies:
        message["Requires-Dist"] = dependency
    if description:
        message["Summary"] = description
    return message.as_string()


def file_identity(path: Path) -> dict[str, object]:
    return {
        "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
        "bytes": path.stat().st_size,
    }


def entry_points(scripts: dict[object, object]) -> str:
    lines = ["[console_scripts]"]
    for name, target in sorted(scripts.items()):
        if not isinstance(name, str) or not isinstance(target, str):
            raise SystemExit("error: invalid project script metadata")
        lines.append(f"{name} = {target}")
    return "\n".join(lines) + "\n"
