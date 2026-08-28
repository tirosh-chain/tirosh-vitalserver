from __future__ import annotations

import hashlib
import json
import tarfile
from dataclasses import dataclass, replace
from pathlib import Path

import pytest
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

from tirosh_vitalserver.devtools.adapters.update_bundle import (
    bootstrap_bundle_service,
)
from tirosh_vitalserver.devtools.core.errors import DomainError
from tirosh_vitalserver.devtools.core.helper_stable_update_release import (
    encode_helper_stable_update_specification,
    helper_stable_update_specification_document,
)
from tirosh_vitalserver.devtools.core.helper_stable_update_release_models import (
    HelperStableUpdateArtifactDeclaration,
    HelperStableUpdateEffectExecutorDeclaration,
    HelperStableUpdateLayer,
    HelperStableUpdateLayerRelease,
    HelperStableUpdateReleasePlan,
    HelperStableUpdateRollbackPlan,
)
from tirosh_vitalserver.devtools.core.update_bootstrap_bundle_models import (
    BuildUpdateBootstrapBundleInput,
)


def test_writes_exact_three_layer_helper_product_update_specification() -> None:
    plan = helper_release_plan()

    document = helper_stable_update_specification_document(plan)

    assert document == {
        "schemaVersion": "vitalserver.product-update-specification/v1",
        "id": "helper-update-0.2.3-specification",
        "bootstrapEnvelopeId": "helper-update-0.2.3",
        "layerPlan": [
            expected_layer_document(
                HelperStableUpdateLayer.CONTAINER,
                depends_on=[],
            ),
            expected_layer_document(
                HelperStableUpdateLayer.GUEST_RUNTIME,
                depends_on=["container"],
            ),
            expected_layer_document(
                HelperStableUpdateLayer.HOST_PLATFORM,
                depends_on=["container", "guest-runtime"],
            ),
        ],
    }
    assert json.loads(encode_helper_stable_update_specification(plan)) == document
    assert encode_helper_stable_update_specification(plan).endswith(b"\n")


def test_rejects_helper_release_when_layer_dependency_is_not_an_earlier_layer() -> None:
    plan = helper_release_plan()
    guest_runtime = plan.layers[1]
    invalid = HelperStableUpdateReleasePlan(
        update_id=plan.update_id,
        specification_id=plan.specification_id,
        layers=(
            plan.layers[0],
            HelperStableUpdateLayerRelease(
                layer=guest_runtime.layer,
                depends_on=(HelperStableUpdateLayer.HOST_PLATFORM,),
                artifact=guest_runtime.artifact,
                effect_executor=guest_runtime.effect_executor,
                rollback=guest_runtime.rollback,
            ),
            plan.layers[2],
        ),
    )

    with pytest.raises(
        DomainError,
        match="dependencies must refer only to earlier layers",
    ):
        helper_stable_update_specification_document(invalid)


def test_preserves_explicit_unsupported_rollback_reason() -> None:
    plan = helper_release_plan(
        host_rollback=HelperStableUpdateRollbackPlan.unsupported(
            "No signed baseline Host Platform release was supplied."
        )
    )

    document = helper_stable_update_specification_document(plan)

    layer_plan = document["layerPlan"]
    assert isinstance(layer_plan, list)
    host_layer = layer_plan[2]
    assert isinstance(host_layer, dict)
    host_rollback = host_layer["rollback"]
    assert host_rollback == {
        "state": "unsupported",
        "artifact": None,
        "reason": "No signed baseline Host Platform release was supplied.",
    }


@pytest.mark.parametrize(
    ("role", "media_type", "message"),
    [
        (
            "executable",
            "application/octet-stream",
            "container effect executor media type is unsupported",
        ),
        (
            "configuration",
            "application/json",
            "container effect configuration media type is unsupported",
        ),
    ],
)
def test_rejects_effect_media_type_not_consumed_by_next_updater(
    role: str,
    media_type: str,
    message: str,
) -> None:
    plan = helper_release_plan()
    container = plan.layers[0]
    executable = container.effect_executor.executable
    configuration = container.effect_executor.configuration
    invalid_executor = replace(
        container.effect_executor,
        executable=(
            replace(executable, media_type=media_type)
            if role == "executable"
            else executable
        ),
        configuration=(
            replace(configuration, media_type=media_type)
            if role == "configuration"
            else configuration
        ),
    )
    invalid = replace(
        plan,
        layers=(
            replace(container, effect_executor=invalid_executor),
            *plan.layers[1:],
        ),
    )

    with pytest.raises(DomainError, match=message):
        helper_stable_update_specification_document(invalid)


