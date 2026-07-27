"""Compose a deterministic Linux DEB from one explicit C48 release.

The composer is release tooling.  It does not inspect an installed Host,
create a service registration, or turn a package archive into clean-host
evidence.  The generated maintainer scripts transport C48/C50/C54 arguments
to Host Installation Manager; dpkg remains the sole owner of its receipt.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import gzip
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import shutil
import tarfile
import tempfile
from typing import Any, Mapping

from tooling.contracts import ContractRepository, ContractToolError


class LinuxHostPackageCompositionError(RuntimeError):
    """Raised when a selected release cannot be represented as a safe DEB."""


_HOST_ADMINISTRATION_DESCRIPTOR_PATH = "/opt/vitalserver-runtime-platform/control/host-agent.local.json"
_HOST_ADMINISTRATION_TIMEOUT_MILLISECONDS = 5000


@dataclass(frozen=True)
class LinuxHostPackageComposition:
    manifest_path: Path
    release_source_directory: Path
    service_definition_sources: Mapping[str, Path]
    operator_interface_bootstrap_source: Path
    installation_journal_path: str
    installation_receipt_path: str
    removal_journal_path: str
    removal_receipt_path: str
    package_manager_completion_manager_path: str
    package_manager_completion_manifest_path: str
    output_package: Path
    package_name: str
    architecture: str
    maintainer: str
    description: str
    replace_output: bool = False
    systemctl_executable_path: str = "/usr/bin/systemctl"


def compose_linux_host_package(composition: LinuxHostPackageComposition) -> dict[str, str]:
    """Validate explicit release inputs and publish one deterministic DEB.

    C50 preflight runs in postinst, after dpkg has delivered the immutable
    payload and reports its explicit `unpacked` receipt state.  Control
    scripts only carry C48 command arguments; they do not contain a second
    executable or manifest source.
    """

    manifest = _read_manifest(composition.manifest_path)
    _validate_composition(composition, manifest)
    output = composition.output_package
    if output.exists() and not composition.replace_output:
        raise LinuxHostPackageCompositionError(f"output package already exists: {output}")
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="vitalserver-linux-deb-") as temporary:
        root = Path(temporary)
        data_root = root / "data"
        control_root = root / "control"
        _write_data_archive_root(composition, manifest, data_root)
        _write_control_archive_root(composition, manifest, control_root)
        control = _tar_gzip_bytes(control_root)
        data = _tar_gzip_bytes(data_root)
        package = _ar_bytes(
            [
                ("debian-binary", b"2.0\n"),
                ("control.tar.gz", control),
                ("data.tar.gz", data),
            ]
        )
        temporary_output = output.with_name("." + output.name + ".compose")
        if temporary_output.exists():
            temporary_output.unlink()
        temporary_output.write_bytes(package)
        temporary_output.replace(output)
    return {
        "artifactPath": str(output),
        "sha256": _sha256_file(output),
        "sizeBytes": str(output.stat().st_size),
        "packageName": composition.package_name,
        "productVersion": str(manifest["package"]["productVersion"]),
    }


def _read_manifest(path: Path) -> Mapping[str, Any]:
    document = _read_json(path, "C48 HostProductInstallationManifest")
    repository = ContractRepository(Path(__file__).resolve().parents[1])
    try:
        repository.load()
        findings = repository.validate_instance("host-product-installation-manifest.schema.json", document)
    except ContractToolError as error:
        raise LinuxHostPackageCompositionError("C48 contract source is unavailable: " + str(error)) from error
    if findings:
        raise LinuxHostPackageCompositionError("C48 is invalid: " + "; ".join(findings))
    if document.get("platform") != "linux":
        raise LinuxHostPackageCompositionError("Linux DEB composer requires C48 platform linux")
    return document


def _validate_composition(composition: LinuxHostPackageComposition, manifest: Mapping[str, Any]) -> None:
    if not _valid_package_name(composition.package_name):
        raise LinuxHostPackageCompositionError("Debian package name is invalid")
    if composition.architecture not in {"amd64", "arm64"}:
        raise LinuxHostPackageCompositionError("Linux package architecture must be amd64 or arm64")
    if not composition.maintainer or not composition.description:
        raise LinuxHostPackageCompositionError("Linux package maintainer and description are required")
    if not composition.release_source_directory.is_dir() or composition.release_source_directory.is_symlink():
        raise LinuxHostPackageCompositionError("C48 release source directory is unavailable or symbolic")
    expected_manifest = composition.release_source_directory / "installation-manifest.json"
    if expected_manifest.resolve() != composition.manifest_path.resolve():
        raise LinuxHostPackageCompositionError("C48 manifest must be the installation-manifest.json in the selected release source")
    release = _required_object(manifest, "release", "C48")
    package = _required_object(manifest, "package", "C48")
    if composition.package_name != _required_string(package, "identifier", "C48 package"):
        raise LinuxHostPackageCompositionError("Debian package name must equal the C48 package identifier observed by dpkg")
    immutable = _required_object(manifest, "immutablePayload", "C48")
    expected_root = _absolute_to_package_path(_required_string(immutable, "releaseRootPath", "C48 immutablePayload"))
    if expected_root.name != _required_string(release, "id", "C48 release"):
        raise LinuxHostPackageCompositionError("C48 immutable release root does not name its release id")
    _validate_declared_release_files(composition.release_source_directory, immutable)
    operator = _required_object(manifest, "operatorInterface", "C48")
    _verify_file_hash(composition.operator_interface_bootstrap_source, _required_string(operator, "bootstrapConfigurationSha256", "C48 operatorInterface"), "C53 bootstrap source")
    _require_absolute_path(composition.installation_journal_path, "installation journal path")
    _require_absolute_path(composition.installation_receipt_path, "installation receipt path")
    _require_absolute_path(composition.removal_journal_path, "removal journal path")
    _require_absolute_path(composition.removal_receipt_path, "removal receipt path")
    _validate_package_manager_completion_transport(composition, manifest)
    _require_absolute_path(composition.systemctl_executable_path, "systemctl executable path")
    manager_source = composition.release_source_directory / "bin" / "host-installation-manager"
    if not manager_source.is_file() or manager_source.is_symlink():
        raise LinuxHostPackageCompositionError("C48 release source must contain a regular bin/host-installation-manager")
    services = _required_list(manifest, "requiredServices", "C48")
    if set(composition.service_definition_sources) != {service["role"] for service in services}:
        raise LinuxHostPackageCompositionError("every and only C48 service role must have one service-definition source")
    for service in services:
        if service.get("manager") != "systemd":
            raise LinuxHostPackageCompositionError("Linux C48 service manager must be systemd")
        source = composition.service_definition_sources[service["role"]]
        _verify_file_hash(source, _required_string(service, "definitionSha256", "C48 requiredService"), "C48 systemd definition " + service["role"])


def _write_data_archive_root(composition: LinuxHostPackageComposition, manifest: Mapping[str, Any], destination_root: Path) -> None:
    immutable = _required_object(manifest, "immutablePayload", "C48")
    release_destination = destination_root / _absolute_to_package_path(_required_string(immutable, "releaseRootPath", "C48 immutablePayload"))
    for source in sorted(composition.release_source_directory.rglob("*")):
        relative = source.relative_to(composition.release_source_directory)
        target = release_destination / relative
        if source.is_dir():
            target.mkdir(parents=True, exist_ok=True)
            continue
        if source.is_symlink() or not source.is_file():
            raise LinuxHostPackageCompositionError("C48 release source contains an unsupported filesystem entry")
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)
        target.chmod(0o755 if source.stat().st_mode & 0o111 else 0o644)
    for service in _required_list(manifest, "requiredServices", "C48"):
        target = destination_root / _absolute_to_package_path(_required_string(service, "definitionPath", "C48 requiredService"))
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(composition.service_definition_sources[service["role"]], target)
        target.chmod(0o644)
    operator = _required_object(manifest, "operatorInterface", "C48")
    target = destination_root / _absolute_to_package_path(_required_string(operator, "bootstrapConfigurationPath", "C48 operatorInterface"))
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(composition.operator_interface_bootstrap_source, target)
    target.chmod(0o644)


def _write_control_archive_root(composition: LinuxHostPackageComposition, manifest: Mapping[str, Any], destination_root: Path) -> None:
    destination_root.mkdir(parents=True, exist_ok=True)
    version = _required_string(_required_object(manifest, "package", "C48"), "productVersion", "C48 package")
    (destination_root / "control").write_text(
        "Package: {0}\nVersion: {1}\nArchitecture: {2}\nMaintainer: {3}\nDescription: {4}\n".format(
            composition.package_name, version, composition.architecture, composition.maintainer, composition.description
        ),
        encoding="utf-8",
    )
    (destination_root / "preinst").write_text(_preinst_script(composition, manifest), encoding="utf-8")
    (destination_root / "postinst").write_text(_postinst_script(composition, manifest), encoding="utf-8")
    (destination_root / "prerm").write_text(_prerm_script(composition, manifest), encoding="utf-8")
    (destination_root / "postrm").write_text(_postrm_script(composition, manifest), encoding="utf-8")
    for name in ("preinst", "postinst", "prerm", "postrm"):
        (destination_root / name).chmod(0o755)


def _preinst_script(composition: LinuxHostPackageComposition, manifest: Mapping[str, Any]) -> str:
    del composition, manifest
    return """#!/bin/sh
