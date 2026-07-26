from tirosh_guest_tools.contracts import (
    RuntimeBootstrapEvidenceFileName,
    RuntimeFileName,
    RuntimeDiagnosticsArtifactFileName,
)


def test_runtime_file_names_do_not_own_diagnostics_artifact_names() -> None:
    assert not hasattr(RuntimeFileName, "RUNTIME_STATE")
    assert not hasattr(RuntimeFileName, "BOOTSTRAP_RESULT")
    assert not hasattr(RuntimeFileName, "VM_IP")


def test_diagnostics_artifact_file_names_are_stable() -> None:
    assert (
        RuntimeDiagnosticsArtifactFileName.RUNTIME_OBSERVATION.value
        == "runtime-observation.json"
    )
    assert (
        RuntimeDiagnosticsArtifactFileName.BOOTSTRAP_RESULT.value
        == "bootstrap-result.json"
    )


def test_bootstrap_evidence_file_names_are_stable() -> None:
    assert RuntimeBootstrapEvidenceFileName.VM_IP.value == "vm-ip"
