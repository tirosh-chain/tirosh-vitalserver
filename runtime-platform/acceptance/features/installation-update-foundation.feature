Feature: Installable product update foundation
  The Host owns durable update admission and recovery state.  A current
  updater verifies only a small signed bootstrap envelope, then hands control
  to the signed next updater that understands the evolving product plan.

  Background:
    Given a release has a signed immutable C25 bootstrap envelope
    And the envelope declares explicit Guest runtime, Container, and Host platform layers
    And the Host installation has a known revision

  Scenario: A next updater settles an explicitly ordered layered update
    When the Host admits a C27 update command with that installation revision
    Then it stores a C29 journal in handoff-pending state before the handoff effect
    And replaying the exact request id does not stage or hand off again
    When the staged next updater validates a matching C26 specification
    And it reports C28 succeeded evidence in the bootstrap-declared layer order
    Then the Host advances the installed release exactly once
    And replaying the exact completion report is idempotent

  Scenario: Restart repeats only a durable handoff
    Given a Host has persisted a handoff-pending C29 journal
    When the Host process restarts
    Then it reissues the bootstrapper handoff for that same journal
    And it does not infer or restart an applying next updater

  Scenario: Missing bootstrap trust does not become update success
    Given the selected native bootstrapper reports unavailable
    When the Host admits an update command
    Then its operation and journal are terminal failed with the typed bootstrap issue
    And no next-updater handoff occurs
    And the installed release revision is unchanged

  Scenario: Invalid, failed, or unsupported layer evidence does not advance release
    Given a staged Host update journal declares Guest runtime before Container
    When the next updater reports Container evidence first
    Then the Host records update-execution-report-invalid as a terminal failure
    And the installed release revision is unchanged
    When the next updater instead returns explicit unsupported evidence with rollback evidence
    Then the Host preserves it as a typed terminal failure
    And the installed release revision is unchanged

  Scenario: A Guest Product update bundle has one explicit activation boundary
    Given the release process selects immutable macOS arm64 next-updater, Guest Product archive, C55 executor, and reverse rollback archive bytes
    When it composes C61 and C26 before the generic release signer creates C25
    Then C26 names only payload-relative bytes with calculated immutable identities
    And C61 names only the Host-loopback C32 bridge and the C59 compare-and-swap release transitions
    And neither release composition nor C25 signing activates Guest state
