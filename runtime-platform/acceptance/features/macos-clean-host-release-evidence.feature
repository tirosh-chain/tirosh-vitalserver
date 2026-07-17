Feature: macOS clean-Host release evidence
  A release operator needs explicit evidence that one declared macOS package was
  installed on a clean Host and retained its required Host registrations.

  Scenario: A signed C23 package is installed on a clean macOS Host
    Given a C23 macOS release plan names one PKG filename, package identifier, and two launchd services
    And a clean-Host evidence run binds one unchanged PKG SHA-256
    And pkgutil explicitly reports that the C23 package receipt is absent
    And launchctl explicitly reports that both C23 service labels are absent
    When the root release operator explicitly authorizes the installer effect
    And pkgutil reports the exact C23 package receipt as installed
    And launchctl reports both C23 service labels as registered
    Then the runner emits separate C24 clean-install and service-registration proof fragments
    And neither proof claims that the Guest VM started or the Guest Runtime is ready

  Scenario: An ambiguous launchctl failure is not clean-Host evidence
    Given a C23 package artifact passed explicit integrity observation
    When launchctl returns an unrecognised failure while checking a required service label
    Then clean-host preflight is recorded as failed
    And the runner does not execute the installer effect

  Scenario: Reboot proof needs an observed boot-session transition
    Given service-registration evidence was verified
    And the runner persisted a pre-reboot boot-session checkpoint
    When the operator reboots the Host and the runner observes a different boot-session identifier
    Then the reboot proof may be verified only after the C23 receipt and both service labels are observed again
