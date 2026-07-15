Feature: Backup update and recovery
  운영자는 data를 보존하고 검증된 update를 적용하며 실패 원인을 잃지 않고 복구할 수 있다.

  @US-BACKUP-001 @backup @bdd-pending
  Scenario: VitalServer backup을 생성한다
    Given Host runtime state와 Guest Redis backup source가 loaded이다
    When 운영자가 VitalServer backup 생성을 요청한다
    Then backup artifact에는 Host state와 Guest data manifest가 포함된다
    And artifact verification이 통과한 뒤에만 backup success가 보고된다
    And dependency failure는 빈 backup 또는 성공으로 바뀌지 않는다

  @US-UPDATE-001 @update @bdd-pending
  Scenario: 검증된 Product Update를 적용한다
    Given 현재 설치와 호환되는 Product Update bundle이 있다
    When 운영자가 bundle 검증과 적용을 요청한다
    Then manifest와 artifact와 compatibility proof가 먼저 검증된다
    And update operation progress가 persisted owner state로 제공된다
    And activation health proof 이후에만 update success가 보고된다

  @US-UPDATE-002 @update @rollback @bdd-pending
  Scenario: Product Update 실패 후 rollback한다
    Given Product Update activation이 terminal failure를 보고했다
    When update workflow가 이전 verified state로 rollback한다
    Then 원래 update failure reason이 보존된다
    And rollback terminal result가 update result와 별도로 기록된다
    And rollback proof가 실패하면 이전 상태가 복구되었다고 표시하지 않는다

  @US-RECOVERY-001 @recovery @bdd-pending
  Scenario: State owner dependency 장애를 진단한다
    Given Platform Agent와 Host database와 Guest Controller 중 하나가 실패한다
    When 운영자가 Status와 Advanced diagnostics를 조회한다
    Then 실패한 owner와 operation과 reason이 표시된다
    And read와 write와 decode와 permission failure가 구분된다
    And UI와 다른 adapter는 missing state나 default success를 생성하지 않는다
