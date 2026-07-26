Feature: Linux clean-Host release evidence
  A release operator needs explicit evidence that one declared DEB was
  installed on a clean Linux Host and retained the declared systemd services.

  Scenario: A C23-selected DEB is installed on a clean Linux Host
    Given a C23 Linux release plan names one DEB and three systemd services
    And a clean-Host evidence run binds one unchanged DEB SHA-256 and dpkg package identifier
    And dpkg-query explicitly reports the package absent
    And systemctl explicitly reports all three C23 services not found
    And the declared immutable product root and mutable data root are absent
    When the root release operator authorizes the DEB installer stage with authorize-clean-install
    And dpkg-query reports the exact C23 product version installed
    And systemctl reports all three C23 services loaded
    Then the runner emits separate C24 clean-install and service-registration proof fragments
    And neither proof claims that libvirt started the Guest or that Guest Runtime is ready

  Scenario: A residual dpkg state is not clean-Host evidence
    Given a C23 DEB passed explicit integrity observation
    When dpkg-query reports config-files or another non-installed residual state
    Then clean-host preflight is recorded as failed
    And the runner does not execute the DEB installer effect

  Scenario: Reboot proof needs an observed Linux boot-session transition
    Given service-registration evidence was verified
    And the runner persisted a pre-reboot kernel boot ID checkpoint
    When the operator reboots Linux and the runner observes a different boot ID
    Then reboot proof may be verified only after the package receipt, roots, and all three services are observed again

  Scenario: Host-platform update is a contract fact and a fresh Linux observation
    Given reboot evidence was verified for one C23-selected DEB
    And C29, C28, C55 apply, C48, and C49 prove one succeeded Host-platform update
    When the runner records the explicit update transition inputs
    Then it verifies that fresh dpkg, systemd, and product-root observations agree with C48/C49
    And it emits C24 update evidence without claiming that the C29/C28/C55 documents alone installed the package

  Scenario: Rollback is a separate failed-update evidence run
    Given reboot evidence was verified for one C23-selected DEB
    And C29 is failed while C28 rollback, C55 rollback, C48, and C49 prove the restored release
    When the runner records the explicit rollback transition inputs
    Then fresh dpkg observes the restored C48 product version, not the attempted C23 target version
    And the run cannot also record a successful update transition

  Scenario: Preservation removal is observed before one reinstallation
    Given reboot evidence was verified for the selected C23 DEB
    And the operator supplied a completed C54 receipt for the exact installation and release
    And C54 explicitly selected preserve-mutable-data
    When the root release operator authorizes removal of the declared dpkg package with authorize-uninstall-reinstall
    Then the package receipt, three systemd units, and immutable root must be absent
    And the declared mutable data root must be present
    And only then may the runner reinstall the selected DEB within that same authorize-uninstall-reinstall command
    And the runner records the preservation choice and both OS observations in one C24 uninstall-reinstall fragment
