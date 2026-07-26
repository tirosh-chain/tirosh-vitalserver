# 147 macOS VM supervisor의 Virtualization entitlement 누락

> 상태: release-build contract and staged-signing verification implemented / signed identity execution evidence pending

## 증상

macOS provider가 C32를 정상적으로 읽고 storage attachment를 만든 뒤
`VZVirtualMachineConfiguration.validate()`에서 다음 오류로 실패한다.

```text
The process doesn’t have the “com.apple.security.virtualization” entitlement.
```

이 오류는 Guest kernel, cloud-init, Guest Runtime 또는 recorder ingress 상태가 아니다.
Host의 long-lived VM owner process가 Apple Virtualization API를 호출할 권한이 없다는
provider boundary failure다.

## 원인

PKG의 installer signature와 실행 파일 signature를 같은 `signing`으로 취급하면
`pkgbuild --sign`을 수행했다는 사실만으로 실행 중인
`macos-virtual-machine-supervisor`의 entitlement가 있다고 잘못 판단하게 된다.
Apple Virtualization은 installer가 아니라 `VZVirtualMachine`을 생성하는 process의
embedded entitlement를 검사한다.

## 조치

`MacOSVirtualMachineSupervisorCodeSigning`은 PKG signing input과 분리되어 다음
네 가지를 명시한다.

1. supervisor executable code-signing mode;
2. supervisor application signing identity;
3. selected `codesign` executable;
4. `MacOSVirtualMachineSupervisor.entitlements` source document.

signed mode에서 package composer는 source binary를 바꾸지 않고 temporary PKG payload의
`macos-virtual-machine-supervisor`만 sign한다. 이어서 strict signature verification과
`com.apple.security.virtualization=true` entitlement read를 모두 통과해야 `pkgbuild`를
호출한다. signed PKG는 unsigned supervisor contract를 가질 수 없다.

## 예방 원칙

installer identity와 capability-bearing process identity는 서로 다른 artifact fact다.
하나의 generic signing option, package-only verification, 또는 unsigned development
default가 실행 권한을 추측하면 안 된다. 이름과 validation은 반드시 대상 artifact와
required capability를 함께 드러내야 한다.

## 현재 증거 경계

focused test는 staged binary만 code sign command의 대상이고 source build artifact가
변하지 않으며, strict verification과 entitlement display가 모두 성공해야 PKG가
publish됨을 검증한다. 실제 Apple signing identity와 notarization environment에서
서명된 supervisor로 Guest를 boot하는 C24 evidence는 별도 clean-host smoke에서
기록해야 한다.
