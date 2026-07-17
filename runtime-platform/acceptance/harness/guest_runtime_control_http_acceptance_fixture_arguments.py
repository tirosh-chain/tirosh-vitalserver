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
    archive_export_outcome_mode: str,
    external_upstream_outcome_mode: str,
    outbound_relay_outcome_mode: str,
    guest_node_id: str,
    time_authority_id: str,
    time_probe_outcome_mode: str,
    telemetry_collector_probe_outcome_mode: str,
    telemetry_export_outcome_mode: str,
) -> list[str]:
    return [
        "--listen", listen_address,
        "--state-db", state_database_path,
        "--service-version", service_version,
        "--instance-id", instance_id,
        "--archive-provider-kind", "lab-simulation-archive",
        "--archive-provider-id", "bundled-archive",
        "--archive-provider-capability-revision", "1",
        "--archive-provider-mode", archive_export_outcome_mode,
        "--external-upstream-observation-provider-kind", "external-capability-profile",
        "--external-upstream-observation-provider-id", "external-upstream",
        "--external-upstream-observation-provider-capability-revision", "1",
        "--external-upstream-observation-provider-mode", external_upstream_outcome_mode,
        "--outbound-relay-observation-provider-kind", "outbound-relay-profile",
        "--outbound-relay-observation-provider-id", "outbound-relay",
        "--outbound-relay-observation-provider-capability-revision", "1",
        "--outbound-relay-observation-provider-mode", outbound_relay_outcome_mode,
        "--guest-node-id", guest_node_id,
        "--time-authority-id", time_authority_id,
        "--time-provider-mode", time_probe_outcome_mode,
        "--telemetry-pipeline-mode", telemetry_collector_probe_outcome_mode,
        "--telemetry-export-mode", telemetry_export_outcome_mode,
    ]
