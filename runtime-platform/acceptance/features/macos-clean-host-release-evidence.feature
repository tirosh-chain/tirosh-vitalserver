Feature: macOS clean-Host release evidence
  A release operator needs explicit evidence that one declared macOS package was
  installed on a clean Host and retained its required Host registrations.

  Scenario: A C23-policy-matched package is installed on a clean macOS Host
    Given a C23 macOS release plan names one PKG filename, package identifier, signature policy, and three launchd services
    And a clean-Host evidence run binds one unchanged PKG SHA-256
    And pkgutil explicitly reports that the C23 package receipt is absent
    And launchctl explicitly reports that all three C23 service labels are absent
    When the root release operator explicitly authorizes the installer effect
    And pkgutil reports the exact C23 package receipt as installed
    And launchctl reports all three C23 service labels as registered
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
    Then the reboot proof may be verified only after the C23 receipt and all three service labels are observed again

  Scenario: Host-platform update requires both C29/C28/C55/C48/C49 and fresh macOS facts
    Given reboot evidence was verified for one C23-selected PKG
    And C29, C28, C55 apply, C48, and C49 prove one succeeded Host-platform update
    When the runner records the explicit update transition inputs
    Then fresh pkgutil and launchctl observations must agree with C48/C49
    And the C24 update proof does not treat an internal update receipt as a macOS installation fact

  Scenario: Rollback is not the next step after a successful update
    Given reboot evidence was verified for one C23-selected PKG
    And failed C29 plus succeeded C28/C55 rollback prove one restored C48/C49 release
    When the runner records the rollback transition
    Then it records the restored package version and keeps update and rollback in separate evidence runs

  Scenario: Preservation removal cannot be mistaken for a clean reinstall
    Given reboot evidence was verified for one exact C23 PKG
    And the operator explicitly supplies the installed C48 manifest, C50 paths, and new C54 removal paths and identities
    When the root operator authorizes C54 preserve-mutable-data removal
    Then the runner requires a matching completed C54 receipt, absent pkgutil receipt, and absent C23 launchd registrations before it invokes installer
    And it verifies the same bound PKG receipt and all three services after reinstallation
    And a missing or mismatched C54 receipt records failed uninstall-reinstall evidence without reinstalling
