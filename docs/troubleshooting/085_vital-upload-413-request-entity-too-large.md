# 085 TestKit vital upload가 413 Request Entity Too Large로 실패함

> ID: TS-085
> Category: Host proxy / Guest containers / TestKit
> Owner: macos-runtime
> Status: active

## Symptoms

VitalServer Helper의 Test 탭에서 Virtual Vital Recorder를 오래 실행한 뒤 stop하면 `.vital` export는 완료되지만 upload가 실패합니다.

UI에는 아래처럼 nginx HTML error body가 표시됩니다.

```text
upload error: <html>
<head><title>413 Request Entity Too Large</title></head>...
```

## Impact

TestKit `.vital` artifact는 생성됐지만 VitalServer `/upload` endpoint에 도달하지 못합니다. 따라서 VitalServer storage, parser, Redis file index, My Files visibility 검증이 모두 수행되지 않습니다.

## Cause

macOS host proxy nginx와 VM 내부 guest edge nginx가 `client_max_body_size`를 명시하지 않았습니다. nginx 기본 request body limit은 1 MiB이므로, 수 MiB 이상 `.vital` upload가 proxy boundary에서 `413 Request Entity Too Large`로 차단됩니다.

`.vital` 파일은 장시간 TestKit playback에서 GiB 단위까지 커질 수 있으므로 고정 상한을 조금 높이는 방식은 충분하지 않습니다. VitalServer upstream `/upload`는 `busboy`로 multipart stream을 받으므로 proxy도 `.vital` upload를 streaming request로 통과시켜야 합니다.

## Checks

host proxy에서 413이 나는지 확인합니다.

```sh
dd if=/dev/zero of=/tmp/vital-upload-size-probe.bin bs=1024 count=3300
curl -sS -i -X POST http://127.0.0.1/upload \
  --data-binary @/tmp/vital-upload-size-probe.bin
```

응답 header가 `Server: nginx/...`이고 status가 `413 Request Entity Too Large`이면 VitalServer app이 아니라 nginx edge에서 차단된 것입니다.

guest edge를 직접 확인하려면 runtime state의 VM IP를 사용합니다.

```sh
curl -sS -i -X POST http://<vm-ip>/upload \
  --data-binary @/tmp/vital-upload-size-probe.bin
```

## Actions

제품 수정 방향:

1. macOS host proxy nginx config에서 `/upload`와 `/upload_vital.php` exact location에만 `client_max_body_size 0;`을 명시합니다.
2. VM 내부 guest edge nginx config도 같은 upload exact location에만 `client_max_body_size 0;`을 명시합니다.
3. upload가 GiB 단위로 커질 수 있으므로 upload location에만 `proxy_request_buffering off;`를 설정해 request body를 upstream으로 streaming합니다.
4. 장시간 upload와 parse wait를 위해 upload location의 `client_body_timeout`, `proxy_send_timeout`, `proxy_read_timeout`을 길게 명시합니다.
5. recorder-ingress upstream timeout도 long upload와 parser wait를 감당할 수 있도록 늘립니다.
6. packaging/template test가 host proxy template, guest edge config, compose timeout default를 확인하도록 유지합니다.

기존 설치본은 config가 이미 렌더링되어 있으므로 수정된 bundle/update 적용 또는 proxy config 재렌더링 후 host proxy와 guest edge를 재시작해야 합니다.

## Prevention

`.vital` upload는 작은 API body가 아니라 장시간 recording artifact stream입니다. Edge proxy는 transport boundary에서 임의의 작은 body limit을 domain state로 바꾸면 안 됩니다.

다만 unlimited body와 request streaming은 `/upload`와 `/upload_vital.php`에만 적용합니다. 일반 web UI, Socket.IO, Redis UI, Swagger 요청까지 전역으로 열면 slow upload connection, disk pressure, DoS 표면이 불필요하게 커집니다.

Upload 성공/실패 의미를 구분합니다.

- Edge transport acceptance: nginx가 request body를 upstream으로 전달함
- Upstream parse/store success: VitalServer `/upload` response body가 `success`
- My Files visibility: Redis filelist index에 non-zero `dtstart/dtend`와 권한상 보이는 bed name이 있음

## Related Cases

- `TS-084`: TestKit vital upload가 My Files에 표시되지 않음

## Follow-up

- 2026-06-17: TestKit `.vital` upload가 3.2 MiB artifact에서 `413 Request Entity Too Large`로 실패하는 증상을 확인했습니다.
- 2026-06-17: `http://127.0.0.1/upload`가 `Server: nginx/1.31.1`로 413을 반환해 host proxy body limit이 원인임을 확인했습니다.
- 2026-06-17: VM IP 직접 upload probe도 `Server: nginx/1.24.0`로 413을 반환해 guest edge도 같은 기본 limit을 갖고 있음을 확인했습니다.
