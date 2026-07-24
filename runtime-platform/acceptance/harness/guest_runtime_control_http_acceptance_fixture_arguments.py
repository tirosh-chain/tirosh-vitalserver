"""Compose complete input for the Guest Runtime Control HTTP acceptance fixture.

The fixture composes the real Guest Runtime application and its public HTTP
contract without pretending to bind the Linux-only Guest virtio-socket
transport. Every application deployment setting is supplied by the caller so
cross-host HTTP acceptance cannot depend on product executable defaults.
"""

from __future__ import annotations

import os
import unittest


def require_recorder_catalog_test_database_url() -> str:
    database_url = os.environ.get(
        "VITALSERVER_RECORDER_CATALOG_TEST_DATABASE_URL"
    )
    if not database_url:
        raise unittest.SkipTest(
            "VITALSERVER_RECORDER_CATALOG_TEST_DATABASE_URL is required "
            "for the real Guest Runtime PostgreSQL acceptance fixture"
        )
    return database_url


def compose_explicit_guest_runtime_control_http_acceptance_fixture_arguments(
    *,
    listen_address: str,
    state_database_path: str,
    bootstrap_evidence_root_directory: str,
    recorder_catalog_database_url: str,
    recorder_catalog_admission_bearer_token: str,
    recorder_observation_max_report_age_seconds: int,
    archive_source_admission_bearer_token: str,
    archive_artifact_object_root_directory: str,
    archive_source_maximum_bytes: int,
    lab_replay_source_object_root_directory: str,
    lab_replay_source_maximum_bytes: int,
    lab_replay_spool_root_directory: str,
    lab_replay_string_track_policy: str,
    lab_replay_gap_policy: str,
    lab_replay_frame_batch_size: int,
    recorder_attribution_policy_kind: str,
    service_version: str,
    instance_id: str,
    archive_export_outcome_mode: str | None,
    recorder_gateway_cold_path_source_endpoint: str,
    lab_recorder_runner_endpoint: str,
    external_upstream_outcome_mode: str,
    outbound_relay_outcome_mode: str,
    guest_node_id: str,
    time_authority_id: str,
    time_probe_outcome_mode: str,
    telemetry_collector_probe_outcome_mode: str,
    telemetry_export_outcome_mode: str,
    external_upstream_observation_provider_kind: str = "external-capability-profile",
    external_upstream_observation_provider_id: str = "external-upstream",
    external_upstream_observation_external_vitalserver_delivery_configuration_path: str | None = None,
    external_upstream_observation_request_timeout_milliseconds: int | None = None,
    archive_provider_kind: str = "archive-export-outcome-profile",
    archive_provider_id: str = "bundled-archive",
    archive_provider_vitalserver_configuration_kind: str | None = None,
    archive_provider_vitalserver_configuration_path: str | None = None,
    archive_provider_credential_material_path: str | None = None,
) -> list[str]:
    arguments = [
        "--listen", listen_address,
        "--state-db", state_database_path,
        "--bootstrap-evidence-root", bootstrap_evidence_root_directory,
        "--recorder-catalog-database-url", recorder_catalog_database_url,
        "--recorder-catalog-admission-bearer-token", recorder_catalog_admission_bearer_token,
        "--recorder-observation-max-report-age-seconds", str(recorder_observation_max_report_age_seconds),
        "--archive-source-admission-bearer-token", archive_source_admission_bearer_token,
        "--archive-artifact-object-root", archive_artifact_object_root_directory,
        "--archive-source-max-bytes", str(archive_source_maximum_bytes),
        "--lab-replay-source-object-root", lab_replay_source_object_root_directory,
        "--lab-replay-source-max-bytes", str(lab_replay_source_maximum_bytes),
        "--lab-replay-spool-root", lab_replay_spool_root_directory,
        "--lab-replay-string-track-policy", lab_replay_string_track_policy,
        "--lab-replay-gap-policy", lab_replay_gap_policy,
        "--lab-replay-frame-batch-size", str(lab_replay_frame_batch_size),
        "--recorder-attribution-policy-kind", recorder_attribution_policy_kind,
        "--service-version", service_version,
        "--instance-id", instance_id,
        "--archive-provider-kind", archive_provider_kind,
        "--archive-provider-id", archive_provider_id,
        "--archive-provider-capability-revision", "1",
        "--recorder-gateway-cold-path-source-endpoint", recorder_gateway_cold_path_source_endpoint,
        "--lab-recorder-runner-endpoint", lab_recorder_runner_endpoint,
        "--external-upstream-observation-provider-kind", external_upstream_observation_provider_kind,
        "--external-upstream-observation-provider-id", external_upstream_observation_provider_id,
        "--external-upstream-observation-provider-capability-revision", "1",
        "--outbound-relay-observation-provider-kind", "outbound-relay-profile",
        "--outbound-relay-observation-provider-id", "outbound-relay",
        "--outbound-relay-observation-provider-capability-revision", "1",
        "--outbound-relay-observation-provider-mode", outbound_relay_outcome_mode,
        "--guest-node-id", guest_node_id,
        "--time-authority-id", time_authority_id,
        "--time-adapter-kind", "time-authority-outcome-profile",
        "--time-provider-mode", time_probe_outcome_mode,
        "--telemetry-adapter-kind", "telemetry-export-outcome-profile",
        "--telemetry-pipeline-mode", telemetry_collector_probe_outcome_mode,
        "--telemetry-export-mode", telemetry_export_outcome_mode,
    ]
    if (
        bootstrap_evidence_root_directory == ""
        or recorder_catalog_database_url == ""
        or recorder_catalog_admission_bearer_token == ""
        or recorder_observation_max_report_age_seconds < 1
        or recorder_observation_max_report_age_seconds > 86400
        or archive_source_admission_bearer_token == ""
        or archive_artifact_object_root_directory == ""
        or archive_source_maximum_bytes < 1
        or lab_replay_source_object_root_directory == ""
        or lab_replay_source_maximum_bytes < 1
        or lab_replay_spool_root_directory == ""
        or lab_replay_string_track_policy not in {"reject", "skip"}
        or lab_replay_gap_policy not in {"omit-track", "fail-frame"}
        or lab_replay_frame_batch_size < 1
        or lab_replay_frame_batch_size > 60
        or recorder_attribution_policy_kind != "recorder-assignment-owner"
    ):
        raise ValueError(
            "Guest Runtime persistence and Recorder attribution inputs must "
            "be complete and explicit"
        )
    if external_upstream_observation_provider_kind == "external-capability-profile":
        if external_upstream_outcome_mode == "" or external_upstream_observation_external_vitalserver_delivery_configuration_path is not None or external_upstream_observation_request_timeout_milliseconds is not None:
            raise ValueError("External Upstream outcome profile requires an explicit outcome mode without C46 inputs")
        arguments.extend(["--external-upstream-observation-provider-mode", external_upstream_outcome_mode])
    elif external_upstream_observation_provider_kind == "external-vitalserver-http":
        if external_upstream_outcome_mode != "" or external_upstream_observation_external_vitalserver_delivery_configuration_path is None or external_upstream_observation_request_timeout_milliseconds is None:
            raise ValueError("External VitalServer HTTP observation requires C46 path and timeout without an outcome mode")
        arguments.extend([
            "--external-upstream-observation-external-vitalserver-delivery-configuration", external_upstream_observation_external_vitalserver_delivery_configuration_path,
            "--external-upstream-observation-request-timeout-milliseconds", str(external_upstream_observation_request_timeout_milliseconds),
        ])
    else:
        raise ValueError("External Upstream observation provider kind is unsupported by the acceptance fixture")
    if archive_provider_kind == "archive-export-outcome-profile":
        if archive_export_outcome_mode is None:
            raise ValueError("Archive Export outcome profile requires an explicit outcome mode")
        arguments.extend(["--archive-provider-mode", archive_export_outcome_mode])
    elif archive_provider_kind == "vitalserver-indexed-library":
        if archive_export_outcome_mode is not None or archive_provider_vitalserver_configuration_kind not in {"external-vitalserver-delivery-configuration", "bundled-vitalserver-topology-deployment"} or archive_provider_vitalserver_configuration_path is None or archive_provider_credential_material_path is None:
            raise ValueError("VitalServer indexed-library provider requires explicit C44-or-C46 kind, configuration path, and credential material path without a profile mode")
        arguments.extend([
            "--archive-provider-vitalserver-configuration-kind", archive_provider_vitalserver_configuration_kind,
            "--archive-provider-vitalserver-configuration", archive_provider_vitalserver_configuration_path,
            "--archive-provider-credential-material-path", archive_provider_credential_material_path,
        ])
    else:
        raise ValueError("Archive provider kind is unsupported by the acceptance fixture")
    return arguments