def test_rejects_same_bytes_declared_for_two_layer_roles() -> None:
    plan = helper_release_plan()
    container = plan.layers[0]
    rollback_artifact = container.rollback.artifact
    assert rollback_artifact is not None
    invalid = replace(
        plan,
        layers=(
            replace(
                container,
                rollback=HelperStableUpdateRollbackPlan.available(
                    replace(
                        rollback_artifact,
                        sha256=container.artifact.sha256,
                    )
                ),
            ),
            *plan.layers[1:],
        ),
    )

    with pytest.raises(
        DomainError,
        match="container artifact digests must be distinct by role",
    ):
        helper_stable_update_specification_document(invalid)


def test_fake_layer_payload_closure_is_signed_and_verified(
    tmp_path: Path,
) -> None:
    fixture = write_fake_release_payload(tmp_path)
    specification = tmp_path / "update-specification.json"
    specification.write_bytes(encode_helper_stable_update_specification(fixture.plan))
    updater = tmp_path / "vitalserver-update"
    updater.write_bytes(b"fake bundle-owned updater")
    updater.chmod(0o755)
    private_key, public_key = signing_keys(tmp_path)
    output = tmp_path / "helper-update-0.2.3.tar.gz"

    bootstrap_bundle_service.build_bootstrap_bundle(
        BuildUpdateBootstrapBundleInput(
            update_id=fixture.plan.update_id,
            product_version="0.2.3",
            runtime_version="0.2.3",
            target_platform="macos",
            target_architecture="arm64",
            layer_order=[layer.layer.value for layer in fixture.plan.layers],
            next_updater=updater,
            specification=specification,
            payload_root=fixture.payload_root,
            publisher_key_id="helper-release-key-2026",
            publisher_private_key=private_key,
            issued_at="2026-07-29T00:00:00Z",
            output=output,
        )
    )

    bootstrap_bundle_service.verify_bootstrap_bundle(output, public_key)
    with tarfile.open(output, "r:gz") as archive:
        root = f"update-bootstrap-{fixture.plan.update_id}"
        regular_files = {
            member.name for member in archive.getmembers() if member.isfile()
        }
    assert regular_files == {
        f"{root}/bootstrap-envelope.json",
        f"{root}/payload/bin/vitalserver-update",
        f"{root}/payload/update-specification.json",
        *{f"{root}/{path}" for path in fixture.declared_relative_paths},
    }


@dataclass(frozen=True)
class FakeReleasePayload:
    plan: HelperStableUpdateReleasePlan
    payload_root: Path
    declared_relative_paths: frozenset[str]


def write_fake_release_payload(root: Path) -> FakeReleasePayload:
    payload_root = root / "payload-root"
    releases: list[HelperStableUpdateLayerRelease] = []
    declared_paths: set[str] = set()
    previous: list[HelperStableUpdateLayer] = []
    for layer in HelperStableUpdateLayer:
        apply = write_fake_artifact(
            payload_root,
            artifact_id=f"helper-{layer.value}-apply",
            relative_path=f"payload/layers/{layer.value}/apply.tar.gz",
            contents=f"{layer.value} apply".encode(),
            media_type="application/gzip",
        )
        executor = write_fake_artifact(
            payload_root,
            artifact_id=f"helper-{layer.value}-effect-executor",
            relative_path=f"payload/layers/{layer.value}/effect-executor",
            contents=f"{layer.value} executable".encode(),
            media_type=(
                "application/vnd.tirosh.vitalserver.update-layer-effect-executor"
            ),
        )
        (payload_root / executor.relative_path).chmod(0o755)
        configuration = write_fake_artifact(
            payload_root,
            artifact_id=f"helper-{layer.value}-effect-configuration",
            relative_path=(f"payload/layers/{layer.value}/effect-configuration.json"),
            contents=b'{"schemaVersion":"fake/v1"}\n',
            media_type=(
                "application/vnd.tirosh.vitalserver."
                "update-layer-effect-configuration+json"
            ),
        )
        rollback = write_fake_artifact(
            payload_root,
            artifact_id=f"helper-{layer.value}-rollback",
            relative_path=f"payload/layers/{layer.value}/rollback.tar.gz",
            contents=f"{layer.value} rollback".encode(),
            media_type="application/gzip",
        )
        releases.append(
            HelperStableUpdateLayerRelease(
                layer=layer,
                depends_on=tuple(previous),
                artifact=apply,
                effect_executor=HelperStableUpdateEffectExecutorDeclaration(
                    executable=executor,
                    configuration=configuration,
                ),
                rollback=HelperStableUpdateRollbackPlan.available(rollback),
            )
        )
        declared_paths.update(
            {
                apply.relative_path,
                executor.relative_path,
                configuration.relative_path,
                rollback.relative_path,
            }
        )
        previous.append(layer)
    return FakeReleasePayload(
        plan=HelperStableUpdateReleasePlan(
            update_id="helper-update-0.2.3",
            specification_id="helper-update-0.2.3-specification",
            layers=tuple(releases),
        ),
        payload_root=payload_root,
        declared_relative_paths=frozenset(declared_paths),
    )