set -eu
case "${1:-install}" in
  install) exit 0 ;;
  upgrade)
    echo "direct Debian package upgrades are unsupported; use the signed staged Host Updater" >&2
    exit 1
    ;;
  *) exit 0 ;;
esac
"""


def _postinst_script(composition: LinuxHostPackageComposition, manifest: Mapping[str, Any]) -> str:
    immutable = _required_object(manifest, "immutablePayload", "C48")
    release_root = _required_string(immutable, "releaseRootPath", "C48 immutablePayload")
    manager = release_root + "/bin/host-installation-manager"
    manifest_path = _required_string(immutable, "manifestPath", "C48 immutablePayload")
    installation = _required_string(manifest, "installationId", "C48")
    release = _required_string(_required_object(manifest, "release", "C48"), "id", "C48 release")
    return """#!/bin/sh
set -eu
case "${{1:-configure}}" in
  configure)
    "{manager}" --mode preflight --manifest "{manifest}" --journal "{journal}" --receipt "{receipt}" --request-id "{package}-preflight" --installation-id "{installation}" --release-id "{release}" --host-administration-descriptor "{host_administration_descriptor}" --host-administration-timeout-milliseconds {host_administration_timeout} --systemctl "{systemctl}"
    "{manager}" --mode quiesce --manifest "{manifest}" --journal "{journal}" --receipt "{receipt}" --host-administration-descriptor "{host_administration_descriptor}" --host-administration-timeout-milliseconds {host_administration_timeout} --systemctl "{systemctl}"
    "{manager}" --mode activate --manifest "{manifest}" --journal "{journal}" --receipt "{receipt}" --host-administration-descriptor "{host_administration_descriptor}" --host-administration-timeout-milliseconds {host_administration_timeout} --systemctl "{systemctl}"
    exec "{manager}" --mode finalize --manifest "{manifest}" --journal "{journal}" --receipt "{receipt}" --host-administration-descriptor "{host_administration_descriptor}" --host-administration-timeout-milliseconds {host_administration_timeout} --systemctl "{systemctl}"
    ;;
  *) exit 0 ;;
