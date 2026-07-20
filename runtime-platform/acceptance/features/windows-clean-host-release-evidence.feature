Feature: Windows clean-Host release evidence
  A release operator needs explicit evidence that one declared MSI was
  installed on a clean Windows Host and retained the declared SCM services.

  Scenario: A C23-selected MSI is installed on a clean Windows Host
    Given a C23 Windows release plan names one MSI and three SCM services
    And a clean-Host evidence run binds one unchanged MSI SHA-256 and ProductCode
    And reg.exe explicitly reports the ProductCode absent
    And sc.exe explicitly reports all three C23 service names absent
    And the declared product installation root is absent
    When the elevated release operator authorizes the MSI installer stage with authorize-clean-install
    And reg.exe reports the exact C23 product version installed
    And sc.exe reports all three C23 service names registered
    Then the runner emits separate C24 clean-install and service-registration proof fragments
    And neither proof claims that Hyper-V started the Guest or that Guest Runtime is ready

  Scenario: An ambiguous SCM error is not clean-Host evidence
    Given a C23 MSI passed explicit integrity observation
    When sc.exe returns an unrecognised failure while checking a required C23 service
    Then clean-host preflight is recorded as failed
    And the runner does not execute the MSI installer effect

  Scenario: Reboot proof needs an observed Windows boot-session transition
    Given service-registration evidence was verified
    And the runner persisted a pre-reboot Windows boot-session checkpoint
    When the operator reboots Windows and the runner observes a different boot-session identifier
    Then reboot proof may be verified only after the MSI receipt, product root, and all three services are observed again

  Scenario: Host-platform update joins internal evidence with Windows-native facts
    Given reboot evidence was verified for one C23-selected MSI
    And C29, C28, C55 apply, C48, and C49 prove one succeeded Host-platform update
    When the runner records the explicit update transition inputs
    Then fresh reg.exe, SCM, and product-root observations must agree with C48/C49
    And a C55 receipt alone cannot become a verified C24 update

  Scenario: Rollback proves the restored release in a separate run
    Given reboot evidence was verified for one C23-selected MSI
    And failed C29 plus succeeded C28/C55 rollback prove a restored C48/C49 release
    When the runner records the rollback transition
    Then fresh DisplayVersion observes the restored release rather than the attempted C23 target
    And the run cannot mix that rollback with a successful update transition

  Scenario: C54 preservation removal cannot silently become a reinstall
    Given reboot evidence was verified for one C48 MSI release slot and mutable data root
    When the operator authorizes the preserving uninstall/reinstall operation with authorize-uninstall-reinstall
    Then the runner observes the ProductCode, all three SCM services, and immutable release root absent
    And it observes the separately declared mutable data root present
    And it requires a completed C54 receipt for the exact installation and release before MSI reinstallation
    And an invalid, missing, or mismatched receipt records a failed stage without running the reinstall effect
