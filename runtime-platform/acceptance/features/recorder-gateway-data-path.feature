Feature: Recorder Gateway durable data path
  The Recorder Gateway owns Socket.IO session state, packet admission, durable ingress state,
  VitalServer delivery replay, cold-path packet capture, and immutable delivery attempt receipts.

  Scenario: A Socket.IO v2 Recorder sends a binary packet through bundled upstream
    Given a bundled-upstream capability has been durably applied by Guest Runtime without claiming a connection
    And a Socket.IO v2 Recorder has joined the Gateway
    When the Recorder sends one binary send_data packet
    Then the Gateway acknowledges only after a C5 IngressReceipt is durable
    And a replay worker records a separate C13 DeliveryReceipt after explicit upstream acknowledgement
    And the public receipt reads validate against their canonical schemas

  Scenario: Backpressure, reconnect, and command scope remain explicit
    Given the Gateway VitalServer delivery replay admission capacity is full
    When a Recorder sends another packet
    Then the Recorder receives rejected delivery replay capacity without a synthetic ingress receipt
    When a disconnected Recorder reconnects without join_vr
    Then send_data is rejected as recorder-session-not-joined
    And req_cmd is acknowledged as unsupported rather than dispatched