esac
""".format(manager=manager, manifest=manifest_path, journal=composition.installation_journal_path, receipt=composition.installation_receipt_path, package=composition.package_name, installation=installation, release=release, host_administration_descriptor=_HOST_ADMINISTRATION_DESCRIPTOR_PATH, host_administration_timeout=_HOST_ADMINISTRATION_TIMEOUT_MILLISECONDS, systemctl=composition.systemctl_executable_path)


def _prerm_script(composition: LinuxHostPackageComposition, manifest: Mapping[str, Any]) -> str:
    immutable = _required_object(manifest, "immutablePayload", "C48")
    manager = _required_string(immutable, "releaseRootPath", "C48 immutablePayload") + "/bin/host-installation-manager"
    manifest_path = _required_string(immutable, "manifestPath", "C48 immutablePayload")
    release = _required_object(manifest, "release", "C48")
    return """#!/bin/sh
set -eu
case "${{1:-remove}}" in
  remove)
    exec "{manager}" --mode remove --manifest "{manifest}" --journal "{journal}" --receipt "{receipt}" --request-id "{package}-remove-preserve" --installation-id "{installation}" --release-id "{release}" --data-disposition preserve-mutable-data --removal-journal "{removal_journal}" --removal-receipt "{removal_receipt}" --package-manager-completion-manager "{completion_manager}" --package-manager-completion-manifest "{completion_manifest}" --host-administration-descriptor "{host_administration_descriptor}" --host-administration-timeout-milliseconds {host_administration_timeout} --systemctl "{systemctl}"
    ;;
  upgrade)
    echo "direct Debian package upgrades are unsupported; use the signed staged Host Updater" >&2
    exit 1
    ;;
  *) exit 0 ;;
