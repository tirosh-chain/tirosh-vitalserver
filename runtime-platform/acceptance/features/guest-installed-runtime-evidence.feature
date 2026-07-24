Feature: Installed Guest runtime and direct-upload evidence
  A release operator needs explicit proof that an installed Guest retained its
  owned operational state across a real Host reboot and attributed a Recorder
  upload through public owner contracts.

  Scenario: First boot is checkpointed only from public owner reads
    Given platformctl uses the installed Host local-control descriptor
    And sysctl reports one stable Host boot-session identifier during observation
    When Guest readiness and C77 are both explicitly available
    Then C78 records the SQLite, PostgreSQL, migration receipt, and non-secret private-material-set identities
    And the runner does not inspect Guest files, databases, processes, logs, or VM disks

  Scenario: Direct upload is verified by Archive lineage rather than HTTP success
    Given a verified first-boot C78 checkpoint
    And the operator selects an approved provenance .vital file and explicit Recorder assignment
    When curl streams the complete file as one multipart Recorder upload
    Then C78 requires the exact source hash, byte size, Recorder upload receipt, and matched Recorder attribution
    And the Recorder artifact page and Archive artifact detail must expose identical owner facts
    And an HTTP success response without matching owner lineage is failed

  Scenario: Post-reboot evidence requires a real Host boot-session transition
    Given a verified first-boot C78 checkpoint
    And verified direct-upload lineage
    When sysctl reports a different stable Host boot-session identifier
    And Guest readiness and C77 are explicitly available again
    Then C78 is verified only if SQLite, PostgreSQL, and bootstrap identities are unchanged

  Scenario: Partial or changed state is failure
    Given a verified first-boot C78 checkpoint
    And verified direct-upload lineage
    When one owner read is unavailable or one stable identity changes after reboot
    Then post-reboot C78 is failed with a typed dependency issue
    And no partial identity is published as evidence
