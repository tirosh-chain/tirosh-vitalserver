# macOS `pkgbuild`가 Host metadata를 AppleDouble payload carrier로 넣는 경우

> 상태: resolved by declared Installer payload inventory recomposition

## 증상

`pkgbuild`는 성공하고 generated `.pkg`도 `pkgutil --expand-full`로 열리지만,
Installer가 실제로 보는 payload 목록에는 다음과 같은 선언되지 않은 항목이 남는다.

```text
./Library/Application Support/VitalServerRuntimePlatform/bin/._host-agent
./Library/Application Support/VitalServerRuntimePlatform/release/._guest-root.raw
```

즉, Host Agent, Guest artifact, release configuration의 declared product bytes 외에
build Mac의 metadata carrier가 설치 대상에 섞인다. expanded filesystem만 검사하면
`._*`가 xattr로 복원되어 ordinary file처럼 보이지 않을 수 있으므로, 단순 expansion
검증만으로는 이 문제를 놓칠 수 있다.

## 원인

최근 macOS의 `pkgbuild`는 staging source에 남은 `com.apple.provenance` 같은
build-Host extended attribute를 component package의 old ASCII CPIO `Payload` 또는
`Scripts` 안에 AppleDouble `._*` record로 직렬화할 수 있다.

이 record는 VitalServer Runtime Platform의 product role이 아니다. 파일을 `cp -X`,
`ditto --norsrc`, `xattr -c`로 다시 복사하거나 제거한 뒤 `pkgbuild`를 재실행하는 것은
tool behavior와 source filesystem 상태에 다시 의존한다. 따라서 declared payload
inventory를 증명하지 못한다.

## 수정 방향

`MacOSHostPackageComposer`는 `pkgbuild` 결과를 final release artifact가 아니라
`pkgbuild component candidate`로 취급한다.

1. `MacOSInstallerComponentCpioArchive` adapter가 candidate의 `Payload`와 `Scripts`
   CPIO archive를 읽는다.
2. declared CPIO entry의 header/path/content/padding은 그대로 보존하고,
   product role이 없는 AppleDouble `._*` carrier만 제외한 archive를 새로 만든다.
3. composer는 declared payload root에서 BOM과 `PackageInfo` inventory를 다시 만들고,
   `xar --distribution`으로 component package를 재조립한다.
4. `MacOSInstallerPackageSigning`은 이 reconstituted component package에만
   `productsign`을 적용한다. candidate에 먼저 서명하지 않는다.
5. `MacOSHostPackageVerifier`는 expanded payload 검사와 별도로
   `pkgutil --payload-files`라는 Installer-owned observation에서 `._*` path를
   거절한다.

## 재발 방지 원칙

- `pkgbuild` exit 0은 declared Installer payload inventory의 증거가 아니다.
- package verification은 Host staging tree나 expanded filesystem만 보지 말고,
  Installer가 제공하는 payload observation도 함께 사용한다.
- Host extended attribute를 product state, release metadata, 또는 harmless fallback으로
  취급하지 않는다.
- unsigned development PKG의 clean composition proof와 Apple-signed clean-Host C24
  install proof는 서로 다른 evidence다.

## 관련 경계

- [macOS Release Package Assembly Boundary](../architecture/macos-release-package-assembly-boundary.md)
- `MacOSInstallerComponentCpioArchive`
- `MacOSHostPackageComposer`
- `MacOSInstallerPackageSigning`
- `MacOSHostPackageVerifier`
