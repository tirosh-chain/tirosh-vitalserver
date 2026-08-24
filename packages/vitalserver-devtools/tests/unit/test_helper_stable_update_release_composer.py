from __future__ import annotations

import base64
import hashlib
import json
import tarfile
from dataclasses import replace
from pathlib import Path
from unittest.mock import patch

import pytest
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import (
    Ed25519PrivateKey,
    Ed25519PublicKey,
)

from tirosh_vitalserver.devtools.adapters.macos_release import (
    helper_update_layer_artifacts,
)
from tirosh_vitalserver.devtools.adapters.update_bundle import (
    bootstrap_bundle_service,
    trust_store_service,
)
from tirosh_vitalserver.devtools.application.inputs import (
    ComposeHelperStableUpdateReleaseInput,
    HelperStableUpdateLayerArtifactInput,
)
from tirosh_vitalserver.devtools.application.usecases import (
    helper_stable_update_release,
)
from tirosh_vitalserver.devtools.core.errors import DomainError
from tirosh_vitalserver.devtools.core.helper_stable_update_release_models import (
    HelperStableUpdateLayer,
)
from tirosh_vitalserver.devtools.core.update_bootstrap_bundle_models import (
    BuildUpdateBootstrapBundleInput,
    BuildUpdateBootstrapBundleResult,
)


def test_composes_signed_bundle_from_explicit_three_layer_files(
    tmp_path: Path,
) -> None:
    input, public_key = release_input(tmp_path)

    result = helper_stable_update_release.compose(
        input,
        operations(),
    )

    assert result == 0
    bootstrap_bundle_service.verify_bootstrap_bundle(input.output, public_key)
    with tarfile.open(input.output, "r:gz") as archive:
        root = f"update-bootstrap-{input.update_id}"
        regular_files = {
            member.name for member in archive.getmembers() if member.isfile()
        }
        specification_file = archive.extractfile(
            f"{root}/payload/update-specification.json"
        )
        assert specification_file is not None
        specification = json.load(specification_file)
    assert regular_files == {
        f"{root}/bootstrap-envelope.json",
        f"{root}/payload/bin/vitalserver-update",
        f"{root}/payload/update-specification.json",
        *{
            f"{root}/payload/layers/{layer.value}/{role}"
            for layer in HelperStableUpdateLayer
            for role in (
                "artifact",
                "effect-executor",
                "effect-configuration.json",
                "rollback-artifact",
            )
        },
    }
    assert [entry["layer"] for entry in specification["layerPlan"]] == [
        "container",
        "guest-runtime",
        "host-platform",
    ]
    assert specification["layerPlan"][2]["dependsOn"] == [
        "container",
        "guest-runtime",
    ]
    for layer_entry in specification["layerPlan"]:
        assert layer_entry["effectExecutor"]["id"] == (
            f"vitalserver-{layer_entry['layer']}-layer-effect-executor-0.2.2"
        )


def test_rejects_effect_configuration_that_is_not_a_v2_document(
    tmp_path: Path,
) -> None:
    input, _ = release_input(tmp_path)
    container = input.layers[0]
    broken = write_file(
        tmp_path / "broken-container-configuration.json",
        json.dumps({"layer": "container"}) + "\n",
    )
    invalid = ComposeHelperStableUpdateReleaseInput(
        **{
            **input.__dict__,
            "layers": (
                replace(container, effect_configuration=broken),
                *input.layers[1:],
            ),
        }
    )

    with pytest.raises(
        DomainError,
        match="container effect configuration fields differ",
    ):
        helper_stable_update_release.compose(invalid, operations())


