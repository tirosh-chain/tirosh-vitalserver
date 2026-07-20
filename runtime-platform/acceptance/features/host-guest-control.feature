Feature: Host and Guest control ownership
  The Host Agent owns provider lifecycle and Host transport facts.
  The Guest Runtime owns topology and Guest operations.

  Scenario: Start, forward, stop, and recover without composing owner state
    Given a configured Host Agent and independently running Guest Runtime
    When the Host starts the configured Guest provider
    Then the Host lifecycle operation succeeds with provider state running
    And the Host Guest endpoint transport state remains not-checked until an explicit Guest control probe
    When the client reads Guest readiness through the Host facade
    Then the facade returns the Guest response unchanged and the Host records transport reachable
    When the Host stops the configured Guest provider
    Then the Host lifecycle operation succeeds with provider state stopped
    And the facade returns typed unavailable without forwarding to the still-running Guest test process
    When the Host reboots the configured Guest provider
    Then the facade recovers only by a new explicit Guest control probe

  Scenario: Guest topology remains explicit when upstream is absent
    Given the Host facade can reach the Guest Runtime
    When the client applies a RuntimeTopology through the facade
    Then the Guest returns a durable operation
    And the persisted topology status is unsupported with connection not-checked
    And malformed topology input is rejected before a Guest operation exists

  Scenario: Guest topology admission ambiguity is not reported as rejection
    Given the Guest cannot determine whether its atomic topology write committed
    When the client applies a RuntimeTopology directly to the Guest API
    Then the Guest returns CommandAdmissionFailure with admissionState unknown
    And the client retries only the same request ID after Guest recovery

  Scenario: Host lifecycle admission stays explicit when durable admission is uncertain
    Given the Host cannot determine whether a lifecycle operation write committed
    When the client requests a Guest lifecycle action
    Then the Host returns CommandAdmissionFailure with admissionState unknown
    And the Host does not invoke the provider before durable admission is known
    And the client retries only the same request ID after Host recovery

  Scenario: Host terminal outcome persistence does not replay an external effect
    Given the Host recorded a running lifecycle operation before invoking its provider
    And the provider effect completed but terminal outcome persistence failed
    When the client retries the same lifecycle request ID
    Then the Host returns the durable running operation
    And the Host does not invoke the provider a second time

  Scenario: Headless operator control uses the same public facade
    Given an operator supplies the exact Host loopback control endpoint
    When platformctl reads the Host Guest Runtime Control endpoint
    And it requests Guest start with the returned endpoint id and revision
    Then it displays the Host operation returned by the public facade
    And a stale revision remains a typed rejection with its actual HTTP status

  Scenario: Archive provider configuration crosses the Host facade without an export claim
    Given the Guest Archive Export owner has selected one non-secret provider reference
    When platformctl reads Archive Export provider configuration through the Host facade
    Then it receives the Guest-owned provider kind, ID, and capability revision unchanged
    And the response does not claim source finalization, artifact formation, upload, indexing, or provider reachability

  Scenario: External archive credentials stay local while Guest Runtime remains operable
    Given C46 selects an external VitalServer indexed-library provider
    And its C51 credential material has not been provisioned
    When Guest Runtime starts
    Then C60 reports credential material state missing without a user ID or password
    And the public Host edge does not route the C60 credential-material path
    When an OS-authorized C52 local operator provisions exact C51 material matching C46
    Then C60 returns only a provisioned non-secret outcome
    And a later Archive effect may use the private material
    But an unavailable or invalid C51 writes a known failed Archive receipt rather than upload success
