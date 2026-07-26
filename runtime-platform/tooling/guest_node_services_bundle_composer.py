"""Compose the immutable Guest Node Services bundle for C35/C39 delivery.

The bundle is a release-build artifact, not a service manager.  It accepts
already-built, explicit inputs and writes exactly one new tar-gzip archive:

* one declared ARM64 or AMD64 Linux Node distribution below ``node/``;
* the Recorder Gateway's built program and runtime dependencies;
* the Lab Recorder Runner's built program and runtime dependencies; and
* the declared Lab scenario catalog consumed by that Runner.

It never chooses a Node distribution, runs npm, builds TypeScript, reads a
Guest root, or starts a process.  Those effects belong to the caller's
explicit build preparation and to the Guest Product supervisor respectively.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import gzip
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import stat
import sys
import tarfile
import tempfile
from typing import Iterable


class GuestNodeServicesBundleCompositionError(RuntimeError):
    """One declared Node Services bundle could not be safely composed."""


@dataclass(frozen=True)
class GuestNodeServicesBundleComposition:
    """Every caller-owned input and the one new immutable output path."""

    node_distribution_root: Path
    guest_architecture: str
    recorder_gateway_root: Path
    lab_recorder_runner_root: Path
    lab_scenario_catalog: Path
    output_archive: Path


@dataclass(frozen=True)
class DeclaredBundleTree:
    """One source tree and its exact archive prefix."""

    source_root: Path
    archive_prefix: PurePosixPath


def compose_guest_node_services_bundle(
    composition: GuestNodeServicesBundleComposition,
) -> dict[str, str | int]:
    """Atomically create a byte-identified C39 Guest Node Services archive."""

    validate_composition(composition)
    trees = declared_bundle_trees(composition)
    parent = composition.output_archive.parent
    temporary_directory = Path(
        tempfile.mkdtemp(
            prefix="." + composition.output_archive.name + ".",
            dir=parent,
        )
    )
    temporary_archive = temporary_directory / composition.output_archive.name
    try:
        write_deterministic_tar_gzip(temporary_archive, trees, composition.lab_scenario_catalog)
        # link(2) publishes only when the declared destination remains new; it
        # therefore cannot turn a concurrent producer's artifact into ours.
        try:
            os.link(temporary_archive, composition.output_archive)
        except FileExistsError as error:
            raise GuestNodeServicesBundleCompositionError(
                "Guest Node Services bundle output already exists: "
                + str(composition.output_archive)
            ) from error
    finally:
        shutil.rmtree(temporary_directory, ignore_errors=True)

    size_bytes, sha256 = regular_file_identity(composition.output_archive)
    return {
        "artifactId": "guest-node-services-linux-" + composition.guest_architecture,
        "outputArchive": str(composition.output_archive),
        "sizeBytes": size_bytes,
        "sha256": sha256,
    }


def validate_composition(composition: GuestNodeServicesBundleComposition) -> None:
    require_directory(composition.node_distribution_root, "Node distribution root")
    require_directory(composition.recorder_gateway_root, "Recorder Gateway root")
    require_directory(composition.lab_recorder_runner_root, "Lab Recorder Runner root")
    require_regular_file(composition.lab_scenario_catalog, "Lab scenario catalog")
    require_linux_node_distribution(
        composition.node_distribution_root / "bin/node", composition.guest_architecture
    )
    require_production_service_payload(
        composition.recorder_gateway_root,
        "Recorder Gateway",
        "recorder-gateway.js",
    )
    require_production_service_payload(
        composition.lab_recorder_runner_root,
        "Lab Recorder Runner",
        "lab-recorder-runner.js",
    )
    require_lab_scenario_catalog(composition.lab_scenario_catalog)
    if not composition.output_archive.is_absolute():
        raise GuestNodeServicesBundleCompositionError(
            "Guest Node Services bundle output path must be absolute"
        )
    if composition.output_archive.exists() or composition.output_archive.is_symlink():
        raise GuestNodeServicesBundleCompositionError(
            "Guest Node Services bundle output already exists: "
            + str(composition.output_archive)
        )
    require_directory(composition.output_archive.parent, "Guest Node Services bundle output parent")


def declared_bundle_trees(
    composition: GuestNodeServicesBundleComposition,
) -> tuple[DeclaredBundleTree, ...]:
    """Return the complete, fixed product layout without source discovery."""

    return (
        DeclaredBundleTree(composition.node_distribution_root, PurePosixPath("node")),
        DeclaredBundleTree(
            composition.recorder_gateway_root / "dist",
            PurePosixPath("recorder-gateway/dist"),
        ),
        DeclaredBundleTree(
            composition.recorder_gateway_root / "node_modules",
            PurePosixPath("recorder-gateway/node_modules"),
        ),
        DeclaredBundleTree(
            composition.lab_recorder_runner_root / "dist",
            PurePosixPath("lab-recorder-runner/dist"),
        ),
        DeclaredBundleTree(
            composition.lab_recorder_runner_root / "node_modules",
            PurePosixPath("lab-recorder-runner/node_modules"),
        ),
    )


def write_deterministic_tar_gzip(
    destination: Path,
    trees: Iterable[DeclaredBundleTree],
    scenario_catalog: Path,
) -> None:
    """Write a deterministic, safe tar-gzip payload from declared trees only."""

    with destination.open("xb") as raw_output:
        with gzip.GzipFile(fileobj=raw_output, mode="wb", mtime=0) as compressed_output:
            with tarfile.open(
                fileobj=compressed_output,
                mode="w",
                format=tarfile.PAX_FORMAT,
            ) as archive:
                archive_paths: set[str] = set()
                for tree in trees:
                    add_declared_tree(archive, tree, archive_paths)
                add_declared_regular_file(
                    archive,
                    scenario_catalog,
                    PurePosixPath("lab-recorder-runner/lab-scenario-catalog.json"),
                    archive_paths,
                )


def add_declared_tree(
    archive: tarfile.TarFile,
    tree: DeclaredBundleTree,
    archive_paths: set[str],
) -> None:
    root = tree.source_root.resolve(strict=True)
    for current_root, directories, filenames in os.walk(root, topdown=True, followlinks=False):
        current = Path(current_root)
        directories.sort()
        filenames.sort()
        relative_current = current.relative_to(root)
        archive_current = tree.archive_prefix / relative_current
        add_declared_directory(archive, current, archive_current, archive_paths)

        linked_directories: list[str] = []
        for directory_name in directories:
            candidate = current / directory_name
            if candidate.is_symlink():
                add_declared_symlink(archive, candidate, tree, archive_paths)
                linked_directories.append(directory_name)
        for directory_name in linked_directories:
            directories.remove(directory_name)

        for file_name in filenames:
            candidate = current / file_name
            if candidate.is_symlink():
                add_declared_symlink(archive, candidate, tree, archive_paths)
            else:
                add_declared_regular_file(
                    archive,
                    candidate,
                    tree.archive_prefix / candidate.relative_to(root),
                    archive_paths,
                )


def add_declared_directory(
    archive: tarfile.TarFile,
    directory: Path,
    archive_path: PurePosixPath,
    archive_paths: set[str],
) -> None:
    info = directory_tar_info(directory, archive_path)
    add_unique_tar_info(archive, info, archive_paths)


def add_declared_regular_file(
    archive: tarfile.TarFile,
    source: Path,
    archive_path: PurePosixPath,
    archive_paths: set[str],
) -> None:
    require_regular_file(source, "Guest Node Services bundle source")
    info = regular_file_tar_info(source, archive_path)
    add_unique_tar_info(archive, info, archive_paths, source)


def add_declared_symlink(
    archive: tarfile.TarFile,
    source: Path,
    tree: DeclaredBundleTree,
    archive_paths: set[str],
) -> None:
    target = read_safe_relative_symlink_target(source, tree.source_root)
    # os.walk starts from the resolved source root while callers may have
    # declared an equivalent symlinked path (macOS commonly maps /tmp to
    # /private/tmp).  Archive membership is lexical within the walked tree;
    # resolving the link itself would erase the symlink we are preserving.
    archive_path = tree.archive_prefix / source.relative_to(tree.source_root.resolve(strict=True))
    info = tarfile.TarInfo(archive_path.as_posix())
    info.type = tarfile.SYMTYPE
    info.linkname = target
    info.mode = stat.S_IMODE(source.lstat().st_mode)
    normalize_tar_info(info)
    add_unique_tar_info(archive, info, archive_paths)


def add_unique_tar_info(
    archive: tarfile.TarFile,
    info: tarfile.TarInfo,
    archive_paths: set[str],
    source: Path | None = None,
) -> None:
    archive_path = info.name.rstrip("/")
    if not archive_path or archive_path in archive_paths:
        raise GuestNodeServicesBundleCompositionError(
            "Guest Node Services bundle archive path is duplicated or empty: "
            + repr(info.name)
        )
    archive_paths.add(archive_path)
    if source is None:
        archive.addfile(info)
        return
    with source.open("rb") as contents:
        archive.addfile(info, contents)


def directory_tar_info(source: Path, archive_path: PurePosixPath) -> tarfile.TarInfo:
    info = tarfile.TarInfo(archive_path.as_posix())
    info.type = tarfile.DIRTYPE
    info.mode = stat.S_IMODE(source.lstat().st_mode)
    normalize_tar_info(info)
    return info


def regular_file_tar_info(source: Path, archive_path: PurePosixPath) -> tarfile.TarInfo:
    info = tarfile.TarInfo(archive_path.as_posix())
    info.type = tarfile.REGTYPE
    info.mode = stat.S_IMODE(source.lstat().st_mode)
    info.size = source.stat().st_size
    normalize_tar_info(info)
    return info


def normalize_tar_info(info: tarfile.TarInfo) -> None:
    info.uid = 0
    info.gid = 0
    info.uname = ""
    info.gname = ""
    info.mtime = 0


def read_safe_relative_symlink_target(source: Path, tree_root: Path) -> str:
    try:
        target = os.readlink(source)
    except OSError as error:
        raise GuestNodeServicesBundleCompositionError(
            "Guest Node Services bundle symbolic link cannot be read: " + str(source)
        ) from error
    if not target or os.path.isabs(target):
        raise GuestNodeServicesBundleCompositionError(
            "Guest Node Services bundle symbolic link must be relative: " + str(source)
        )
    resolved_target = (source.parent / target).resolve(strict=False)
    resolved_root = tree_root.resolve(strict=True)
    try:
        resolved_target.relative_to(resolved_root)
    except ValueError as error:
        raise GuestNodeServicesBundleCompositionError(
            "Guest Node Services bundle symbolic link escapes its declared tree: "
            + str(source)
        ) from error
    return target


def require_directory(path: Path, role: str) -> None:
    if not path.is_absolute():
        raise GuestNodeServicesBundleCompositionError(role + " path must be absolute")
    if path.is_symlink() or not path.is_dir():
        raise GuestNodeServicesBundleCompositionError(
            role + " must be an existing non-symlink directory: " + str(path)
        )


def require_regular_file(path: Path, role: str) -> None:
    if not path.is_absolute():
        raise GuestNodeServicesBundleCompositionError(role + " path must be absolute")
    if path.is_symlink() or not path.is_file():
        raise GuestNodeServicesBundleCompositionError(
            role + " must be an existing regular non-symlink file: " + str(path)
        )


def require_linux_node_distribution(path: Path, guest_architecture: str) -> None:
    """Reject a Host or wrong-architecture Node executable before packaging."""

    expected_machine_by_architecture = {"arm64": 183, "amd64": 62}
    if guest_architecture not in expected_machine_by_architecture:
        raise GuestNodeServicesBundleCompositionError(
            "Guest Node Services architecture must be arm64 or amd64"
        )

    require_regular_file(path, "Node distribution executable")
    if path.stat().st_mode & 0o111 == 0:
        raise GuestNodeServicesBundleCompositionError(
            "Node distribution executable must be executable: " + str(path)
        )
    try:
        header = path.read_bytes()[:20]
    except OSError as error:
        raise GuestNodeServicesBundleCompositionError(
            "Node distribution executable cannot be read: " + str(path)
        ) from error
    if len(header) < 20 or header[:4] != b"\x7fELF" or header[4] != 2 or header[5] != 1:
        raise GuestNodeServicesBundleCompositionError(
            "Node distribution executable must be Linux ELF64 little-endian: " + str(path)
        )
    if int.from_bytes(header[18:20], "little") != expected_machine_by_architecture[guest_architecture]:
        raise GuestNodeServicesBundleCompositionError(
            "Node distribution executable must target Linux "
            + guest_architecture
            + ": "
            + str(path)
        )


def require_production_service_payload(
    service_root: Path,
    service_name: str,
    entrypoint_name: str,
) -> None:
    """Require compiled code and an npm-pruned runtime dependency closure."""

    require_regular_file(
        service_root / "dist" / "cmd" / entrypoint_name,
        service_name + " program",
    )
    node_modules = service_root / "node_modules"
    require_directory(node_modules, service_name + " runtime dependencies")
    package_path = service_root / "package.json"
    require_regular_file(package_path, service_name + " package manifest")
    try:
        package = json.loads(package_path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise GuestNodeServicesBundleCompositionError(
            service_name + " package manifest cannot be decoded: " + str(error)
        ) from error
    if not isinstance(package, dict):
        raise GuestNodeServicesBundleCompositionError(
            service_name + " package manifest must be an object"
        )
    dependencies = package.get("dependencies")
    if not isinstance(dependencies, dict) or not dependencies:
        raise GuestNodeServicesBundleCompositionError(
            service_name + " package manifest must declare runtime dependencies"
        )
    missing_dependencies = sorted(
        dependency for dependency in dependencies if not (node_modules / dependency).is_dir()
    )
    if missing_dependencies:
        raise GuestNodeServicesBundleCompositionError(
            service_name
            + " runtime dependencies are missing declared packages: "
            + ", ".join(missing_dependencies)
        )
    development_dependencies = package.get("devDependencies", {})
    if not isinstance(development_dependencies, dict):
        raise GuestNodeServicesBundleCompositionError(
            service_name + " package devDependencies must be an object"
        )

    # A manifest name is not enough to identify a development-only package.
    # For example, Recorder Gateway declares ``ws`` for its development test
    # harness while Socket.IO also brings the same package into the production
    # dependency closure.  npm records that distinction in package-lock's
    # concrete package entries.  The staged closure therefore has to be
    # checked against those entries, not against the intent-only manifest.
    package_lock_path = service_root / "package-lock.json"
    require_regular_file(package_lock_path, service_name + " dependency lock")
    try:
        package_lock = json.loads(package_lock_path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise GuestNodeServicesBundleCompositionError(
            service_name + " dependency lock cannot be decoded: " + str(error)
        ) from error
    if not isinstance(package_lock, dict):
        raise GuestNodeServicesBundleCompositionError(
            service_name + " dependency lock must be an object"
        )
    locked_packages = package_lock.get("packages")
    if not isinstance(locked_packages, dict):
        raise GuestNodeServicesBundleCompositionError(
            service_name + " dependency lock must declare package entries"
        )
    installed_development_only_packages = sorted(
        package_path
        for package_path, package_metadata in locked_packages.items()
        if isinstance(package_path, str)
        and package_path.startswith("node_modules/")
        and isinstance(package_metadata, dict)
        and package_metadata.get("dev") is True
        and (service_root / package_path).exists()
    )
    if installed_development_only_packages:
        raise GuestNodeServicesBundleCompositionError(
            service_name
            + " runtime dependencies contain development-only package: "
            + ", ".join(installed_development_only_packages)
        )


def require_lab_scenario_catalog(path: Path) -> None:
    try:
        document = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise GuestNodeServicesBundleCompositionError(
            "Lab scenario catalog cannot be decoded: " + str(error)
        ) from error
    if (
        not isinstance(document, dict)
        or document.get("schemaVersion") != "v1"
        or not isinstance(document.get("catalogId"), str)
        or not document["catalogId"]
        or not isinstance(document.get("scenarios"), list)
    ):
        raise GuestNodeServicesBundleCompositionError(
            "Lab scenario catalog must provide schemaVersion v1, catalogId, and scenarios"
        )


def regular_file_identity(path: Path) -> tuple[int, str]:
    require_regular_file(path, "Guest Node Services bundle output")
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return path.stat().st_size, digest.hexdigest()


def parse_arguments(arguments: list[str]) -> GuestNodeServicesBundleComposition:
    parser = argparse.ArgumentParser(
        description="compose one explicit Guest Node Services tar-gzip bundle"
    )
    parser.add_argument("--node-distribution-root", required=True)
    parser.add_argument("--guest-architecture", choices=("arm64", "amd64"), required=True)
    parser.add_argument("--recorder-gateway-root", required=True)
    parser.add_argument("--lab-recorder-runner-root", required=True)
    parser.add_argument("--lab-scenario-catalog", required=True)
    parser.add_argument("--output-archive", required=True)
    parsed = parser.parse_args(arguments)
    return GuestNodeServicesBundleComposition(
        node_distribution_root=Path(parsed.node_distribution_root),
        guest_architecture=parsed.guest_architecture,
        recorder_gateway_root=Path(parsed.recorder_gateway_root),
        lab_recorder_runner_root=Path(parsed.lab_recorder_runner_root),
        lab_scenario_catalog=Path(parsed.lab_scenario_catalog),
        output_archive=Path(parsed.output_archive),
    )


def main(arguments: list[str] | None = None) -> int:
    try:
        composition = parse_arguments(sys.argv[1:] if arguments is None else arguments)
        result = compose_guest_node_services_bundle(composition)
    except GuestNodeServicesBundleCompositionError as error:
        print("Guest Node Services bundle composition failed: " + str(error), file=sys.stderr)
        return 1
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
