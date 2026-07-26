# Release Notes

이 문서는 설치와 운영에 영향을 주는 Helper 변경을 요약합니다. 아직 서명된 안정
배포 artifact가 확정되지 않은 항목은 release candidate로 표시합니다.

## 0.2.1 release candidate

### Recorder observability

- observation v2와 boot-event v2를 수락합니다.
- Recorder Detail에서 evidence health, 현재 boot-loop 및 반복 저전압 assessment를
  확인할 수 있습니다.
- Recent reported incidents에서 kernel incident와 boot-loop,
  repeated-undervoltage, ledger-continuity 이력을 함께 확인할 수 있습니다.
- boot evidence의 epoch/ordinal이 이어지지 않아 순서를 비교할 수 없으면
  `nonOrderable`로 표시하고 과거 current boot를 임의로 덮어쓰지 않습니다.

### 호환성

Helper 0.2.1은 기존 observation v1과 boot-event v1도 계속 수락합니다. 기존
Recorder를 유지한 채 Helper부터 올릴 수 있습니다.

Recorder 0.2.6 후보는 observation v2와 boot-event v2를 발행하므로 Helper 0.2.0
이하에 먼저 배포하면 안 됩니다. 이전 Helper에서는 해당 문서가 quarantine될 수
있습니다.

권장 순서는 다음과 같습니다.

1. Helper 0.2.1 배포와 Guest/Compose readiness 확인
2. 기존 Recorder의 v1 수신이 계속되는지 확인
3. Recorder 한 대를 0.2.6 canary로 배포
4. v2 accepted disposition, buffer, Recorder Detail과 incident history 확인
5. 나머지 Recorder 순차 배포

### 개발 artifact 검증

`make dist/pkg/dev/verify`로 `VitalServerHelper-0.2.1-dev.pkg`의 contract review,
PWA test/build, clean Ubuntu golden rootfs, Compose readiness와 golden disk
runtime boot smoke를 통과했습니다.

개발용 PKG는 unsigned artifact입니다. 서명된 안정 배포본은 release branch,
배포용 signing identity, artifact digest와 실제 설치 acceptance를 별도로
통과해야 합니다.
