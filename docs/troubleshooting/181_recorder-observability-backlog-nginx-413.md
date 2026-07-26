# 181 Recorder observability backlog가 nginx 413으로 거절됨

> ID: TS-181
> Category: Recorder observability / Host proxy / Guest edge
> Owner: recorder-ingress
> Status: active

## Symptoms

Recorder의 신규 관측 요청은 `202 Accepted`를 받지만, 연결 복구 후 한 번에
전송하는 초기 backlog 중 1 MiB를 넘는 묶음은 nginx HTML
`413 Request Entity Too Large`를 받습니다.

## Cause

macOS Host nginx와 Guest edge nginx의 `/api/v1/recorders/` 경로에 request
body 정책이 없어서 nginx 기본 1 MiB 제한이 먼저 적용됐습니다. 이 거절은
Recorder ingress의 명시적인 `maxRequestBytes` 정책에 도달하지 않으므로,
애플리케이션이 소유하는 JSON `request_too_large` 실패 의미도 가립니다.

## Fix direction

Host와 Guest nginx 모두 `/api/v1/recorders/` 경로에만
`client_max_body_size 0;`을 적용합니다. 이는 무제한 관측 수용 정책이
아닙니다. Nginx는 transport body를 전달하고, Recorder ingress가 배포
설정의 `RECORDER_INGRESS_OBSERVABILITY_MAX_REQUEST_BYTES` 값으로 최종
admission을 결정합니다.

기본 애플리케이션 상한은 5 MiB입니다. 이를 넘는 backlog는 nginx 413 대신
Recorder ingress의 typed JSON 413을 받아야 하며, 필요한 경우 Recorder의
묶음 크기 또는 명시적인 ingress 배포 설정을 조정해야 합니다.

## Verification

1 MiB 초과, 5 MiB 이하의 유효한 NDJSON backlog를 Host public endpoint로
보내 `202 Accepted`를 확인합니다. 같은 요청이 Host와 Guest nginx access
log에 모두 보이고 Recorder ingress admission metric에 반영돼야 합니다.

5 MiB 초과 요청은 nginx HTML이 아니라 다음 의미의 JSON 413을 받아야
합니다.

```json
{
  "state": "rejected",
  "reason": "request_too_large",
  "maxRequestBytes": 5242880
}
```

## Prevention

Proxy의 일반 웹 경로 제한을 전역으로 해제하지 않습니다. 대량 body가
계약상 허용되는 `/api/v1/recorders/` transport 경로만 별도로 선언하고,
실제 admission 상한과 실패 응답은 Recorder ingress가 소유합니다.
