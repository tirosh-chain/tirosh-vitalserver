# 011 HTTP 302가 Reachable로 표시됨

> ID: TS-011  
> Category: Runtime health  
> Owner: macOS runtime  
> Status: resolved

증상:

Helper app의 Service health에서 VitalServer 또는 Network access가 `HTTP 302`인데도 `Reachable`로 표시됩니다.

원인:

`/` 요청은 로그인 화면 등으로 redirect될 수 있습니다. Redirect 자체는 proxy가 살아 있다는 신호일 수 있지만, 운영 health를 의미하지는 않습니다.

조치:

health check는 `/` 대신 VitalServer readiness endpoint인 `/check`를 사용하고, 성공 상태는 2xx만 인정합니다. 브라우저로 여는 URL은 여전히 `/`를 사용합니다.

worker가 없으면 master process만 살아 있고 HTTP listener가 없어 nginx가 502를 냅니다.

조치:

`VITALSERVER_MIN_CPUS` 기본값을 `8`로 두어 최소 worker 2개가 뜨게 했습니다.

## Follow-up

- 관련 issue/PR, 재현 로그, 수정 버전, 운영 판단이 생기면 이 섹션에 추가합니다.