def test_rejects_effect_configuration_whose_executor_id_is_empty(
    tmp_path: Path,
) -> None:
    input, _ = release_input(tmp_path)
    container = input.layers[0]
    empty_id = write_file(
        tmp_path / "empty-executor-id-configuration.json",
        json.dumps(
            {
                "schemaVersion": (
                    "vitalserver.guest-owner-layer-effect-configuration/v2"
                ),
                "layer": "container",
                "effectExecutorId": "",
                "requestTimeoutSeconds": 60,
                "operationTimeoutSeconds": 900,
                "pollIntervalMilliseconds": 500,
                "apply": {
                    "expectedIdentity": "container-0.2.1",
                    "targetIdentity": "container-0.2.2",
                },
                "rollback": {
                    "expectedIdentity": "container-0.2.2",
                    "targetIdentity": "container-0.2.1",
                },
            }
        )
        + "\n",
    )
    invalid = ComposeHelperStableUpdateReleaseInput(
        **{
            **input.__dict__,
            "layers": (
                replace(container, effect_configuration=empty_id),
                *input.layers[1:],
            ),
        }
    )

    with pytest.raises(
        DomainError,
        match="effectExecutorId must be a non-empty",
    ):
        helper_stable_update_release.compose(invalid, operations())


def test_rejects_missing_effect_configuration(tmp_path: Path) -> None:
    input, _ = release_input(tmp_path)
    container = input.layers[0]
    missing = tmp_path / "missing-configuration.json"
    invalid = ComposeHelperStableUpdateReleaseInput(
        **{
            **input.__dict__,
            "layers": (
                replace(container, effect_configuration=missing),
                *input.layers[1:],
            ),
        }
    )

    with pytest.raises(DomainError, match="inspection failed"):
        helper_stable_update_release.compose(invalid, operations())


def test_rejects_undecodable_effect_configuration(tmp_path: Path) -> None:
    input, _ = release_input(tmp_path)
    container = input.layers[0]
    undecodable = tmp_path / "undecodable-configuration.json"
    undecodable.write_bytes(b"\xff\xfe\x00invalid-utf8")
    invalid = ComposeHelperStableUpdateReleaseInput(
        **{
            **input.__dict__,
            "layers": (
                replace(container, effect_configuration=undecodable),
                *input.layers[1:],
            ),
        }
    )

    with pytest.raises(DomainError, match="decode failed"):
        helper_stable_update_release.compose(invalid, operations())


def test_rejects_effect_configuration_with_invalid_executor_identifier(
    tmp_path: Path,
) -> None:
    input, _ = release_input(tmp_path)
    container = input.layers[0]
    invalid_id = write_file(
        tmp_path / "invalid-executor-id-configuration.json",
        json.dumps(
            {
                "schemaVersion": (
                    "vitalserver.guest-owner-layer-effect-configuration/v2"
                ),
                "layer": "container",
                "effectExecutorId": "not a valid identifier!",
                "requestTimeoutSeconds": 60,
                "operationTimeoutSeconds": 900,
                "pollIntervalMilliseconds": 500,
                "apply": {
                    "expectedIdentity": "container-0.2.1",
                    "targetIdentity": "container-0.2.2",
                },
                "rollback": {
                    "expectedIdentity": "container-0.2.2",
                    "targetIdentity": "container-0.2.1",
                },
            }
        )
        + "\n",
    )
    invalid = ComposeHelperStableUpdateReleaseInput(
        **{
            **input.__dict__,
            "layers": (
                replace(container, effect_configuration=invalid_id),
                *input.layers[1:],
            ),
        }
    )

    with pytest.raises(DomainError, match="not a stable ASCII identifier"):
        helper_stable_update_release.compose(invalid, operations())


