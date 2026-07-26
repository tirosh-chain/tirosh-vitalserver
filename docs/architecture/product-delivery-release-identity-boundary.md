# Product Delivery Release Identity Boundary

## 왜 이 경계가 필요한가

한 제품 릴리스의 이름은 PKG filename, `pkgbuild --version`, C33
`installation.productVersion`, launchd service label에 각각 복사해서 넣을 값이
아니다. 서로 다른 CLI argument나 script variable에 같은 문자열을 반복하면, 모두
형식상 유효하지만 서로 다른 제품을 가리키는 package가 만들어질 수 있다.

`0.2.0-dev` PKG와 C33은 있는데 C23가 `0.1.0-dev`를 말하던 사례가 바로 이 failure
mode다. 파일이 생성되었다는 사실은 release identity가 일치한다는 evidence가 아니다.

## Owner와 용어

```text
Release process
  └─ C23 ReleaseDeliveryPlan
       ├─ ProductVersion
       ├─ intended installer artifact name
       ├─ macOS installer package identifier
       └─ required Host service registrations
           ├─ host-agent
           └─ host-edge-proxy
           └─ host-update-handoff-supervisor
            ↓ explicit selected plan
Product Delivery package adapter
  └─ MacOSHostPackageReleasePlan
       ├─ pkgbuild PackageInfo.version
       ├─ C33 installation.productVersion correlation
       ├─ expected PKG file name
       ├─ pkgbuild / PackageInfo installer package identifier
       ├─ Host Agent launchd label
       ├─ Host Edge Proxy launchd label
       └─ Host Update Handoff Supervisor launchd label
            ↓ package payload
Host installation
  └─ C33 HostAgentDeploymentConfiguration
       └─ installed instance desired configuration
```

`ReleaseDeliveryPlan`은 C23의 canonical 이름이며 Release process가 소유한다.
`MacOSHostPackageReleasePlan`은 그 문서의 macOS PKG에 필요한 필드만 투영한
adapter-local value다. 새 release document나 hidden version store가 아니다.

`HostAgentDeploymentConfiguration`은 installed Host instance의 desired input이다.
그 안의 `installation.productVersion`은 C23 Release Identity를 **realize**해야 하지만,
C23을 대체하거나 release를 선택하지 않는다. `PackageInfo.version`도 installer
metadata일 뿐 release owner가 아니다.

C47 `MacOSReleasePackageAssemblyDeclaration`은 C23을 또 하나의 version field로
복사하지 않는다. `releaseDeliveryPlan.documentAbsolutePath`와
`releaseDeliveryPlan.id`로 C23 selection을 명시하고, C41/C35, Host artifacts, package
signing, PKG verification을 하나의 release-build invocation으로 orchestration한다.
C47 `MacOSReleasePackageAssemblyReceipt`은 completed C41/C35/C34/PKG identity를
기록하지만 release plan이나 C24 proof를 대체하지 않는다. 자세한 build boundary는
[macOS Release Package Assembly](macos-release-package-assembly-boundary.md)를 따른다.

## 현재 package composition 계약

`macos_host_package_composer.py`와 `macos_host_package_verifier.py`는 아래 입력을
명시적으로 받는다.

```text
--release-delivery-plans-document <absolute C23 plans document>
--release-delivery-plan-id macos-runtime-platform-release
```

조립기와 검증기는 `--product-version`, 일반 `--launchd-service-label`, 또는
`--host-edge-proxy-launchd-service-label` 또는
`--host-update-handoff-supervisor-launchd-service-label`을 받지 않는다. 선택된
`MacOSHostPackageReleasePlan`에서 세 Host service launchd label, product version,
expected PKG filename, macOS installer package identifier를 읽는다. 그러므로 다음 모두가 같아야 package composition 또는
verification이 성공한다.

1. C23 `productVersion`
2. C23 `intendedInstallerArtifact.expectedName`과 output PKG basename
3. C23 `requiredHostServiceRegistrations[host-agent].name`과 packaged Host Agent
   launchd plist label
4. C23 `requiredHostServiceRegistrations[host-edge-proxy].name`과 packaged Host
   Edge Proxy launchd plist label
5. C23 `requiredHostServiceRegistrations[host-update-handoff-supervisor].name`과
   packaged Host Update Handoff Supervisor launchd plist label
6. C33 `installation.productVersion`
7. expanded PKG `PackageInfo.version`
8. C23 `macOSInstallerPackageIdentifier`, `pkgbuild --identifier`, expanded PKG
   `PackageInfo.identifier`, clean Host `pkgutil` receipt package identifier

`requiredHostServiceRegistrations`는 generic `service`가 아니라 package가 등록해야
하는 Host-side process role을 말한다. 각 release plan에는 `host-agent`,
`host-edge-proxy`, `host-update-handoff-supervisor`가 정확히 하나씩 있으며, macOS
projection은 세 registration이 모두 `launchd`임을 요구한다. 이로써 Host Edge
Proxy나 update handoff supervisor가 installer contract 밖의 보조 process로
사라지지 않고, generic `service-label`도 남지 않는다.

## 제품 버전과 component 버전은 다르다

C23 `productVersion`은 cross-platform installer release identity다. SBOM policy의
각 component `version`이나 C37 `serviceVersion`은 각 executable/service artifact의
version이다. 하나가 `0.2.0-dev`로 advance했다고 다른 모든 component version을
문자열 치환해서는 안 된다. 그 component가 실제로 release된 version인지, C35/C34
provenance가 무엇을 말하는지 각각의 owner가 명시해야 한다.

## 실패 의미

| 관측 | 의미 | 허용되는 처리 |
| --- | --- | --- |
| C23 plan이 없거나 schema-invalid | Release process input unavailable/invalid | package build/verify 실패 |
| output filename이 C23와 다름 | 다른 installer artifact를 만들려는 시도 | package composition 실패 |
| C33 version이 C23와 다름 | installed deployment가 다른 product release를 주장 | package composition/verify 실패 |
| PackageInfo version이 C33와 다름 | installer metadata drift | package verify 실패 |
| PackageInfo identifier가 C23 macOS installer package identifier와 다름 | installer receipt owner가 다른 PKG | package composition/verify 실패 |
| clean-install C24 receipt가 C23 package identifier/version과 다름 | installer effect가 declared release에 대해 관측되지 않음 | delivery proof 검증 실패 |
| verified C24 observed installer artifact가 C23 kind/name/productVersion과 다름 | clean Host가 다른 installer release를 증명에 연결하려는 시도 | delivery proof 검증 실패 |
| verified C24 service registration이 C23 role/name/manager와 다름 | clean Host가 다른 또는 일부 Host service만 관측 | delivery proof 검증 실패 |
| C24 proof가 pending | release identity는 선언되었지만 delivery evidence 없음 | `make release-ready` 실패 |

이 경계는 C24 clean-host install, reboot, update, rollback 증거를 대신하지 않는다.
그저 그 증거가 나중에 어느 정확한 product release를 가리키는지 잃지 않게 한다.

clean Host가 C23 identity를 실제로 관측하는 workflow는 [macOS Clean-Host Release
Evidence](macos-clean-host-release-evidence-boundary.md)에 있다.
