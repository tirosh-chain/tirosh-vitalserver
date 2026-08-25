# Recorder observability proof crashes on service-start connection reset

> ID: TS-231
> Category: TestKit
> Owner: testkit
> Status: resolved

## Symptoms

`make testkit/recorder-observability/compose-proof`가 compose 기동 직후 raw
traceback으로 실패합니다. recorder-ingress가 `Started` 직후 host probe가
연결을 닫힌 채 받습니다.

```text
Traceback (most recent call last):
  ...
    raise RemoteDisconnected("Remote end closed connection without")
http.client.RemoteDisconnected: Remote end closed connection without response
make: *** [testkit/recorder-observability/compose-proof] Error 1
```

모든 Guest compose 서비스는 healthy이고, ingress `/recorder-ingress/health`는
`curl`로 확인하면 `HTTP 204`입니다. 즉 제품/서비스는 정상인데 증명 스크립트만
건강 대기 첫 probe에서 죽습니다.

## Impact

- 증명 실행 실패. PROOF-* admission/projection/query는 실행되지 않습니다.
- 제품 runtime 상태와 무관합니다. container/데이터는 영향받지 않습니다.

## Cause

`scripts/recorder_observability_compose_e2e.py`의 outbound HTTP adapter
`UrllibHttpClient`가 `http.client.RemoteDisconnected`를 분류하지 않았습니다.
`RemoteDisconnected`는 `OSError` 계열이라 기존 `HTTPError`/`TimeoutError`/
`URLError` 처리에 걸리지 않습니다. `wait_for_ingress_health`는
`TransportError`만 재시도하므로, ingress가 bind되기 전(container `Started`
직후, ~10-20초)의 일시적 connection reset이 raw exception으로 탈출해
90초 ready window가 적용되기 전에 스크립트 전체가 종료됩니다.

## Checks

```sh
# compose 프로젝트 상태와 ephemeral postgres host port
docker compose --project-name vitalserver-recorder-observability-proof \
  --file apps/vitalserver-macos-runtime/Support/Guest/compose.yaml ps -a

# ingress가 실제로 healthy인지
curl -s -o /dev/null -w "%{http_code}\n" \
  http://127.0.0.1:18083/recorder-ingress/health
```

## Actions

`RemoteDisconnected`는 adapter에서 `TransportError(kind="unavailable")`로
분류되고, `wait_for_ingress_health`는 그 typed 결과를 ready deadline(기본
90초)까지 재시도합니다. 증명을 다시 실행하기 전에 기다리거나 ingress health를
수동으로 확인하는 workaround는 필요하지 않습니다. ready deadline을 넘겨
실패하면 sleep이나 fallback을 추가하지 말고, 명시적 서비스 health 증거와
ingress log(`listening on :8080`)로 실패 경계를 분류합니다.

## Prevention

outbound HTTP adapter(`UrllibHttpClient`)가 외부 transport 분류를 전부
소유합니다. `urlopen`에서 나오는 정확한 `http.client.RemoteDisconnected`를
`TransportError(kind="unavailable")`로 매핑합니다. workflow/health wait는
typed 결과만 소비합니다. `timeout`은 `TransportError(kind="timeout")`로
분리 유지합니다. raw `OSError`/`RemoteDisconnected` catch를 workflow에
넣지 않습니다.

## Operational Notes

- ephemeral postgres host port(`--postgres-host-port 0`)는 host port 충돌과
  무관합니다. 이 케이스는 service-start race이며 compose 기동 자체는 성공합니다.
- 재발 시 ingress log(`docker logs <ingress-container>`)에서
  `listening on :8080` 시점과 host probe 시점을 대조합니다.

## Related Cases

- `TS-181` (Recorder observability backlog nginx 413)
- `TS-124` (VitalDB schema migration before Postgres readiness)

## Follow-up

- `2026-08-24`: PR #87 branch에서 adapter가 `RemoteDisconnected`를
  `unavailable`로 매핑하도록 수정하고 재실행. 증명 성공:
  `vrcode=PROOF-20260824T145229Z-09f3975c`, `ok=true`,
  `queryOwner=recorder-ingress`, `queryBaseUrl=http://127.0.0.1:18083`.
