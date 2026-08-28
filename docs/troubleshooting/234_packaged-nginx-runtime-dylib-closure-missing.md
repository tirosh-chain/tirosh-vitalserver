# Packaged nginx runtime dylib closure is missing

> ID: TS-234  
> Category: Packaging / Host proxy  
> Owner: macOS nginx bundle and DMG artifact verification  
> Status: resolved

## Symptoms

PKG 설치는 성공하고 Guest service도 healthy이지만 Host port 80에 listener가
생기지 않습니다. Proxy launchd job은 재시작을 반복하고 runtime log에 다음 오류가
남습니다.

```text
dyld: Library not loaded: @executable_path/../lib/libpcre2-8.0.dylib
Reason: .../release/nginx/lib/libpcre2-8.0.dylib (no such file)
```

## Impact

Guest 내부 API가 정상이어도 Host proxy를 통한 PWA와 제품 route에 접근할 수
없습니다. Installer exit 0이나 launchd job 존재는 nginx runtime closure가
완전하다는 증거가 아닙니다.

## Cause

nginx bundle builder가 Homebrew 등의 absolute dylib load path만 수집했습니다.
이미 bundle된 nginx를 다시 build input으로 사용하면 load path는
`@executable_path/../lib/...`인데, 이를 system dependency처럼 제외해 새 bundle의
`lib` directory가 빈 상태로 생성됐습니다. 기존 DMG artifact verifier도 rootfs,
trust store, handoff supervisor만 검사하고 nginx dylib closure는 검사하지 않아 이
PKG를 승인했습니다.

## Checks

```sh
tail -n 200 \
  "/Library/Application Support/VitalServerHelper/logs/runtime/proxy.err.log"
lsof -nP -iTCP:80 -sTCP:LISTEN
find "/Library/Application Support/VitalServerHelper/host-platform/current/nginx" \
  -maxdepth 2 -type f -print
```

## Actions

수정된 builder와 artifact verifier로 DMG를 다시 생성하고 검증한 뒤 표준 data-preserving
uninstall과 fresh install을 수행합니다. 실행 중인 설치본의 `lib` directory에 dylib를
수동 복사하지 않습니다. 수동 복사는 package closure 결함을 숨기고 다음 설치나 update에서
같은 장애를 재발시킵니다.

## Prevention

- Builder는 `@executable_path/../lib/...`를 input binary의 sibling `lib`에서만
  해석합니다.
- sibling library 누락과 bundle 밖으로 나가는 상대 경로는 서로 다른 명시적
  packaging failure로 유지합니다.
- DMG artifact verifier는 설치 payload의 nginx executable과 PCRE2, OpenSSL,
  libcrypto dylib를 모두 요구합니다.
- Artifact 검증을 통과한 새 PKG로만 현장 재설치를 진행합니다.

## Operational Notes

Guest health 200/204와 Host proxy health는 서로 다른 owner의 상태입니다. Guest가
healthy라는 이유로 port 80 실패를 startup delay나 성공으로 바꾸지 않습니다. 데이터
보존이 필요하면 `--clean` uninstall을 사용하지 않습니다.

## Related Cases

- [TS-217 PKG postinstall uses legacy nginx executable path](217_pkg-postinstall-uses-legacy-nginx-executable-path.md)
- [TS-181 Host and Guest nginx reject Recorder backlog bodies](181_host-and-guest-nginx-reject-recorder-backlog-bodies.md)

## Follow-up

- 2026-08-25: fresh 0.2.2 PKG 설치 후 Guest root와 recorder-ingress는 healthy였지만
  Host proxy가 `libpcre2-8.0.dylib` 누락으로 반복 종료됐습니다. 설치 payload와
  package build root의 nginx `lib` directory가 모두 비어 있음을 확인했습니다.
- 2026-08-28: 수정된 0.2.2 PKG 설치본에서 PCRE2, OpenSSL, libcrypto 세 dylib와
  nginx의 `@executable_path/../lib/...` load path를 확인했습니다. Host proxy와
  Guest root는 HTTP 302, Guest Control readiness는 HTTP 200을 반환했고, 설치된
  Runtime Control PWA가 실제 Recorder 상세를 정상 렌더링했습니다. 수동 dylib
  복사는 사용하지 않았습니다.
