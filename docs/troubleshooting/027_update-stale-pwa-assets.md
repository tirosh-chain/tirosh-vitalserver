# 027 Update 적용 후 PWA가 이전 JS를 계속 사용

> ID: TS-027  
> Category: Runtime Control PWA / Update  
> Owner: macOS runtime  
> Status: active

증상:

```text
Update bundle 적용 후에도 Runtime Control PWA의 탭, 설정, API client 동작이 이전 빌드처럼 보인다.
강제 새로고침을 해도 /assets/index-*.js hash가 기대한 최신 build와 다르다.
```

진단:

```sh
npm --prefix apps/vitalserver-runtime-pwa run build
sed -n '1,80p' apps/vitalserver-runtime-pwa/dist/index.html
curl -sS http://127.0.0.1:18321/ | sed -n '1,80p'
ls -la "/Applications/VitalServer Helper.app/Contents/Resources/runtime-control-pwa/assets"
```

원인:

- update bundle이 최신 PWA `dist`를 포함하지 않았다.
- update apply가 `app-bundle.tar.gz`를 교체했지만 PWA를 띄운 브라우저 세션이 이전 JS runtime을 계속 실행했다.
- PWA 경로로 update apply를 호출한 뒤 Helper app이 재실행되지 않아 새 app bundle의 리소스와 실행 중인 Helper 프로세스가 어긋났다.

조치:

- update bundle 생성은 `make vm-update-bundle-*` 경로를 사용합니다. 이 target은 `pwa-build`를 선행 실행합니다.
- 적용 후 `curl http://127.0.0.1:18321/`의 asset hash가 `apps/vitalserver-runtime-pwa/dist/index.html`과 같은지 확인합니다.
- PWA에서 update apply가 성공하면 Helper가 재실행되고, PWA 화면은 잠시 뒤 reload되어 새 bundle을 로드해야 합니다.

수정:

PWA에서 update bundle apply 성공 시 페이지 reload를 예약합니다. Local Runtime Control API handler도 PWA 경로로 update apply가 성공한 경우 Helper relaunch를 예약해 Swift UI update flow와 동작을 맞춥니다.
