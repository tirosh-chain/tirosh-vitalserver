Feature: Lab lifecycle, artifact export, and deletion evidence

  The Guest Runtime owns Lab execution separately from Archive Export.
  A stopped Lab recorder is eligible for export, but stop itself does not imply
  a finalized artifact, upstream upload, or indexing result.

  Scenario: Stop then explicitly export a Lab virtual recorder
    Given a prepared Lab session with virtual recorders
    When the session is started and then stopped
    Then the Lab session is stopped without an artifact success claim
    When an explicit artifact export is requested for a stopped virtual recorder
    Then an immutable ArtifactManifest and a succeeded ExportReceipt are readable
    And upload and indexing have separate succeeded evidence

  Scenario: A Lab recorder run is a real Gateway capture before Archive sees it
    Given a declared Lab scenario and Guest-loopback Runner and Recorder Gateway processes
    When the Runner starts the virtual recorder and the exact live run is stopped
    Then Gateway has accepted the scenario packets and finalized that exact capture
    And the public packet sequence matches the Gateway finalization receipt digest
    And the Runner publishes its Recorder-owned observation through the named Guest catalog boundary
    And neither Runner nor Gateway claims an Archive upload or indexing result

  Scenario: An operator interface requests export without becoming an Archive owner
    Given a stopped no-export virtual recorder publishes its finalization receipt and revision
    And Archive Export publishes its selected provider reference
    When Console or platformctl submits an artifact export request with those exact facts
    Then Guest Runtime decides admission and owns the resulting Archive operation
    And neither interface creates a source capture, writes a vital file, or claims upload or indexing success

  Scenario: Export failure does not rewrite Lab lifecycle state
    Given a stopped Lab virtual recorder and a provider with a known upload or indexing failure
    When an artifact export is requested
    Then the Archive operation and ExportReceipt are failed with the exact failed step
    And the Lab session remains stopped

  Scenario: An unknown provider outcome does not become a terminal export claim
    Given a stopped Lab virtual recorder and a provider whose upload outcome is unknown
    When an artifact export is requested
    Then the export operation remains running with its immutable manifest evidence
    And no ExportReceipt or terminal upload outcome is guessed
    And repeating the same request returns the same running operation

  Scenario: Hide, detach, and delete are distinct
    Given a stopped Lab session with an exported virtual recorder
    When a recorder is hidden
    Then its visibility changes without deleting its assignment
    When deletion is requested while the recorder remains assigned
    Then deletion is rejected and the recorder remains readable
    When the recorder is detached and a stopped session is deleted with owned-resources cascade
    Then every Lab session, bed, and recorder read model is empty or missing as appropriate
    And the DeletionReceipt names any retained Archive manifest and artifact object