esac
""".format(manager=manager, manifest=manifest_path, journal=composition.installation_journal_path, receipt=composition.installation_receipt_path, package=composition.package_name, installation=_required_string(manifest, "installationId", "C48"), release=_required_string(release, "id", "C48 release"), removal_journal=composition.removal_journal_path, removal_receipt=composition.removal_receipt_path, completion_manager=composition.package_manager_completion_manager_path, completion_manifest=composition.package_manager_completion_manifest_path, host_administration_descriptor=_HOST_ADMINISTRATION_DESCRIPTOR_PATH, host_administration_timeout=_HOST_ADMINISTRATION_TIMEOUT_MILLISECONDS, systemctl=composition.systemctl_executable_path)


def _postrm_script(composition: LinuxHostPackageComposition, manifest: Mapping[str, Any]) -> str:
    """Return the post-dpkg C54 completion proof transport.

    Debian owns the package receipt. After `prerm remove` records the explicit
    hand-off, `postrm remove` runs only after dpkg removed the installed
    payload. C54 prepares its own transport below the declared mutable store
    before it removes that payload; no dpkg control-file lifetime is assumed.
    """

    return """#!/bin/sh
set -eu
case "${{1:-remove}}" in
  remove)
    exec "{manager}" --mode complete-removal-after-package-manager --manifest "{manifest}" --journal "{journal}" --receipt "{receipt}" --removal-journal "{removal_journal}" --removal-receipt "{removal_receipt}" --host-administration-descriptor "{host_administration_descriptor}" --host-administration-timeout-milliseconds {host_administration_timeout} --systemctl "{systemctl}"
    ;;
  purge|abort-remove|abort-install|disappear) exit 0 ;;
  *) exit 0 ;;
