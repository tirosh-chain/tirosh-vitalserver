Feature: Operator control surface
  The desktop console and platformctl are consumers of owner-supplied public
  control contracts. They do not create Host, Guest, Lab, Recorder, or
  upstream state.

  Scenario: A lifecycle command uses the explicit current Host endpoint identity
    Given an operator has read the Host-owned Guest Runtime Control endpoint
    When the operator requests Guest start with its endpoint id and revision
    Then Host Agent either returns the durable Host operation or a typed admission result
    And the interface does not create another request id or revision

  Scenario: A typed control failure remains visible
    Given the Host facade returns a typed non-success response document
    When platformctl or the desktop console displays the result
    Then it preserves the response document and HTTP status
    And it does not display the result as an available success

  Scenario: Local control is not a remote endpoint fallback
    Given an operator supplies a non-loopback control address
    When platformctl or the desktop console validates the address
    Then it rejects the address before sending a control request

  Scenario: An offline update bundle remains Host-owned before and during admission
    Given an operator selects one local signed release-bundle directory
    When the desktop console or platformctl submits C69 import with an explicit request id
    Then Host Agent atomically imports only a complete non-symlinked bundle tree or returns a typed rejection
    And its declared C25 view does not claim signature verification or update success
    When the operator submits the imported bundle id with the current Host installation identity and revision
    Then Host Agent reads C25 from its own bundle store and enters the normal C27/C29 update workflow
    And neither interface constructs C25 or substitutes a payload path after import

  Scenario: Lab lifecycle carries Guest-owned resource revision
    Given an operator creates a prepared Lab session with an explicit new ID and revision zero
    When the interface reads the resulting Guest-owned Lab bed or virtual recorder
    And the operator requests a supported action with that resource ID and revision
    Then the Host facade forwards exactly the named Lab command
    And the interface does not derive a resource ID or revision from a LAB- display name
    And a session delete declares owned-resources while a single resource delete declares none

  Scenario: Manual artifact export carries facts from two explicit owners
    Given a Guest Lab read reports a stopped no-export virtual recorder with a revision and cold-path finalization receipt
    And Archive Export publishes its provider kind, ID, and capability revision
    When the operator requests the named artifact-export command
    Then the Host facade forwards exactly those owner-published facts
    And Console and CLI do not accept a Gateway URL, cold-path filename, provider endpoint, credential, or raw payload
    And a recorder with export-on-stop remains governed by its separate terminal Archive intent

  Scenario: External topology contains references, never a remote secret
    Given a reviewed Guest deployment owns external VitalServer endpoint and credential material
    When an operator applies the named external-upstream command with only those references
    And then applies external-upstream RuntimeTopology using the resulting integration reference
    Then the facade returns each Guest operation or typed admission result unchanged
    And Console and CLI expose no raw URL, header, password, or generic JSON command field

  Scenario: Time and OpenTelemetry remain owner-scoped explicit contracts
    Given Host and Guest each own their NTP authority and OTLP pipeline state
    When an operator applies a time authority with owner scope, node, revision, and source identity
    And applies an OTLP pipeline with owner scope, collector reference, and bounded redaction allowlist
    Then the facade routes each command only to that owner's published endpoint
    And the OTLP signal set remains logs, metrics, and traces
    And Console and CLI expose no NTP host, collector URL, header, password, secret, or raw JSON field