def helper_release_plan(
    *,
    host_rollback: HelperStableUpdateRollbackPlan | None = None,
) -> HelperStableUpdateReleasePlan:
    releases: list[HelperStableUpdateLayerRelease] = []
    previous: list[HelperStableUpdateLayer] = []
    for layer in HelperStableUpdateLayer:
        releases.append(
            HelperStableUpdateLayerRelease(
                layer=layer,
                depends_on=tuple(previous),
                artifact=artifact_declaration(layer, "apply", "application/gzip"),
                effect_executor=HelperStableUpdateEffectExecutorDeclaration(
                    executable=artifact_declaration(
                        layer,
                        "effect-executor",
                        (
                            "application/vnd.tirosh.vitalserver."
                            "update-layer-effect-executor"
                        ),
                    ),
                    configuration=artifact_declaration(
                        layer,
                        "effect-configuration",
                        (
                            "application/vnd.tirosh.vitalserver."
                            "update-layer-effect-configuration+json"
                        ),
                    ),
                ),
                rollback=(
                    host_rollback
                    if layer is HelperStableUpdateLayer.HOST_PLATFORM
                    and host_rollback is not None
                    else HelperStableUpdateRollbackPlan.available(
                        artifact_declaration(
                            layer,
                            "rollback",
                            "application/gzip",
                        )
                    )
                ),
            )
        )
        previous.append(layer)
    return HelperStableUpdateReleasePlan(
        update_id="helper-update-0.2.3",
        specification_id="helper-update-0.2.3-specification",
        layers=tuple(releases),
    )


def artifact_declaration(
    layer: HelperStableUpdateLayer,
    role: str,
    media_type: str,
) -> HelperStableUpdateArtifactDeclaration:
    return HelperStableUpdateArtifactDeclaration(
        artifact_id=f"helper-{layer.value}-{role}",
        relative_path=f"payload/layers/{layer.value}/{role}",
        sha256=role_digest(layer, role),
        size_bytes=len(f"{layer.value}:{role}".encode()),
        media_type=media_type,
    )


def role_digest(layer: HelperStableUpdateLayer, role: str) -> str:
    return hashlib.sha256(f"{layer.value}:{role}".encode()).hexdigest()


def expected_layer_document(
    layer: HelperStableUpdateLayer,
    *,
    depends_on: list[str],
) -> dict[str, object]:
    apply = artifact_declaration(layer, "apply", "application/gzip")
    executor = artifact_declaration(
        layer,
        "effect-executor",
        "application/vnd.tirosh.vitalserver.update-layer-effect-executor",
    )
    configuration = artifact_declaration(
        layer,
        "effect-configuration",
        ("application/vnd.tirosh.vitalserver.update-layer-effect-configuration+json"),
    )
    rollback = artifact_declaration(layer, "rollback", "application/gzip")
    return {
        "layer": layer.value,
        "dependsOn": depends_on,
        "artifact": artifact_document(apply),
        "effectExecutor": {
            **artifact_document(executor),
            "configurationArtifact": artifact_document(configuration),
        },
        "rollback": {
            "state": "available",
            "artifact": artifact_document(rollback),
            "reason": None,
        },
    }


def artifact_document(
    artifact: HelperStableUpdateArtifactDeclaration,
) -> dict[str, object]:
    return {
        "id": artifact.artifact_id,
        "relativePath": artifact.relative_path,
        "sha256": artifact.sha256,
        "sizeBytes": artifact.size_bytes,
        "mediaType": artifact.media_type,
    }


def write_fake_artifact(
    root: Path,
    *,
    artifact_id: str,
    relative_path: str,
    contents: bytes,
    media_type: str = "application/octet-stream",
) -> HelperStableUpdateArtifactDeclaration:
    path = root / relative_path
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(contents)
    return HelperStableUpdateArtifactDeclaration(
        artifact_id=artifact_id,
        relative_path=relative_path,
        sha256=hashlib.sha256(contents).hexdigest(),
        size_bytes=len(contents),
        media_type=media_type,
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
