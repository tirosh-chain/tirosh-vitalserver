Feature: Host product installation lifecycle
  A macOS product package must not infer that old Host files are safe to
  overwrite. The Host Installation Manager owns the admission and activation
  transaction, while package scripts transport only explicit contracts.

  Scenario: A clean Host installs one immutable release safely
    Given C48 declares one release slot, current link, two launchd services, and separate mutable stores
    And C49 explicitly observes the receipt, release catalog and slot, current link, service registrations and definition bytes, stores, and journal as absent
    When C50 preflight is requested for the declared release
    Then the manager records a preflight-verified journal
    When C50 service quiescence succeeds for exactly the C48 launchd services
    Then the manager records activation-pending before the package writes release bytes
    When the package writes the declared slot and every C48 payload digest matches
    Then activation atomically points current at that slot and records an activated receipt

  Scenario: A version-changing direct package invocation is not an update
    Given C49 observes an installed package receipt or current link for another release
    When a package requests C50 preflight for a different declared release
    Then the manager returns direct-version-upgrade-requires-staged-updater
    And the package does not overwrite the immutable slot or mutable stores

  Scenario: Residue is never treated as an empty Host
    Given C49 observes absent receipt and remaining data, service registration or definition, release catalog or slot, link, or unreadable resource state
    When a package requests C50 preflight
    Then the manager records a typed blocked receipt
    And it does not delete the residue as a package-script fallback