esac
""".format(manager=composition.package_manager_completion_manager_path, manifest=composition.package_manager_completion_manifest_path, journal=composition.installation_journal_path, receipt=composition.installation_receipt_path, removal_journal=composition.removal_journal_path, removal_receipt=composition.removal_receipt_path, host_administration_descriptor=_HOST_ADMINISTRATION_DESCRIPTOR_PATH, host_administration_timeout=_HOST_ADMINISTRATION_TIMEOUT_MILLISECONDS, systemctl=composition.systemctl_executable_path)


def _validate_declared_release_files(root: Path, immutable: Mapping[str, Any]) -> None:
    declared = {"installation-manifest.json"}
    for entry in _required_list(immutable, "entries", "C48 immutablePayload"):
        relative = _safe_relative_path(_required_string(entry, "relativePath", "C48 immutable entry"))
        declared.add(relative.as_posix())
        _verify_file_hash(root / relative, _required_string(entry, "sha256", "C48 immutable entry"), "C48 immutable source " + relative.as_posix())
    actual = set()
    for source in root.rglob("*"):
        if source.is_dir():
            continue
        if source.is_symlink() or not source.is_file():
            raise LinuxHostPackageCompositionError("C48 release source contains an unsupported filesystem entry")
        actual.add(source.relative_to(root).as_posix())
    if actual != declared:
        raise LinuxHostPackageCompositionError("C48 release source does not contain exactly its immutable manifest and declared entries")


def _tar_gzip_bytes(root: Path) -> bytes:
    output = io.BytesIO()
    with gzip.GzipFile(fileobj=output, mode="wb", mtime=0) as compressed:
        with tarfile.open(fileobj=compressed, mode="w", format=tarfile.USTAR_FORMAT) as archive:
            for path in sorted(root.rglob("*"), key=lambda value: value.relative_to(root).as_posix()):
                relative = path.relative_to(root).as_posix()
                if path.is_dir():
                    info = tarfile.TarInfo(relative + "/")
                    info.type = tarfile.DIRTYPE
                    info.mode = 0o755
                    info.mtime = 0
                    archive.addfile(info)
                    continue
                content = path.read_bytes()
                info = tarfile.TarInfo(relative)
                info.size = len(content)
                info.mode = path.stat().st_mode & 0o777
                info.mtime = 0
                archive.addfile(info, io.BytesIO(content))
    return output.getvalue()


def _ar_bytes(members: list[tuple[str, bytes]]) -> bytes:
    output = io.BytesIO()
    output.write(b"!<arch>\n")
    for name, content in members:
        encoded_name = (name + "/").encode("ascii")
        if len(encoded_name) > 16:
            raise LinuxHostPackageCompositionError("DEB archive member name is too long")
        header = encoded_name.ljust(16, b" ") + b"0".ljust(12, b" ") + b"0".ljust(6, b" ") + b"0".ljust(6, b" ") + b"100644".ljust(8, b" ") + str(len(content)).encode("ascii").ljust(10, b" ") + b"`\n"
        output.write(header)
        output.write(content)
        if len(content) % 2:
            output.write(b"\n")
    return output.getvalue()


def _read_json(path: Path, description: str) -> Mapping[str, Any]:
    if not path.is_file() or path.is_symlink():
        raise LinuxHostPackageCompositionError(description + " is missing or symbolic")
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise LinuxHostPackageCompositionError("read " + description + ": " + str(error)) from error
    if not isinstance(value, dict):
        raise LinuxHostPackageCompositionError(description + " must be one JSON object")
    return value


def _required_object(value: Mapping[str, Any], key: str, context: str) -> Mapping[str, Any]:
    child = value.get(key)
    if not isinstance(child, dict):
        raise LinuxHostPackageCompositionError(context + " requires object " + key)
    return child


def _required_list(value: Mapping[str, Any], key: str, context: str) -> list[Mapping[str, Any]]:
    child = value.get(key)
    if not isinstance(child, list) or not all(isinstance(item, dict) for item in child):
        raise LinuxHostPackageCompositionError(context + " requires object array " + key)
    return child


def _required_string(value: Mapping[str, Any], key: str, context: str) -> str:
    child = value.get(key)
    if not isinstance(child, str) or not child:
        raise LinuxHostPackageCompositionError(context + " requires string " + key)
    return child


def _safe_relative_path(value: str) -> PurePosixPath:
    path = PurePosixPath(value)
    if path.is_absolute() or value == "." or any(part in {"", ".", ".."} for part in path.parts):
        raise LinuxHostPackageCompositionError("C48 immutable relative path is unsafe")
    return path


def _absolute_to_package_path(value: str) -> PurePosixPath:
    _require_absolute_path(value, "C48 Host path")
    return PurePosixPath(value[1:])


def _require_absolute_path(value: str, context: str) -> None:
    if not value.startswith("/") or "\\" in value or any(part == ".." for part in PurePosixPath(value).parts):
        raise LinuxHostPackageCompositionError(context + " must be a safe absolute Linux path")


def _validate_package_manager_completion_transport(composition: LinuxHostPackageComposition, manifest: Mapping[str, Any]) -> None:
    manager_path = composition.package_manager_completion_manager_path
    manifest_path = composition.package_manager_completion_manifest_path
    _require_absolute_path(manager_path, "package-manager completion manager path")
    _require_absolute_path(manifest_path, "package-manager completion manifest path")
    if manager_path == manifest_path or PurePosixPath(manager_path).name != "package-manager-removal-completion" or PurePosixPath(manifest_path).name != "package-manager-removal-manifest.json":
        raise LinuxHostPackageCompositionError("package-manager completion transport paths are invalid")
    manager_store_paths = {
        str(store["path"])
        for store in _required_list(manifest, "mutableStores", "C48")
        if store.get("owner") == "host-installation-manager" and store.get("retention") == "purge-only-by-explicit-command"
    }
    if not any(manager_path.startswith(path.rstrip("/") + "/") and manifest_path.startswith(path.rstrip("/") + "/") for path in manager_store_paths):
        raise LinuxHostPackageCompositionError("package-manager completion transport must be below one declared manager-owned mutable store")


def _verify_file_hash(path: Path, expected: str, context: str) -> None:
    if not path.is_file() or path.is_symlink():
        raise LinuxHostPackageCompositionError(context + " is missing or symbolic")
    if _sha256_file(path) != expected:
        raise LinuxHostPackageCompositionError(context + " SHA-256 does not match C48")


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _valid_package_name(value: str) -> bool:
    return bool(value) and all(character.islower() or character.isdigit() or character in "+-." for character in value) and value[0].isalnum()


def _parse_arguments(arguments: list[str] | None = None) -> LinuxHostPackageComposition:
    parser = argparse.ArgumentParser(description="compose a deterministic Linux VitalServer Runtime Platform DEB")
    parser.add_argument("--composition", required=True, type=Path, help="JSON LinuxHostPackageComposition document")
    values = parser.parse_args(arguments)
    document = _read_json(values.composition, "Linux Host package composition")
    try:
        return LinuxHostPackageComposition(
            manifest_path=Path(document["manifestPath"]),
            release_source_directory=Path(document["releaseSourceDirectory"]),
            service_definition_sources={str(key): Path(value) for key, value in document["serviceDefinitionSources"].items()},
            operator_interface_bootstrap_source=Path(document["operatorInterfaceBootstrapSource"]),
            installation_journal_path=str(document["installationJournalPath"]),
            installation_receipt_path=str(document["installationReceiptPath"]),
            removal_journal_path=str(document["removalJournalPath"]),
            removal_receipt_path=str(document["removalReceiptPath"]),
            package_manager_completion_manager_path=str(document["packageManagerCompletionManagerPath"]),
            package_manager_completion_manifest_path=str(document["packageManagerCompletionManifestPath"]),
            output_package=Path(document["outputPackage"]),
            package_name=str(document["packageName"]), architecture=str(document["architecture"]),
            maintainer=str(document["maintainer"]), description=str(document["description"]),
            replace_output=bool(document.get("replaceOutput", False)),
            systemctl_executable_path=str(document.get("systemctlExecutablePath", "/usr/bin/systemctl")),
        )
    except (KeyError, TypeError) as error:
        raise LinuxHostPackageCompositionError("Linux Host package composition is incomplete") from error


def main(arguments: list[str] | None = None) -> int:
    try:
        print(json.dumps(compose_linux_host_package(_parse_arguments(arguments)), sort_keys=True))
    except LinuxHostPackageCompositionError as error:
        print("Linux Host package composition failed: " + str(error), file=__import__("sys").stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
