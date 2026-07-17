# macOS package composer가 supervisor entitlement를 읽지 못하는 경우

## 증상

`macos_host_package_composer`가 signed
`macos-virtual-machine-supervisor`를 payload에 stage하는 중 아래와 비슷한 오류로
중단한다.

```text
xml.parsers.expat.ExpatError: not well-formed (invalid token)
```

`codesign --display --entitlements :- <supervisor>`를 직접 실행하면 entitlement
plist는 보이지만, 앞뒤에 `Executable=...`, authority, warning 같은 diagnostic line도
함께 보일 수 있다.

## 원인

`codesign` display output은 순수 plist API가 아니다. macOS 버전과 signing mode에
따라 XML plist와 signature diagnostic을 stdout 또는 stderr에 섞어 쓴다. Composer가
첫 `<?xml` 뒤의 **나머지 전체 출력**을 plist parser에 넘기면 closing `</plist>` 뒤의
diagnostic이 XML이 아닌 trailing input이 되어 decode가 실패한다.

이 오류는 entitlement가 없다는 증거도, Guest VM이 시작할 수 없다는 lifecycle
observation도 아니다. 정확한 실패 사실은 "external codesign display evidence를 plist
document로 분리하지 못했다"이다.

## 수정 방향

`parse_displayed_macos_virtual_machine_supervisor_entitlement_plist`는 mixed external
output에서 `<?xml`부터 대응하는 `</plist>`까지만 추출해 parse한다. 그 뒤에만
`com.apple.security.virtualization=true`를 검증한다. XML 시작 또는 종료 tag가 없거나,
추출된 plist가 malformed/object가 아니면 explicit package composition failure로
보고한다.

## 재발 방지 원칙

- command output 전체를 structured contract로 해석하지 않는다. owner가 제공한
  evidence 영역만 명시적으로 추출한다.
- diagnostic line을 제거하거나 entitlement absence로 바꾸지 않는다.
- 실제 `codesign`의 leading/trailing diagnostic을 포함한 parser test를 유지한다.
- PKG composition 성공은 C24 install proof가 아니다. installer signature, clean-host
  install, VM boot, listener bind는 별도 evidence로 검증한다.
