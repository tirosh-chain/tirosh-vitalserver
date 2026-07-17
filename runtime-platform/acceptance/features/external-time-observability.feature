Feature: External upstream, node time, and diagnostic observability
  The control plane must preserve independent owner state for external
  integrations, node-local time, Recorder self-observation, and telemetry.

  Scenario: External upstream capability does not inherit bundled lifecycle
    Given a Guest Runtime with an available explicit external upstream profile
    When an operator applies an ExternalUpstreamIntegration and references it from RuntimeTopology
    Then RuntimeTopology reports the integration's explicit capability document
    And upstream lifecycle start, stop, update, and backup are explicitly unsupported
    And no bundled capability is inferred

  Scenario: External upstream and relay have independent observation lifecycles
    Given a Guest Runtime whose external upstream is unavailable and relay is available
    When an operator applies both resources
    Then the external resource remains unavailable with its typed issue
    And the relay resource remains available
    And applying one resource does not rewrite the other

  Scenario: Time is owned by the node that configured it
    Given Host and Guest Runtime have separate Time Authority owners
    When each node applies its explicit enterprise NTP profile
    Then synchronized quality includes source, stratum, offset, uncertainty, and last-sync evidence
    And Host time does not create or overwrite Guest clock quality
    And a probe with an unknown outcome leaves its operation running without a guessed resource

  Scenario: Recorder observation preserves device-owned occurrence time
    Given a Recorder emits a self-observation envelope
    When Guest Runtime Catalog ingests it
    Then Catalog preserves occurredAt and records separate received and persisted facts
    And replaying the identical recorder, boot, and sequence identity returns the recorded operation
    And a conflicting envelope for that identity is rejected

  Scenario: Diagnostic telemetry does not become product state
    Given a node has a ready OTLP telemetry pipeline for logs, metrics, and traces
    When it emits an allowlisted signal containing a patient attribute
    Then the receipt records the redacted key and never persists the value
    And bounded cardinality produces a dropped receipt instead of a success claim
    And unavailable or unknown collector outcomes remain explicit without changing topology or delivery state
