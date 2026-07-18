Feature: macOS unsigned development installation evidence
  A development operator needs to validate a local macOS installation and the
  Virtualization entitlement before Apple distribution signing is available.

  Scenario: An unsigned package installs an ad-hoc entitled VM Supervisor
    Given a C23 macOS release plan names one PKG filename, package identifier, and two launchd services
    And a development-installation evidence run binds one unchanged unsigned PKG SHA-256
    And pkgutil reports that the PKG metadata matches C23 and its status is no signature
    And pkgutil and launchctl explicitly report the C23 receipt and service labels as absent
    When the root development operator explicitly authorizes the installer effect
    And pkgutil reports the exact C23 package receipt as installed
    And launchctl reports both C23 service labels as registered
    And codesign reports the installed macOS Virtual Machine Supervisor as ad-hoc signed
    And codesign reports com.apple.security.virtualization as true
    Then the runner records development-installation evidence
    And it does not emit a C24 release-delivery proof
    And it does not claim that the Guest VM started or the Guest Runtime is ready

  Scenario: A signed package is not unsigned development evidence
    Given a development-installation evidence run binds one PKG
    When pkgutil reports a package signature instead of Status no signature
    Then artifact identity is recorded as failed
    And the runner does not execute the installer effect

  Scenario: A Developer ID Supervisor is not an ad-hoc development Supervisor
    Given unsigned package installation and C23 service-registration evidence were verified
    When codesign reports the installed VM Supervisor as Developer ID signed
    Then supervisor-signature is recorded as failed
    And the runner does not treat the signature as ad-hoc by fallback

  Scenario: Reboot evidence needs all retained development-install facts
    Given supervisor-signature evidence was verified
    And the runner persisted a pre-reboot boot-session checkpoint
    When the operator reboots the Host and the runner observes a different boot-session identifier
    Then reboot may be verified only after the C23 receipt, both services, and ad-hoc entitled Supervisor are observed again
