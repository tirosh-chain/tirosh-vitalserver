# 152 macOS Host-local HTTP bridge가 nonblocking socket 대기를 연결 종료로 처리함

> 상태: resolved by `GuestRuntimeControlHostLocalHTTPBridgeByteRelaySocketResultPolicy`

## 증상

Guest console에는 다음 두 사실이 모두 남았다.

```text
guest-runtime virtio-socket control listening port=18443
guest-runtime TCP control listening address=[::]:18443
```

그러나 Host `curl http://127.0.0.1:18443/v1/runtime/readiness`는 `Empty reply from
server`로 끝났다. 즉, Guest listener 기동은 증명됐지만 C32 Host-to-Guest byte relay가
HTTP 응답 전 connection을 닫았다.

## 원인

accepted Host TCP descriptor와 VZ virtio socket descriptor는 nonblocking일 수 있다.
relay가 `read`/`write`의 `EAGAIN`, `EWOULDBLOCK`, `EINTR`를 terminal error와 같은
`bytesRead <= 0`으로 처리해 established connection을 종료했다.

## 조치 방향

pure adapter rule
`GuestRuntimeControlHostLocalHTTPBridgeByteRelaySocketResultPolicy`가 위 error를
**waiting** result로 분류한다. byte relay는 짧게 대기한 뒤 같은 connection에서
forward를 계속한다. peer EOF 또는 terminal socket error만 해당 accepted bridge
connection을 close한다.

수정 후 real macOS Virtualization Guest에서 C33 Host-local HTTP request가 C32 bridge와
C37 `AF_VSOCK` listener를 거쳐 다음 readiness document를 HTTP 200으로 반환했다.

```json
{"state":"available","value":{"state":"ready"}}
```

## 예방 원칙

nonblocking "not ready"는 connection failure, Guest lifecycle failure, Guest Runtime
readiness failure와 서로 다른 사실이다. adapter-local I/O classification은 pure named
policy로 test하고, Host Agent가 별도 probe 결과를
`GuestRuntimeControlTransportObservation`으로 저장할 때만 transport outcome을
관측한다.

## 관련 경계

- C32 `GuestRuntimeControlHostLocalHTTPBridge`
- C33 `ConfiguredGuestRuntimeControlHTTPAddress`
- C37 `GuestRuntimeControlVirtioSocketListener`
- [Guest Runtime Control Endpoint Boundary](../architecture/guest-runtime-control-endpoint-boundary.md)
