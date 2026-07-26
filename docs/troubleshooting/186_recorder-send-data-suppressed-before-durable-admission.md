# Recorder send_data가 durable admission 전에 억제됨

> ID: TS-186
> Category: Recorder ingress / Data delivery
> Owner: recorder-ingress
> Status: active

## Symptoms

- VRecorder 연결은 유지되지만 VitalServer의 waveform, bed activity, packet history가 갱신되지 않거나 간헐적으로 비어 보입니다.
- `/recorder-ingress/status`에서 `spool.mode`가 `spool_and_replay`이고 `spool.writeFailures`, `rejectedEvents`, `replay.lastFailure` 중 하나가 증가할 수 있습니다.
- Recorder는 `send_data`를 보냈지만 client-visible admission ACK나 reject를 받지 않습니다.

신규 0.2.1 설치에서 `spool.mode=observe_only`, replay `disabled`, Helper의
`observing, direct delivery preserved, load control unavailable` 표시는 이
장애가 아니라 안정화 기본 경계입니다.

## Impact

`spool_only` 또는 `spool_and_replay`에서 spool admission이 실패하면 원본
`send_data`가 upstream VitalServer에 도달하지 않을 수 있습니다. 이 경우
실시간 waveform과 VitalServer Redis 상태가 누락될 수 있으며, Recorder가
성공으로 오인할 가능성이 있습니다.

## Cause

0.2.1의 WebSocket relay와 Redis spool write는 하나의 synchronous durable
transaction이 아닙니다.

1. relay는 mode만 보고 원본 `send_data` frame을 즉시 억제합니다.
2. Socket.IO audit 경로는 spool write를 비동기로 요청합니다.
3. Redis admission 실패를 Recorder에 돌려주는 durable ACK protocol이 없습니다.

따라서 `spool_and_replay`는 persistence 성공을 확인하기 전에 원본 전달을
막을 수 있습니다. 실패 시 direct relay로 전환하는 fallback은 중복 전달과
숨은 상태를 만들므로 사용하지 않습니다.

## Checks

```sh
curl -fsS http://127.0.0.1:18321/runtime/recorder-ingress/status
```

응답에서 다음 값을 구분해 확인합니다.

- `spool.mode`
- `spool.status`, `spool.writeFailures`, `spool.rejectedEvents`, `spool.lastFailure`
- `replay.status`, `replay.retryableFailures`, `replay.deadLetteredEvents`, `replay.lastFailure`

Guest runtime 설정의 소유 값도 확인합니다.

```sh
sudo /usr/local/bin/vitalserver-vm runtime settings
```

읽기 실패나 decode 실패를 기본값으로 간주하지 않습니다.

## Actions

신규 설치는 `observe_only`를 사용합니다. 기존 설치는 설정 provenance가
없으므로 update가 명시적 `spool_and_replay` 값을 자동으로 덮어쓰지 않습니다.

기존 설치에서 데이터 전달 보존을 우선하려면 Helper Settings에서
`Recorder load control`을 Off로 저장해 `observe_only`로 전환하고 Guest
stack reconcile을 완료합니다. 전환 뒤 status에서 다음을 확인합니다.

- `spool.mode=observe_only`
- `spool.status=disabled`
- `replay.status=disabled`

이 모드는 direct upstream delivery를 보존하고 Redis replay pending을 만들지
않습니다. Audit/metrics와 bounded raw archive 실패는 별도 failure evidence로
남깁니다. Upstream 부하를 제한하지는 않습니다.

## Prevention

- 신규 설치와 누락 설정의 문서화된 기본은 `observe_only`이며 Redis replay pending을 append하지 않습니다.
- Domain/OpenAPI/Guest/Host 계약이 같은 mode 집합을 사용하도록 테스트합니다.
- WebSocket relay 테스트는 `observe_only`에서 원본 text/binary frame이 그대로 전달됨을 증명합니다.
- Helper status는 load control을 성공처럼 표시하지 않고 `unavailable` 경계를 경고로 표시합니다.
- `spool_and_replay`를 안전한 기본으로 되돌리려면 Recorder-visible durable admission ACK와 ACK 이후 frame suppression 계약이 먼저 필요합니다.

## Operational Notes

`observe_only`는 Redis observation/replay spool을 만들지 않습니다. Raw archive
rotation과 cold-path export 수명주기는 별도 계약이며 이 안정화 변경에서
수정하지 않습니다.

## Related Cases

- TS-016
- TS-031
- TS-181

## Follow-up

- 2026-07-27: 신규 0.2.1 설치 기본을 `observe_only`로 변경하고 기존 명시 설정은 보존하는 안정화 경계를 문서화함.
