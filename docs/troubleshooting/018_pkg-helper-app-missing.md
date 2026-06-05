# 018 pkg 설치 후 `/Applications`에 Helper app이 없음

> ID: TS-018  
> Category: Packaging  
> Owner: macOS runtime  
> Status: resolved

증상:

```sh
ls "/Applications/VitalServer Helper.app"
```

결과가 `No such file or directory`입니다.

확인:

```sh
pkgutil --files com.tirosh.vitalserver.vm | grep "VitalServer Helper.app"
pkgutil --payload-files dist/TiroshVitalServerVM-<version>.pkg | grep "VitalServer Helper.app"
```

원인:

payload에는 app bundle이 있어도 macOS Installer가 bundle을 relocatable component로 취급하면 `/Applications`가 아닌 이전 위치를 참고할 수 있습니다. 제품 package에서는 Helper app이 반드시 `/Applications`에 설치되어야 하므로 relocation을 꺼야 합니다.

조치:

`make vm-pkg`는 `Support/Packaging/components.plist.template`을 `vm-build.toml` 값으로 렌더링한 뒤 `pkgbuild --component-plist`에 넘깁니다. 여기서 `BundleIsRelocatable=false`를 명시합니다.

```text
Applications/VitalServer Helper.app
  BundleIsRelocatable = false
```

`postinstall`도 `/Applications/VitalServer Helper.app`이 없으면 실패하도록 검증합니다. 이 증상이 보이면 최신 package를 다시 빌드하고 재설치합니다.

## Follow-up

- 관련 issue/PR, 재현 로그, 수정 버전, 운영 판단이 생기면 이 섹션에 추가합니다.
