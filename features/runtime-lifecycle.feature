Feature: VitalServer Helper runtime lifecycle
  운영자는 설치부터 재부팅, 설정, 중지, 삭제까지 Host와 Guest 상태를 명확히 확인할 수 있다.

  @US-INSTALL-001 @installation @bdd-pending
  Scenario: 새 Mac에 VitalServer Helper를 설치한다
    Given Helper package와 managed runtime이 설치되어 있지 않다
    When 운영자가 검증된 PKG를 설치한다
    Then 설치 operation의 단계와 terminal result가 표시된다
    And Platform Agent와 VM과 Guest product service가 각 owner state로 ready를 보고한다
    And 실패하면 failing stage와 reason과 evidence path가 표시된다

  @US-BOOT-001 @boot @bdd-pending
  Scenario: 설치된 Mac을 재부팅한다
    Given Helper가 설치되어 있고 직전 runtime이 정상 상태였다
    When 운영자가 Mac을 재부팅한다
    Then launchd service와 VM provider가 새로운 lifecycle state를 게시한다
    And Host proxy는 현재 runtime endpoint가 loaded인 경우에만 traffic을 전달한다
    And endpoint가 없거나 실패하면 ready로 추정하지 않는다

  @US-STATUS-001 @observability @bdd-pending
  Scenario: Runtime 상태와 장애 원인을 확인한다
    Given Platform Agent와 Guest Runtime Controller가 각자의 상태 계약을 제공한다
    When 운영자가 Status와 Advanced 화면을 연다
    Then 화면은 각 owner가 제공한 상태와 reason을 표시한다
    And missing과 unavailable과 failed와 stale과 empty와 zero를 구분한다
    And 한 owner의 실패를 다른 owner의 성공으로 대체하지 않는다

  @US-SETTINGS-001 @settings @bdd-pending
  Scenario: VM 설정을 변경하고 적용한다
    Given Platform Agent가 완전한 current settings state를 제공한다
    When 운영자가 유효한 desired settings를 저장하고 적용한다
    Then desired revision이 Host settings owner에 저장된다
    And 필요한 component만 activation된다
    And health proof가 완료된 뒤에만 applied revision이 갱신된다

  @US-STOP-001 @runtime-control @bdd-pending
  Scenario: Product runtime을 중지해도 Host control plane을 유지한다
    Given Platform Agent와 product runtime service가 실행 중이다
    When 운영자가 VM runtime stop을 요청한다
    Then product runtime service와 VM은 stop workflow에 따라 중지된다
    And Platform Agent는 loaded 상태를 유지한다
    And 운영자는 Runtime Control API에서 현재 Host state를 계속 조회할 수 있다

  @US-UNINSTALL-001 @uninstall @bdd-pending
  Scenario: Clean uninstall 후 다시 설치할 수 있다
    Given Helper와 Platform Agent와 VM runtime이 설치되어 있다
    When 운영자가 clean uninstall을 완료한다
    Then VM과 일반 managed service가 uninstall order로 중지된다
    And Platform Agent가 마지막 managed service로 중지된다
    And package receipt와 runtime files와 Host state database가 제거된다
    And fresh install preflight가 이전 설치 잔여물을 보고하지 않는다
