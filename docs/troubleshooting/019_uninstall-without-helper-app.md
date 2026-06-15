# 019 Helper app 없이 설치물을 제거해야 함

> ID: TS-019  
> Category: Uninstall  
> Owner: macOS runtime  
> Status: active

증상:

`/Applications/VitalServer Helper.app`이 없어서 Helper app의 Uninstall 버튼을 사용할 수 없습니다. 하지만 package receipt, LaunchDaemon, runtime files는 남아 있을 수 있습니다.

확인:

```sh
pkgutil --pkgs | grep com.tirosh.vitalserver.vm
ls -l /usr/local/bin/tirosh-vitalserver-uninstall
ls -ld "/Library/Application Support/TiroshVitalServer"
```

조치:

설치된 CLI uninstaller가 남아 있으면 그걸 사용합니다. 기본 제거는 `.vital` 파일 경로와 backups를 보존합니다.

```sh
sudo tirosh-vitalserver-uninstall
```

테스트 설치물을 완전히 지워야 하면 clean 제거를 사용합니다. 이 옵션은 backups와 설정된 vital files directory까지 삭제할 수 있으므로 실제 데이터가 있는 환경에서는 먼저 경로를 확인합니다.

```sh
sudo tirosh-vitalserver-uninstall --clean
```

개발 repo에서 반복 설치/삭제 중이면 같은 제거 스크립트를 감싼 target을 사용할 수 있습니다.

```sh
make dist/uninstall/dev
```

제거 후에는 아래 항목들이 사라졌는지 확인합니다.

```sh
pkgutil --pkgs | grep com.tirosh.vitalserver.vm
ls -l /usr/local/bin/tirosh-vitalserver-uninstall /usr/local/bin/vitalserver-vm
ls -ld "/Library/Application Support/TiroshVitalServer"
ls -ld "/Applications/VitalServer Helper.app"
```

정상 로그:

```text
worker:1 is forked
worker:2 is forked
worker:1 is listening
worker:2 is listening
```

정상 응답:

```text
HTTP/1.1 302 Found
Location: /check
```

## Follow-up

- 관련 issue/PR, 재현 로그, 수정 버전, 운영 판단이 생기면 이 섹션에 추가합니다.