def test_effect_configuration_is_read_once_and_materializes_validated_bytes(
    tmp_path: Path,
) -> None:
    input, _ = release_input(tmp_path)
    source = input.layers[0].effect_configuration
    validated = source.read_bytes()
    tampered = b'{"layer": "container"}\n'

    real_read_bytes = Path.read_bytes
    reads: list[Path] = []

    def read_once(self: Path) -> bytes:
        if self == source:
            reads.append(self)
            return validated if len(reads) == 1 else tampered
        return real_read_bytes(self)

    with patch.object(Path, "read_bytes", read_once):
        result = helper_stable_update_release.compose(input, operations())

    assert result == 0
    assert reads == [source]
    with tarfile.open(input.output, "r:gz") as archive:
        root = f"update-bootstrap-{input.update_id}"
        config_file = archive.extractfile(
            f"{root}/payload/layers/container/effect-configuration.json"
        )
        specification_file = archive.extractfile(
            f"{root}/payload/update-specification.json"
        )
        assert specification_file is not None
        specification = json.load(specification_file)
        assert config_file is not None
        materialized = config_file.read()
    assert materialized == validated
    container_entry = next(
        entry for entry in specification["layerPlan"] if entry["layer"] == "container"
    )
    assert container_entry["effectExecutor"]["configurationArtifact"] == {
        "id": "helper-container-effect-configuration",
        "relativePath": "payload/layers/container/effect-configuration.json",
        "sha256": hashlib.sha256(validated).hexdigest(),
        "sizeBytes": len(validated),
        "mediaType": (
            "application/vnd.tirosh.vitalserver.update-layer-effect-configuration+json"
        ),
    }


def test_same_explicit_inputs_produce_identical_specification(
    tmp_path: Path,
) -> None:
    input, _ = release_input(tmp_path)
    specifications: list[bytes] = []

    def observe_build(
        build_input: BuildUpdateBootstrapBundleInput,
    ) -> BuildUpdateBootstrapBundleResult:
        specifications.append(build_input.specification.read_bytes())
        return bootstrap_bundle_service.build_bootstrap_bundle(build_input)

    helper_stable_update_release.compose(
        input,
        helper_stable_update_release.HelperStableUpdateReleaseOperations(
            materialize_payload=(
                helper_update_layer_artifacts.materialized_helper_update_payload
            ),
            build_bundle=observe_build,
            require_active_publisher_key=(
                trust_store_service.read_active_publisher_key
            ),
        ),
    )
    second = ComposeHelperStableUpdateReleaseInput(
        **{**input.__dict__, "output": tmp_path / "second.tar.gz"}
    )
    helper_stable_update_release.compose(
        second,
        helper_stable_update_release.HelperStableUpdateReleaseOperations(
            materialize_payload=(
                helper_update_layer_artifacts.materialized_helper_update_payload
            ),
            build_bundle=observe_build,
            require_active_publisher_key=(
                trust_store_service.read_active_publisher_key
            ),
        ),
    )

    assert specifications[0] == specifications[1]
    assert input.output.read_bytes() == second.output.read_bytes()


def test_missing_explicit_rollback_is_not_inferred(
    tmp_path: Path,
) -> None:
    input, _ = release_input(tmp_path)
    missing = input.layers[0].rollback_artifact
    missing.unlink()

    with pytest.raises(
        DomainError,
        match="container rollback artifact inspection failed",
    ):
        helper_stable_update_release.compose(input, operations())


def test_rejects_missing_or_reordered_layer_source_contract(
    tmp_path: Path,
) -> None:
    input, _ = release_input(tmp_path)
    invalid = ComposeHelperStableUpdateReleaseInput(
        **{**input.__dict__, "layers": tuple(reversed(input.layers))}
    )

    with pytest.raises(
        DomainError,
        match="layers must be supplied exactly once in order",
    ):
        helper_stable_update_release.compose(invalid, operations())


