# PKG Postinstall Uses Legacy nginx Executable Path

> ID: TS-217
> Category: Packaging / Host proxy
> Owner: macOS runtime
> Status: resolved

## Symptoms

Helper 0.2.2 PKG가 payload를 복사한 뒤 postinstall에서 실패합니다.

```text
/bin/chmod 0755 /Library/Application Support/VitalServerHelper/nginx/sbin/nginx
chmod: .../nginx/sbin/nginx: No such file or directory
```

Installer는 receipt를 남기지 않지만 app, product root, runtime tools, VM
artifacts가 남아 다음 fresh install을 막을 수 있습니다.

## Cause

Host Platform release는 nginx executable을 다음 immutable release 경로에
설치합니다.

```text
/Library/Application Support/VitalServerHelper/host-platform/current/nginx/sbin/nginx
```

Swift installed-path contract와 devtools installed-status 검사는 여전히
legacy mutable nginx prefix 아래에서 executable을 찾았습니다. Mutable
prefix와 release executable이 하나의 `nginxDirectory` 의미로 섞인 것이
원인입니다.

## Fix Direction

- config, pid, logs, temp를 위한 mutable prefix는
  `/Library/Application Support/VitalServerHelper/nginx`로 유지합니다.
- executable은 `host-platform/current/nginx/sbin/nginx`에서만 읽습니다.
- proxy launchd에는 mutable prefix와 executable 경로를 별도 환경 값으로
  전달합니다.
- postinstall executable preparation과 installed-status가 같은 active
  release contract를 사용하도록 검증합니다.
- receipt 없는 partial install은 최신 Reset for Reinstall 도구로 정리한
  뒤 새 PKG를 설치합니다.

## Prevention

Mutable runtime state 경로와 immutable release payload 경로를 한 속성으로
표현하지 않습니다. Packaging template, Swift installed paths, launchd
environment, installed-status가 두 경로를 각각 검증하는 회귀 테스트를
유지합니다.

## Evidence

- Installer log: `/var/log/install.log`
- Preserved postinstall failure log:
  `/private/tmp/tirosh-vitalserver-postinstall-failure.log`

## Related Cases

- [TS-065: Clean Uninstall and Reset Installer Boundary](065_clean-uninstall-reset-installer-boundary.md)
