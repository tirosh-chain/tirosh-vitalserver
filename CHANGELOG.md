# Changelog

Vital Server Helper의 운영상 중요한 변경사항을 기록합니다.

형식은 [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)를 따릅니다. 아직
서명된 안정 배포 artifact가 확정되지 않은 변경은 `[Unreleased]`에 둡니다.

## [Unreleased]

### 0.2.1 release candidate

#### Added

- Recorder observation v2와 boot-event v2 authoritative JSON Schema를
  Recorder contract manifest의 SHA-256 receipt와 함께 수락합니다.
- Recorder Detail에 evidence health, 현재 boot-loop 및 반복 저전압 assessment를
  typed state로 제공합니다.
- 기존 PostgreSQL accepted event store를 사용해 kernel incident와 boot-event v2
  assessment signal을 최대 30일 범위의 bounded incident history로 조회합니다.
- PWA와 macOS Helper의 Recorder Detail에서 현재 incident assessment와 최근
  20개 reported incident를 표시합니다.

#### Changed

- Recorder incident history는 kernel incident만이 아니라 `boot-loop`,
  `repeated-undervoltage`와 `ledger-continuity` signal을 함께 표현합니다.
- 서로 순서를 비교할 수 없는 boot evidence는 이전 current boot를 덮어쓰지 않고
  `nonOrderable`로 명시합니다.

#### Compatibility

- Helper 0.2.1은 observation v1, boot-event v1과 기존 diagnostic/kernel incident
  v1을 계속 수락하므로 기존 Recorder와 호환됩니다.
- Recorder 0.2.6 후보는 observation v2와 boot-event v2를 활성 계약으로
  발행하므로 Helper 0.2.0 이하보다 먼저 배포하면 안 됩니다. 이전 Helper는 이
  두 문서를 지원하지 않아 quarantine할 수 있습니다.
- 안전한 순서는 Helper 0.2.1 배포와 수신 검증, Recorder 한 대 canary, 나머지
  Recorder 순차 배포입니다.

#### Verification

- `make dist/pkg/dev/verify`로 contract review, PWA test/build, clean Ubuntu golden
  rootfs compile, Docker Compose readiness와 golden disk runtime boot smoke를
  통과했습니다.
- 검증 artifact는 `VitalServerHelper-0.2.1-dev.pkg`입니다. 개발용
  `VM_CODESIGN_IDENTITY=-`로 만든 unsigned PKG이며, 서명된 안정 배포본을
  의미하지 않습니다.
