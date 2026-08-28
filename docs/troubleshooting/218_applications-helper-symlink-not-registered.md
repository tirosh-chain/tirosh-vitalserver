# Applications Helper Symlink Is Not Registered

> ID: TS-218
> Category: Packaging / Update
> Owner: macOS runtime
> Status: resolved

## Symptoms

VitalServer Helper PKG 설치와 receipt 기록은 성공하지만 Finder의
`/Applications`와 Launchpad에서 Helper가 application으로 보이지 않습니다.

```text
Bundle path file:///Applications/VitalServer%20Helper.app/ is not an application
```

`/Applications/VitalServer Helper.app`을 `mdls`로 읽으면 content type, kind,
bundle identifier가 비어 있고, release directory 아래의 실제 app만
LaunchServices에 등록될 수 있습니다.

## Cause

Host Platform release slot 도입 과정에서 public app 경로를 다음 source의
symbolic link로 만들었습니다.

```text
/Applications/VitalServer Helper.app
  -> /Library/Application Support/VitalServerHelper/host-platform/current/app/VitalServer Helper.app
```

target app의 `Info.plist`, executable, code signature가 정상이더라도 macOS는
`/Applications`의 이 symbolic link 자체를 application bundle로 분류하지
않습니다. 설치 성공과 application publication이 서로 다른 상태인데 PKG와
updater가 symlink 존재를 publication proof로 잘못 사용했습니다.

## Fix Direction

- PKG payload는 `/Applications/VitalServer Helper.app`에 실제 bundle directory를
  포함합니다.
- postinstall은 public app이 symlink이면 실패하고, bundle directory,
  `Contents/Info.plist`, main executable을 각각 검증합니다.
- Host Platform reconcile은 target release app을 public app 경로에 게시합니다.
- update 실패 보상은 previous release app을 같은 경로에 다시 게시합니다.
- 기존 symlink 설치본에 update를 적용하면 target app publication이 symlink를
  명시적으로 materialized bundle로 교체합니다.
- installed-status는 symlink app을 정상 설치로 보고하지 않습니다.

## Prevention

release source와 macOS public application은 같은 파일 내용을 가질 수 있지만
서로 다른 배포 역할입니다. `current` symlink는 service/CLI release activation에만
사용하고, LaunchServices가 소비하는 `/Applications/*.app`은 실제 bundle로
게시합니다. 앱의 존재, 링크 여부, Info.plist, executable을 독립된 package/update
회귀 테스트로 유지합니다.

## Evidence

```sh
pkgutil --pkg-info ai.tirosh.vitalserver.helper
ls -ld "/Applications/VitalServer Helper.app"
mdls "/Applications/VitalServer Helper.app"
codesign --verify --deep --strict \
  "/Applications/VitalServer Helper.app"
```

Installer evidence는 `/var/log/install.log`의 `Touched bundle` 직후
`is not an application` 메시지에서 확인할 수 있습니다.

## Related Cases

- [TS-018: pkg 설치 후 `/Applications`에 Helper app이 없음](018_pkg-helper-app-missing.md)
- [TS-217: PKG postinstall uses legacy nginx executable path](217_pkg-postinstall-uses-legacy-nginx-executable-path.md)