def release_input(
    root: Path,
) -> tuple[ComposeHelperStableUpdateReleaseInput, Path]:
    sources = root / "sources"
    layers: list[HelperStableUpdateLayerArtifactInput] = []
    for layer in HelperStableUpdateLayer:
        layer_root = sources / layer.value
        artifact = write_file(layer_root / "artifact.tar", f"{layer.value}:apply")
        executor = write_file(
            layer_root / "effect-executor",
            f"#!/bin/sh\n# {layer.value}\n",
        )
        executor.chmod(0o755)
        configuration = write_file(
            layer_root / "configuration.json",
            effect_configuration(layer),
        )
        rollback = write_file(
            layer_root / "rollback.tar",
            f"{layer.value}:rollback",
        )
        layers.append(
            HelperStableUpdateLayerArtifactInput(
                layer=layer,
                artifact=artifact,
                artifact_media_type="application/x-tar",
                effect_executor=executor,
                effect_configuration=configuration,
                rollback_artifact=rollback,
                rollback_media_type="application/x-tar",
            )
        )
    updater = write_file(root / "vitalserver-update", "#!/bin/sh\n")
    updater.chmod(0o755)
    private_key, public_key = signing_keys(root)
    publisher_trust_store = root / "publisher-trust-store.json"
    public = serialization.load_pem_public_key(public_key.read_bytes())
    assert isinstance(public, Ed25519PublicKey)
    raw_public_key = public.public_bytes(
        encoding=serialization.Encoding.Raw,
        format=serialization.PublicFormat.Raw,
    )
    publisher_trust_store.write_text(
        json.dumps(
            {
                "schemaVersion": "v2",
                "keys": [
                    {
                        "id": "helper-release-key-2026",
                        "algorithm": "ed25519",
                        "publicKey": base64.b64encode(raw_public_key).decode("ascii"),
                        "state": "active",
                    }
                ],
            }
        )
        + "\n",
        encoding="utf-8",
    )
    return (
        ComposeHelperStableUpdateReleaseInput(
            update_id="helper-update-0.2.2",
            specification_id="helper-update-0.2.2-specification",
            product_version="0.2.2",
            runtime_version="0.2.2",
            target_platform="macos",
            target_architecture="arm64",
            layers=tuple(layers),
            next_updater=updater,
            publisher_key_id="helper-release-key-2026",
            publisher_private_key=private_key,
            publisher_trust_store=publisher_trust_store,
            issued_at="2026-07-29T00:00:00Z",
            output=root / "helper-update-0.2.2.tar.gz",
        ),
        public_key,
    )


def operations() -> helper_stable_update_release.HelperStableUpdateReleaseOperations:
    return helper_stable_update_release.HelperStableUpdateReleaseOperations(
        materialize_payload=(
            helper_update_layer_artifacts.materialized_helper_update_payload
        ),
        build_bundle=bootstrap_bundle_service.build_bootstrap_bundle,
        require_active_publisher_key=trust_store_service.read_active_publisher_key,
    )


def write_file(path: Path, contents: str) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(contents, encoding="utf-8")
    return path


def effect_configuration(layer: HelperStableUpdateLayer) -> str:
    executor_id = f"vitalserver-{layer.value}-layer-effect-executor-0.2.2"
    if layer is HelperStableUpdateLayer.HOST_PLATFORM:
        return (
            json.dumps(
                {
                    "schemaVersion": (
                        "vitalserver.host-platform-layer-effect-configuration/v1"
                    ),
                    "effectExecutorId": executor_id,
                }
            )
            + "\n"
        )
    return (
        json.dumps(
            {
                "schemaVersion": (
                    "vitalserver.guest-owner-layer-effect-configuration/v2"
                ),
                "layer": layer.value,
                "effectExecutorId": executor_id,
                "requestTimeoutSeconds": 60,
                "operationTimeoutSeconds": 900,
                "pollIntervalMilliseconds": 500,
                "apply": {
                    "expectedIdentity": f"{layer.value}-release-0.2.1",
                    "targetIdentity": f"{layer.value}-release-0.2.2",
                },
                "rollback": {
                    "expectedIdentity": f"{layer.value}-release-0.2.2",
                    "targetIdentity": f"{layer.value}-release-0.2.1",
                },
            }
        )
        + "\n"
    )


def signing_keys(root: Path) -> tuple[Path, Path]:
    private_key = root / "publisher-private.pem"
    public_key = root / "publisher-public.pem"
    key = Ed25519PrivateKey.generate()
    private_key.write_bytes(
        key.private_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PrivateFormat.PKCS8,
            encryption_algorithm=serialization.NoEncryption(),
        )
    )
    public_key.write_bytes(
        key.public_key().public_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PublicFormat.SubjectPublicKeyInfo,
        )
    )
    return private_key, public_key
