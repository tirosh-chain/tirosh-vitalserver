Feature: Recorder and Product Lab operation
  운영자는 실제 Recorder와 Lab resource를 구분하고 lifecycle과 activity를 관리할 수 있다.

  @US-RECORDER-001 @recorder @bdd-pending
  Scenario: 실제 VRecorder 연결과 packet activity를 확인한다
    Given VRecorder가 Mac host recorder endpoint에 연결한다
    When VRecorder가 join과 send_data packet을 전송한다
    Then Recorders와 Beds 화면은 VitalDB owner가 관측한 현재 관계를 표시한다
    And activity 화면은 ingress owner가 집계한 요청 window의 packet history를 표시한다
    And observation failure와 packet history failure를 빈 목록으로 바꾸지 않는다

  @US-RECORDER-002 @recorder @delete @bdd-pending
  Scenario: 숨긴 Recorder와 Bed를 완전히 삭제한다
    Given 숨겨진 Recorder와 Bed와 assignment 관계가 owner state에 존재한다
    When 운영자가 Recorder와 Bed delete를 요청한다
    Then delete command의 terminal success가 반환된다
    And 새 owner read에는 대상 Recorder와 Bed가 존재하지 않는다
    And 대상 assignment와 session 관계도 존재하지 않는다

  @US-RECORDER-003 @recorder @visibility @bdd-pending
  Scenario: VRecorder를 데이터 삭제 없이 기본 목록에서 숨기고 복구한다
    Given 운영자가 명시적으로 선택한 visible VRecorder가 있다
    When 운영자가 Hide from list를 요청하고 owner command가 성공한다
    Then 선택한 VRecorder만 기본 목록에서 제외된다
    And 다른 VRecorder를 자동으로 선택하지 않는다
    And Undo 또는 Show in list로 같은 VRecorder를 다시 표시할 수 있다
    When owner command가 실패한다
    Then 현재 선택과 Detail을 유지하고 owner failure를 표시한다

  @US-LAB-001 @product-lab @bdd-pending
  Scenario: Product Lab session의 Recorder를 시작하고 중지한다
    Given Product Lab owner가 scenario catalog와 session state를 제공한다
    When 운영자가 scenario session을 만들고 Recorder start를 요청한다
    Then Lab owner는 Recorder state를 running으로 보고한다
    When 운영자가 running Recorder stop을 요청한다
    Then Lab owner는 terminal stopped state 또는 명시적인 stop failure를 보고한다

  @US-LAB-002 @product-lab @delete @bdd-pending
  Scenario: Product Lab resource와 관계를 정리한다
    Given Product Lab session에 Recorder와 Bed가 연결되어 있다
    When 운영자가 Lab resource delete 또는 reset을 요청한다
    Then active assignment이면 owner가 delete를 명시적으로 거부한다
    And session이 종료된 뒤 delete가 성공하면 Recorder와 Bed와 관계가 함께 제거된다
    And VitalDB read model에도 삭제된 Lab 관계가 남지 않는다
