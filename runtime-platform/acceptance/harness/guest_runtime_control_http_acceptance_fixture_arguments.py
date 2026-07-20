"""Compose complete input for the Guest Runtime Control HTTP acceptance fixture.

The fixture composes the real Guest Runtime application and its public HTTP
contract without pretending to bind the Linux-only Guest virtio-socket
transport. Every application deployment setting is supplied by the caller so
cross-host HTTP acceptance cannot depend on product executable defaults.
"""

from __future__ import annotations


def compose_explicit_guest_runtime_control_http_acceptance_fixture_arguments(
    *,
    listen_address: str,
    state_database_path: str,
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
