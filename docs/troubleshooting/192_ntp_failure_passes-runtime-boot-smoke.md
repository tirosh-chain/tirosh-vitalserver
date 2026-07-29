# TS-192 NTP 실패가 runtime boot smoke를 통과함

## Symptom

`make dist/dmg/dev`와 golden disk runtime boot smoke가 성공하지만, 생성된
`runtime-boot-smoke-manifest.json`의 Guest stack 상태에는 다음과 같은
clock quality 실패가 남는다.

```text
state=failed
issue=chronyc tracking exited with 1: 506 Cannot talk to daemon
```

같은 부팅의 Guest observability에는
`tirosh-vitalserver-apply-time-authority.service`가 failed로 표시될 수 있다.
`data/deploy/time-authority.json`도 존재하지 않는다.

## Cause

기존 golden disk runtime smoke는 `vitalserver-vm` launcher와 Guest만
실행했다. Host 시간 권한과 UDP NTP listener를 소유하는
`vitalserver-platform-agent`는 실행하지 않았다.

따라서 Guest에는 명시적 `time-authority.json`이 제공되지 않았고 chrony
적용 서비스가 실패했다. 동시에 smoke는 required compose service와 HTTP
상태만 필수로 검사하고 Guest `clockQuality`를 합격 조건으로 검사하지 않아
NTP 실패를 제품 compile 성공으로 기록했다.

## Fix direction

golden disk runtime smoke는 격리된 runtime home에서 실제 macOS Platform
Agent를 함께 실행한다.

- Platform Agent는 smoke runtime state database와 Guest IP evidence만 읽는다.
- Runtime Control HTTP listener는 ephemeral port를 사용한다.
- Host NTP listener는 제품 UDP 123과 분리된 명시적 smoke port를 사용한다.
- Platform Agent가 쓴 `time-authority.json`을 Guest timer가 소비한다.
- Guest Control API의 `clockQuality.state`가 `synchronized`가 될 때까지
  제한 시간 안에서 기다린다.
- missing, unsupported, unsynchronized, failed는 각각 그대로 실패 증빙에
  기록하며 성공으로 바꾸지 않는다.
- Platform Agent가 조기 종료되면 smoke는 agent log 경로를 출력하고
  compile을 실패시킨다.

## Prevention

시간 동기화는 chrony package 설치 여부나 systemd unit 존재 여부로
추정하지 않는다. Host listener, Host 계약 발행, Guest 계약 적용, 실제
chrony tracking 결과를 한 경로에서 검증해야 한다.

새 runtime 상태가 API와 PWA에 추가되면 일반 stack readiness 안에 묻어두지
말고 독립된 smoke stage와 실패 메시지를 둔다. VM compile은 해당 상태가
제품 동작의 전제라면 degraded 증빙을 성공으로 통과시키지 않는다.

## Verification

```bash
make internal/vm/golden-rootfs/runtime-smoke \
  VM_RELEASE_FILE=apps/vitalserver-macos-runtime/release-dev.json

jq '.stages[] | select(.name == "clock-quality")' \
  .tmp/vitalserver-vm-golden-runtime-smoke/data/run/runtime-boot-smoke-manifest.json
```

`clock-quality` stage는 `passed`여야 하고, details의
`clockQuality.state`는 `synchronized`여야 한다. `source`, `offsetMs`,
`lastSyncAt`도 Guest chrony가 보고한 값으로 존재해야 한다.

## Follow-up

- GitHub issue: #75
- 최초 확인 runId: `433b4fd7-40f4-4aca-96e1-f6ba99dcb675`
- 최초 실패: `chronyc tracking exited with 1: 506 Cannot talk to daemon`

