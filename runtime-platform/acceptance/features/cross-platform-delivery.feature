Feature: Cross-platform provider selection and delivery proof
  The Host Agent reads exactly one C33 deployment configuration and selects exactly one explicitly configured platform provider.
  Portable acceptance proves the C21/C10 composition only; a real OS clean-host
  runner is required before C24 can claim installation or release success.

  Scenario: Windows provider request id and endpoint revision are replay-safe
    Given C33 configures Host Agent with the windows-hyperv-scm bridge fixture
    When I start the Guest with request id "windows-start-1" and the current endpoint revision
    And I repeat that exact command
    Then the bridge is invoked exactly once with that request id and revision
    And a different command with the same request id is rejected
    And a stale endpoint revision is rejected before any bridge invocation

  Scenario: Linux provider failure does not choose another provider
    Given C33 configures Host Agent with the linux-kvm-libvirt-systemd bridge fixture
    And the selected bridge explicitly reports unavailable
    When I start the Guest
    Then the Host operation is failed with the provider issue
    And the endpoint provider and transport observations are unavailable
    And no macOS or Windows provider invocation occurs

  Scenario: A package cannot be called released without clean-host evidence
    Given a C23 delivery plan has every required proof stage
    And C24 records a stage as pending because no OS clean-host runner was assigned
    When the release-ready gate runs
    Then it fails with the explicit pending proof labels
