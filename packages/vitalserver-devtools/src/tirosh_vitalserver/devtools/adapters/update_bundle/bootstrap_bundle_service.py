from __future__ import annotations

import base64
import binascii
import json
import os
import shutil
import stat
import tarfile
import tempfile
from pathlib import Path

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import (
    Ed25519PrivateKey,
    Ed25519PublicKey,
)

from tirosh_vitalserver.devtools.adapters.update_bundle.bundle_service import (
    materialized_bundle,
)
from tirosh_vitalserver.devtools.core.errors import DomainError
from tirosh_vitalserver.devtools.core.product_update_specification import (
    load_product_update_specification,
)
from tirosh_vitalserver.devtools.core.update_bootstrap_bundle import (
    artifact,
    canonical_payload,
    seal_envelope,
    sha256_file,
    unsigned_envelope,
    validate_envelope,
)
from tirosh_vitalserver.devtools.core.update_bootstrap_bundle_models import (
    BuildUpdateBootstrapBundleInput,
    BuildUpdateBootstrapBundleResult,
)

ENVELOPE_NAME = "bootstrap-envelope.json"
UPDATER_RELATIVE_PATH = "payload/bin/vitalserver-update"
SPECIFICATION_RELATIVE_PATH = "payload/update-specification.json"


def build_bootstrap_bundle(
    spec: BuildUpdateBootstrapBundleInput,
) -> BuildUpdateBootstrapBundleResult:
    require_regular_file(spec.next_updater, "next updater")
    require_regular_file(spec.specification, "update specification")
    require_regular_file(spec.publisher_private_key, "publisher private key")
    require_directory(spec.payload_root, "product update payload root")
    if spec.output.exists():
        raise DomainError(f"bootstrap bundle output already exists: {spec.output}")
    spec.output.parent.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory(prefix="update-bootstrap-build-") as temporary:
        root = Path(temporary) / f"update-bootstrap-{spec.update_id}"
        updater = root / UPDATER_RELATIVE_PATH
        specification = root / SPECIFICATION_RELATIVE_PATH
        updater.parent.mkdir(parents=True)
        specification.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(spec.next_updater, updater)
        shutil.copy2(spec.specification, specification)
        _, declared_artifacts = load_product_update_specification(
            specification,
            update_id=spec.update_id,
            layer_order=spec.layer_order,
        )
        for relative_path, declaration in declared_artifacts.items():
            if relative_path in {
                UPDATER_RELATIVE_PATH,
                SPECIFICATION_RELATIVE_PATH,
            }:
                raise DomainError(
                    "product update artifact conflicts with bootstrap-owned path: "
                    f"{relative_path}"
                )
            source = spec.payload_root / relative_path
            require_regular_file(source, str(declaration["id"]))
            verify_declared_artifact(source, declaration)
            destination = root / relative_path
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, destination)

        unsigned = unsigned_envelope(
            update_id=spec.update_id,
            product_version=spec.product_version,
            runtime_version=spec.runtime_version,
            target_platform=spec.target_platform,
            target_architecture=spec.target_architecture,
            layer_order=spec.layer_order,
            next_updater_artifact=artifact(
                artifact_id="helper-next-updater",
                relative_path=UPDATER_RELATIVE_PATH,
                source=updater,
                media_type="application/octet-stream",
            ),
            specification_artifact=artifact(
                artifact_id="helper-update-specification",
                relative_path=SPECIFICATION_RELATIVE_PATH,
                source=specification,
                media_type="application/json",
            ),
            issued_at=spec.issued_at,
        )
        signature = sign_ed25519(
            canonical_payload(unsigned),
            spec.publisher_private_key,
        )
        envelope = seal_envelope(
            unsigned=unsigned,
            publisher_key_id=spec.publisher_key_id,
            signature_base64=base64.b64encode(signature).decode("ascii"),
        )
        envelope_path = root / ENVELOPE_NAME
        envelope_path.write_text(
            json.dumps(envelope, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        with tarfile.open(spec.output, "x:gz") as archive:
            archive.add(root, arcname=root.name)
        return BuildUpdateBootstrapBundleResult(
            archive=spec.output,
            envelope_sha256=sha256_file(envelope_path),
        )


def verify_bootstrap_bundle(
    bundle: Path,
    publisher_public_key: Path,
) -> None:
    require_regular_file(bundle, "bootstrap bundle")
    require_regular_file(publisher_public_key, "publisher public key")
    try:
        with materialized_bundle(bundle) as root:
            verify_bootstrap_bundle_directory(root, publisher_public_key)
    except (SystemExit, tarfile.TarError, OSError) as error:
        raise DomainError(
            f"bootstrap bundle materialization failed: {error}"
        ) from error


def verify_bootstrap_bundle_directory(
    root: Path,
    publisher_public_key: Path,
) -> None:
    actual_files: set[str] = set()
    for path in root.rglob("*"):
        relative_path = path.relative_to(root).as_posix()
        try:
            mode = os.lstat(path).st_mode
        except OSError as error:
            raise DomainError(
                "bootstrap bundle entry inspection failed "
                f"path={relative_path}: {error}"
            ) from error
        if stat.S_ISDIR(mode):
            continue
        if not stat.S_ISREG(mode):
            raise DomainError(
                f"bootstrap bundle entry must be a regular file path={relative_path}"
            )
        actual_files.add(relative_path)
    for relative_path in {
        ENVELOPE_NAME,
        UPDATER_RELATIVE_PATH,
        SPECIFICATION_RELATIVE_PATH,
    }:
        require_regular_file(root / relative_path, relative_path)

    envelope_path = root / ENVELOPE_NAME
    try:
        envelope = json.loads(envelope_path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise DomainError(f"bootstrap envelope read failed: {error}") from error
    if not isinstance(envelope, dict):
        raise DomainError("bootstrap envelope must be an object")
    validate_envelope(envelope)
    signature = envelope["signature"]
    unsigned = dict(envelope)
    unsigned.pop("signature")
    try:
        signature_bytes = base64.b64decode(signature["value"], validate=True)
    except (binascii.Error, ValueError) as error:
        raise DomainError(
            f"bootstrap signature is not valid base64: {error}"
        ) from error
    verify_ed25519(
        payload=canonical_payload(unsigned),
        signature=signature_bytes,
        public_key=publisher_public_key,
    )
    verify_bound_artifact(root, envelope["nextUpdaterArtifact"])
    verify_bound_artifact(root, envelope["specification"])
    _, declared_artifacts = load_product_update_specification(
        root / SPECIFICATION_RELATIVE_PATH,
        update_id=str(envelope["id"]),
        layer_order=list(envelope["layerOrder"]),
    )
    expected_files = {
        ENVELOPE_NAME,
        UPDATER_RELATIVE_PATH,
        SPECIFICATION_RELATIVE_PATH,
        *declared_artifacts,
    }
    if actual_files != expected_files:
        raise DomainError(
            "bootstrap bundle file closure differs: "
            f"missing={sorted(expected_files - actual_files)} "
            f"unknown={sorted(actual_files - expected_files)}"
        )
    for relative_path in expected_files:
        require_regular_file(root / relative_path, relative_path)

    for declaration in declared_artifacts.values():
        verify_bound_artifact(root, declaration)


def verify_bound_artifact(root: Path, entry: object) -> None:
    if not isinstance(entry, dict):
        raise DomainError("bootstrap artifact must be an object")
    path = root / str(entry["relativePath"])
    require_regular_file(path, str(entry["id"]))
    actual_digest = sha256_file(path)
    if actual_digest != entry["sha256"]:
        raise DomainError(
            f"bootstrap artifact digest mismatch id={entry['id']} "
            f"expected={entry['sha256']} actual={actual_digest}"
        )
    actual_size = path.stat().st_size
    if actual_size != entry["sizeBytes"]:
        raise DomainError(
            f"bootstrap artifact size mismatch id={entry['id']} "
            f"expected={entry['sizeBytes']} actual={actual_size}"
        )


def verify_declared_artifact(path: Path, entry: dict[str, object]) -> None:
    actual_digest = sha256_file(path)
    if actual_digest != entry["sha256"]:
        raise DomainError(
            f"product update artifact digest mismatch id={entry['id']} "
            f"expected={entry['sha256']} actual={actual_digest}"
        )
    actual_size = path.stat().st_size
    if actual_size != entry["sizeBytes"]:
        raise DomainError(
            f"product update artifact size mismatch id={entry['id']} "
            f"expected={entry['sizeBytes']} actual={actual_size}"
        )


def sign_ed25519(payload: bytes, private_key: Path) -> bytes:
    try:
        key = serialization.load_pem_private_key(
            private_key.read_bytes(),
            password=None,
        )
    except (OSError, ValueError, TypeError) as error:
        raise DomainError(f"Ed25519 private key read failed: {error}") from error
    if not isinstance(key, Ed25519PrivateKey):
        raise DomainError("publisher private key is not Ed25519")
    return key.sign(payload)


def verify_ed25519(
    *,
    payload: bytes,
    signature: bytes,
    public_key: Path,
) -> None:
    try:
        key = serialization.load_pem_public_key(public_key.read_bytes())
    except (OSError, ValueError, TypeError) as error:
        raise DomainError(f"Ed25519 public key read failed: {error}") from error
    if not isinstance(key, Ed25519PublicKey):
        raise DomainError("publisher public key is not Ed25519")
    try:
        key.verify(signature, payload)
    except InvalidSignature as error:
        raise DomainError("bootstrap publisher signature is invalid") from error


def require_regular_file(path: Path, owner: str) -> None:
    try:
        mode = os.lstat(path).st_mode
    except OSError as error:
        raise DomainError(f"{owner} inspection failed path={path}: {error}") from error
    if not stat.S_ISREG(mode):
        raise DomainError(f"{owner} must be a regular file: {path}")


def require_directory(path: Path, owner: str) -> None:
    try:
        mode = os.lstat(path).st_mode
    except OSError as error:
        raise DomainError(f"{owner} inspection failed path={path}: {error}") from error
    if not stat.S_ISDIR(mode):
        raise DomainError(f"{owner} must be a directory: {path}")
