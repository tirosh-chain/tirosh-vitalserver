# 도메인 언어와 모듈 명명 기준

> 대상: VitalServer Runtime Platform과 기존 Helper를 함께 유지보수하는 개발자

이 제품의 이름은 구현 편의가 아니라 **누가 어떤 사실을 소유하고, 어떤 경계에서
무엇을 하는지** 보여야 한다. 코드를 처음 여는 사람이 directory, package, type,
function 이름만으로 대략의 책임과 의존 방향을 설명할 수 있어야 한다.

## 1. 이름이 답해야 하는 질문

모든 지속되는 module·package·type·function은 가능한 한 다음 질문에 답한다.

| 질문 | 이름에 드러나는 예 |
| --- | --- |
| 누가 owner인가? | `HostAgentDeploymentConfiguration`, `GuestRuntimeControlEndpoint`, `RecorderIngressReceipt` |
| 어떤 도메인 사실인가? | `StagedUpdateHandoff`, `ArtifactExportCommand`, `ClockQuality` |
| 어떤 경계인가? | `MacOSVirtualMachineConfiguration`, `SelectedPlatformProviderProcessDeployment` |
| 어떤 역할인가? | `Load…`, `Validate…`, `Resolve…`, `Compose…`, `Execute…`, `Persist…` |
| side effect가 있는가? | `…Repository`, `…Exporter`, `…Bootstrapper`, `…Bridge` |

`Manager`, `Helper`, `Util`, `Common`, `Processor`, `Data`, `Service`만으로는 이 질문에
답하지 못한다. 그런 이름은 새로운 의미를 만들지 않으므로, domain noun과 role을
붙여 구체화한다. 예를 들어 `ConfigurationLoader`가 아니라
`LoadHostAgentDeploymentConfiguration`, `Factory`가 아니라
`MacOSVirtualMachineFactory`라고 쓴다.

## 2. 경계별 어휘

| 위치 | 허용되는 주된 이름 | 책임 |
| --- | --- | --- |
| `contracts/` | `…Command`, `…Result`, `…Receipt`, `…Configuration`, `…Evidence`, `…Handoff` | versioned boundary document. owner와 전달 방향을 catalog에 기록한다. |
| `internal/<bounded-context>domain/` | `…State`, `…Transition`, `…Policy`, `Validate…`, `Plan…` | complete input만 받는 pure rule. filesystem/process/network 이름을 갖지 않는다. |
| `internal/<bounded-context>application/` | `…ApplicationService`, `…Workflow`, `…Coordinator`, `…Port` | port를 통해 read/effect/persist 순서를 orchestration한다. |
| `internal/adapters/` | `…Repository`, `…Bridge`, `…Exporter`, `…Bootstrapper`, `…Client` | external read/write를 수행하고 typed failure를 반환한다. |
| `internal/hostdeployment/` | `…DeploymentConfiguration`, `ResolveSelected…`, `Load…` | Host installation input을 product process 구성으로 변환한다. runtime state를 소유하지 않는다. |
| `providers/` | OS 또는 upstream 이름이 포함된 `…Provider`, `…Bridge`, `…Factory` | selected external technology만 adapt한다. 다른 provider를 고르지 않는다. |
| `tooling/` | `…Composer`, `…Verifier`, `…Generator` | build/release evidence를 만들거나 검증한다. domain state를 만들지 않는다. |

`Configuration`은 시작 전에 주어진 desired input이고, `State`는 owner가 관측·저장한
현재 사실이며, `Evidence`는 어떤 주장을 뒷받침하는 외부 기록이다. 이 셋을 같은
model이나 directory에 섞지 않는다.

하나의 기술 artifact 안에서도 서로 다른 policy를 한 이름으로 합치지 않는다.
예를 들어 Recorder Gateway tar의 `entryModePolicy`는 **파일 권한**을,
`symbolicLinkPolicy`는 **어떤 링크 관계를 Guest bootstrap이 받아들일지**를 각각
나타낸다. `archivePolicy`나 `safeArchive`처럼 결과만 암시하는 이름은 권한 보존과
링크 탈출 방지 중 무엇을 보장하는지 알 수 없다. 따라서
`allow-relative-links-to-declared-regular-files`처럼 허용 대상과 경계를 값 자체에
기록하고, C40 adapter의 검증 함수도
`validateDeclaredTarGzipContents`와
`resolveRelativeTarGzipSymbolicLinkTarget`처럼 같은 도메인 언어를 사용한다.

adapter package 이름은 **owner + managed concept + external mechanism + role** 순으로
쓴다. 예를 들어 `hoststatesqliterepository`와
`gueststatesqliterepository`는 각각 Host Agent와 Guest Runtime이 소유한 state를
SQLite로 persist하는 repository임을 import path에서 보인다. 단순한 `sqlite`는
선택한 기술만 보이므로, 어느 bounded context의 state인지 알려 주지 못한다.

마찬가지로 `guestruntimecontrolhttpclient.GuestRuntimeControlHTTPClient`는 Host가 Guest
Runtime Control의 **HTTP** contract를 호출하는 adapter임을 나타낸다. `Client` 또는
`guestcontrol`만으로는 Guest lifecycle policy인지, browser edge proxy인지, versioned
control API인지 구별할 수 없다.

transport adapter도 기술 이름만 남기지 않는다. 예를 들어
`guestruntimecontrolvirtiolistener`는 **Guest Runtime Control**이라는 managed
contract, **virtio socket**이라는 external mechanism, **listener**라는 role을
함께 드러낸다. `vsock`이나 `socketutil`처럼 기술만 표시한 package는 어느
bounded context의 socket인지 알 수 없어 피한다. C37의 공통 Linux system-call
adapter는 예외적으로 `guestvirtiotransport`라고 부른다. 이것은 domain adapter가
아니라 Guest-local `AF_VSOCK` resource만 감싼 기술 기반층이며, `routeId`, HTTP,
readiness, Recorder, lifecycle을 전혀 알지 않는다. 실제 문맥은 그 위의
`guestruntimecontrolvirtiolistener`와
`guestpublicservicevirtiobridge`가 각각 복원한다. 같은 이유로 macOS side의
`GuestRuntimeControlHostLocalHTTPBridge`와
`GuestPublicServiceHostLocalHTTPBridge`는 같은 byte relay를 공유해도 control과
public data-plane route를 한 type으로 합치지 않는다.

socket error 분류처럼 adapter 내부의 pure rule도 generic `retry`나 `ioPolicy`가
아니라 `HostLocalHTTPToGuestVirtioSocketByteRelaySocketResultPolicy`처럼 그 rule이
적용되는 established resource와 결정을 이름에 넣는다. 이 이름은 `waiting`이
Guest readiness나 VM lifecycle transition이 아님을 code search만으로 보이게 한다.

## 3. 현재 기준 예시

```text
C33 HostAgentDeploymentConfiguration
  └─ Host Agent process가 읽는 Host-owned desired input
      └─ C32 MacOSVirtualMachineConfiguration path
          └─ macOS virtual machine supervisor가 읽는 Guest VM desired input
              └─ C10 ProviderLifecycleResult
                  └─ selected provider가 관측한 native VM 사실

C34 MacOSGuestArtifactManifest
  └─ Guest image compiler가 소유한 immutable kernel/initrd/storage digest
      └─ macOS Host package composer가 C32의 logical storage ID와 대조

GuestRootStorageReleaseArtifact
  └─ C34가 식별하는 immutable release byte source
      └─ GuestRuntimeDiskProvisioner가 Host-owned GuestRuntimeDiskWorkspace에
         최초 provision할 때만 읽음
          └─ C32 MacOSVirtualMachineConfiguration은 workspace의 runtime disk만 attach
              └─ Guest가 boot 이후 root filesystem bytes를 변경

C35 GuestArtifactCompilationCommand
  └─ Release build가 GuestArtifactCompiler에게 준 immutable input/builder identity
      ├─ GuestProductProcessSupervisor artifact + C37 deployment configuration은 product build의 paired input
      └─ GuestArtifactCompiler가 C35 GuestArtifactCompilationReceipt와 C34를 atomically publish
          └─ macOS Host package composer가 C34를 소비

C37 GuestProductProcessDeploymentConfiguration
  └─ GuestProductProcessSupervisor가 읽는 Guest-local desired input
      ├─ GuestRuntimeProcessDeployment (Guest Runtime executable/listener/SQLite owner boundary)
      └─ RecorderGatewayProcessDeployment (Recorder Gateway program/durable-ingress-state/delivery-replay/cold-path-capture owner boundary)
          └─ requiredProcessExitPolicy=terminate-guest-product
              └─ child process exit fact와 desired deployment input을 섞지 않음

C38 GuestProductServiceManagerDeploymentConfiguration
  └─ systemd가 읽을 Guest Product Supervisor service desired input
      ├─ GuestProductProcessSupervisor executable + C37 path
      └─ restart mode/delay + install target
          └─ systemd installed/running fact와 C38 desired input을 섞지 않음

C23 ReleaseDeliveryPlan
  └─ Release process가 소유한 cross-platform installer release identity
      └─ MacOSHostPackageReleasePlan이 macOS PKG에 필요한 version/file/service facts만 투영
          ├─ C33 installation.productVersion, PackageInfo.version, macOSInstallerPackageIdentifier, 두 Host launchd label을 대조
          └─ C24 ObservedInstallerArtifact/ObservedMacOSInstallerReceipt가 어느 PKG bytes와 installer receipt를 실제로 검증했는지 고정

C47 MacOSReleasePackageAssemblyDeclaration
  └─ Release process가 소유한 one C41→C35→PKG→expanded-PKG verification desired input
      ├─ C41의 Guest source selection을 복사하지 않고 C41 declaration path를 명시
      ├─ Host artifacts, deployment documents, signing inputs, new output destinations를 명시
      └─ MacOSReleasePackageAssemblyReceipt가 C41/C35/C34/PKG identity를 retain
          └─ build evidence이며 C24 clean-Host installation proof가 아님

MacOSCleanHostReleaseEvidenceJournal
  └─ Release runner가 소유한 C24 evidence-run SQLite state
      ├─ Host Agent/Guest Runtime SQLite와 다른 bounded context
      └─ MacOSCleanHostReleaseEvidenceRunner가 artifact → clean-host preflight → install → service registration → reboot transition만 기록

MacOSCleanHostReleaseEvidenceCommandContract
  └─ Release runner가 한 evidence run에서 사용할 macOS external command boundary를 고정
      ├─ pkgutil / installer / launchctl / sysctl의 absolute executable path
      └─ Host runtime environment나 Guest state가 아니라, 외부 사실을 관측·effect할 command contract
          └─ MacOSInstallerArtifactReleaseIdentityObservation은 expanded PKG에서 관측한 identifier/version 사실

C29 HostUpdateJournal(state=handoff-pending, journalRevision=3)
  └─ C30 StagedUpdateInvocation.expectedHandoffJournalRevision=3
      └─ staged next updater가 C27 UpdateCompletionCommand을 만들 때 제시할
         Host-owned handoff revision
          └─ Host Agent가 revision을 원자적으로 검증하고 applying/terminal 전이를 수행
```

여기서 C33은 VM이 실행 중이라는 state가 아니다. C32도 disk가 읽혔다는 evidence가
아니다. 실제 native observation은 C10이고, Host workflow의 durable operation은 C2,
Host resource projection은 C7/C8이다. 이름이 이 차이를 가리켜야 UI나 adapter가
absence를 success로 바꾸지 않는다.

같은 방식으로 `expectedHandoffJournalRevision`은 `expectedRevision`보다 길지만,
그 revision이 **handoff-pending C29**에서 온다는 ownership과 transition context를
보존한다. 반면 C27 `UpdateCompletionCommand.expectedJournalRevision`은 Host API가
completion을 받을 때 검증하는 current journal revision이다. 두 값을 같은
`revision`이라는 이름으로 합치면 retry·recovery 시점의 보호 대상이 코드에서
사라진다.

`guest_artifact_compiler`도 generic `image_builder`보다 구체적인 이유가 있다. 이
module은 macOS package나 Host lifecycle을 만들지 않고, **Guest artifact set**의
release-build 입력을 검증·builder effect 호출·C34/C35 output publication만 한다.
그래서 `GuestArtifactCompilationCommand`, `GuestArtifactCompilationReceipt`,
`GuestArtifactCompiler`라는 세 이름은 같은 bounded context의 command, result evidence,
orchestrating owner를 각각 가리킨다.

storage artifact도 `format`처럼 하나의 기술 단어로 축약하지 않는다. Host provider가
file을 attach할 때 읽는 **container**와 Guest가 partition에서 mount할
**filesystem**은 다른 bounded context의 사실이다. 그래서 C35/C34/C32에는
`storageImageFormat`과 `guestVolumeFileSystem`을 쓴다. 예를 들어
`guest-product-bootstrap`은 `storageImageFormat=raw`이면서
`guestVolumeFileSystem=iso9660`이다. `BootstrapISO`, `DiskFormat`, `VolumeFormat`
같은 이름은 어느 consumer의 요구인지 감추므로 사용하지 않는다. 이 naming rule은
`NoCloudGuestProductBootstrapVolumeAdapter`가 Host-side RAW storage image를
compose하고, Guest cloud-init이 그 안의 ISO9660 `CIDATA` filesystem을 읽는 책임
분리를 코드 검색만으로도 드러낸다.

release signature도 `SigningConfiguration` 하나로 뭉치지 않는다. PKG installer의
signature와 `VZVirtualMachine`을 실제 생성하는
`macos-virtual-machine-supervisor` executable signature는 대상·Apple capability·failure
surface가 다르다. 그래서
`MacOSVirtualMachineSupervisorCodeSigning`,
`sign_staged_macos_virtual_machine_supervisor`,
`verify_macos_virtual_machine_supervisor_virtualization_entitlement`처럼 owner,
managed artifact, effect/verification role을 모두 이름에 둔다. 반대로
`sign_package`, `check_entitlement`, `SigningOptions`는 installer와 executable 중 무엇을
말하는지 감추므로 경계 API 이름으로 쓰지 않는다.

boot artifact도 source filename을 target 역할 이름으로 옮기지 않는다. Ubuntu source의
`/boot/vmlinuz`는 gzip-compressed distribution representation이고,
`VZLinuxBootLoader`가 소비하는 것은 uncompressed ARM64 Linux `Image`다. 따라서 C42에는
`DeclaredGuestBootResource.SourceCompression`, `OutputRelativePath`, `OutputFormat`을
분리하고 kernel declaration을
`gzip` → `boot/Image` → `uncompressed-linux-arm64-image`로 고정한다. 이에 맞춰
`extractDeclaredGzipCompressedGuestLinuxKernel`은 representation conversion이라는
filesystem effect를 드러내고, `extractDeclaredGuestRegularFile`은 initial ramdisk의
identity-preserving copy 역할을 드러낸다. 둘을 `extractBootFile`로 합치면 **누가 어떤
consumer format을 만족시키는지**와 conversion 여부가 사라진다.

Go에서는 package가 public symbol의 첫 번째 문맥이다. 따라서 아래 두 호출은
function 이름을 짧게 줄이는 편의보다 owner와 role을 유지하는 쪽을 선택한다.

```go
hoststatesqliterepository.OpenHostStateSQLiteRepository(ctx, path)
gueststatesqliterepository.OpenGuestRuntimeStateSQLiteRepository(ctx, path)
guestruntimecontrolhttpclient.NewGuestRuntimeControlHTTPClient(httpClient)
```

이 명명은 SQLite 파일의 위치, Guest HTTP endpoint 주소, 또는 현재 operation state를
추측하지 않는다. 각각의 owner가 전달받은 explicit input을 읽거나 effect를 수행한다는
경계도 함께 보존한다.

public symbol의 문맥은 package에만 맡기지 않는다. import를 추적하지 않은 채 검색
결과·stack trace·test failure를 읽는 사람도 많기 때문이다. 경계 adapter의 private
helper까지 무조건 장황하게 만들 필요는 없지만, 이름만 잘라 보아도 **어느 contract를
읽고 어떤 artifact를 만드는지** 알 수 있어야 한다. 예를 들어 C38 adapter에서는
`require_c38_string`, `validate_guest_product_systemd_unit_output_path`,
`write_new_guest_product_systemd_unit_file`을 쓴다. `required_string`,
`validate_output_path`, `write_file`처럼 재사용 가능해 보이는 이름은 그 자체로
새 common abstraction을 뜻하지 않으며, C38 이외의 context에서 잘못 재사용될 여지를
만든다.

같은 이유로 orchestration 변수도 역할을 보인다. `context`, `configuration`,
`launcher` 대신 `supervisionContext`, `deploymentConfiguration`,
`guestProductProcessLauncher`처럼 적는다. 이는 언어의 관용적 짧은 이름을 부정하는
규칙이 아니라, lifecycle·recovery처럼 여러 side effect를 다루는 함수에서 input의
도메인 역할을 보존하는 규칙이다. loop index나 한 식 안에서 끝나는 값은 예외지만,
operation 전체를 관통하는 state/effect collaborator는 예외가 아니다.

release identity도 `version`, `artifact`, `service`처럼 독립 CLI flag로 흩어 놓지
않는다. C23의 `ReleaseDeliveryPlan`은 Release process가 소유하는 versioned product
delivery declaration이고, `MacOSHostPackageReleasePlan`은 이를 macOS PKG adapter가
소비하기 위해 만든 read-only projection이다. 따라서
`--release-delivery-plans-document`와 `--release-delivery-plan-id`는 누가 release를
선택했는지 보여 주지만, `--product-version`과 `--launchd-service-label`은 동일한
fact를 다시 입력받아 drift할 여지를 만든다. `macOSInstallerPackageIdentifier`는 package
filename이나 Host data path가 아니라 macOS installer receipt가 어떤 release identity에
속하는지를 나타낸다. 따라서 `--package-identifier`처럼 package composer가 별도로 받는
CLI input으로 두지 않는다. `MacOSHostPackageReleasePlan.macos_installer_package_identifier`가
`pkgbuild`, `PackageInfo`, clean-host `pkgutil` observation까지 같은 C23 fact를 전달한다.
`requiredHostServiceRegistrations`는
generic `service`가 아니라 `host-agent`, `host-edge-proxy`,
`host-update-handoff-supervisor`라는 Host-side managed
process role을 각각 선언한다. 두 launchd label도 C23 projection에서 읽으므로
package CLI에 duplicate service label이 남지 않는다. 자세한 owner와 failure rule은
[Product Delivery Release Identity Boundary](product-delivery-release-identity-boundary.md)를
따른다.

macOS packaging에서도 `pkgbuild output`이나 `PackageSigning`처럼 tool 중심의
일반명으로 final artifact를 부르지 않는다. `pkgbuild`는 modern macOS에서 build Host의
extended attribute를 AppleDouble `._*` CPIO carrier로 직렬화할 수 있으므로 그 결과는
`pkgbuild component candidate`다. `MacOSInstallerComponentCpioArchive`는 Installer의
`Payload`/`Scripts` archive format을 다루는 adapter이고,
`recompose_pkgbuild_component_package_with_declared_payload_inventory`는 어떤
inventory를 final package로 인정하는지 드러낸다. 최종 signature input은
`MacOSInstallerPackageSigning`이며, `productsign`은 candidate가 아니라 reconstituted
declared-payload package만 서명한다. 이 이름들은 AppleDouble를 일반 파일로 숨기거나
`pkgbuild` 성공을 delivery success로 오해하지 않게 한다.

같은 release boundary에서 `ExecutionEnvironment`와 `PackageMetadata`는 충분한
ubiquitous language가 아니다. 전자는 shell, locale, PATH, process privilege처럼 너무
넓은 ambient condition을 뜻할 수 있고, 후자는 checksum·architecture·payload layout까지
무엇을 관측했는지 알 수 없다. 그래서 C24 runner는
`MacOSCleanHostReleaseEvidenceCommandContract`와
`MacOSInstallerArtifactReleaseIdentityObservation`을 사용한다. 첫 이름은 **어떤
외부 command를 명시적으로 선택했는지**, 둘째 이름은 **PKG에서 identifier/version이라는
release identity 사실을 관측했는지**를 보여 준다. 이 구별 덕분에 command failure가
runtime state로, artifact filename이 release identity로 잘못 승격되지 않는다.

정적 acceptance/deployment adapter도 실제 의미를 숨기는 `Provider`가 아니라
`ConfiguredArchiveExportOutcomeProfile`,
`ConfiguredExternalIntegrationOutcomeProfile`,
`ConfiguredTimeAuthorityOutcomeProfile`,
`ConfiguredTelemetryExportOutcomeProfile`처럼 **configured**·**managed
capability**·**outcome profile**을 함께 쓴다. 이 이름은 실제 NTP/OTLP/network
adapter가 아직 없다는 사실도 보존한다. Host 쪽에는
`ConfiguredHostTimeAuthorityOutcomeProfile`처럼 Host owner를 더 드러낸다. 같은
원칙으로 C21/C10 adapter는 `Client`가 아니라
`SelectedPlatformProviderProcessClient`다. 선택된 provider process만 호출하며
provider selection이나 lifecycle policy를 소유하지 않는다는 것을 이름에서 읽을 수
있다.

layer directory도 맥락을 완전히 대신하지 않는다. `domain/contracts.ts`와
`application/service.ts`는 어느 bounded context의 어떤 contract·workflow인지 숨긴다.
따라서 새 독립 구현에서는
`recordergatewaydomain/recorder-gateway-ingress-and-cold-path-contracts.ts`,
`recordergatewaydomain/recorder-gateway-vital-server-delivery-replay-policy.ts`,
`recordergatewayapplication/recorder-gateway-ingress-and-cold-path-application-service.ts`,
`recorder-gateway-runtime-composition.ts`처럼 **bounded context + managed
concept + layer role**을 directory와 file name 모두에 적는다.
`runtime-composition`은 adapter를 선택해 wiring한다는 뜻이며, `Runtime`의 live
state를 소유한다는 뜻이 아니다.

이 내부 명명은 wire contract의 field 이름을 바꾸는 규칙이 아니다. 예를 들어
`recorderGatewaySchemaVersion`은 Recorder Gateway code의 constant 이름이고 C5/C13
JSON document의 field는 계속 `schemaVersion`이다. 코드 명명 개선이 versioned API의
호환성을 몰래 바꾸지 않게 하려는 구분이다.

### Recorder Gateway 기준 구현

Recorder Gateway는 `GatewayStore`, `Clock`, `getReceipt`처럼 receiver type이나
import path를 따라가야만 의미가 나오는 이름을 boundary API에 두지 않는다. Gateway는
더 넓은 infrastructure가 아니라 **Recorder packet ingress와 VitalServer packet
delivery**라는 bounded context이므로, state owner와 effect target을 이름에 남긴다.

| 위치 | 읽을 수 있어야 하는 책임 | 대표 이름 |
| --- | --- | --- |
| `recordergatewaydomain` | C5 ingress receipt, C13 VitalServer delivery receipt, temporary delivery replay와 independent cold-path capture, pure retry policy | `RecorderIngressReceipt`, `VitalServerDeliveryReceipt`, `RecorderGatewayDeliveryReplayClaimSettlement`, `decideVitalServerDeliveryRetryDisposition` |
| `recordergatewayapplication` | ingress admission, cold-path capture, receipt read, one due delivery replay의 순서 | `RecorderGatewayIngressAndColdPathApplicationService`, `admitRecorderPacket`, `readRecorderIngressReceipt`, `replayOneDueVitalServerDelivery` |
| `adapters/recordergatewayingressdurablestatefile` | Gateway-owned durable ingress state bytes의 atomic persistence | `FileRecorderGatewayIngressDurableStateStore` |
| `adapters/recordergatewayinbound` | Socket.IO `join_vr`/`send_data`와 control HTTP presentation | `attachRecorderGatewaySocketIoIngress`, `createRecorderGatewayControlHTTPServer` |
| `adapters/vitalserverpacketdeliverysocketio` | selected VitalServer `send_data` acknowledgement transport | `SocketIoVitalServerPacketDeliveryPort` |

`RecorderGatewayIngressDurableStateStore`는 raw packet을 durable하게 accepted한 사실,
temporary delivery replay claim, independent cold-path capture만 소유한다. 그것을
`ArchiveStore` 또는 `UpstreamStore`라고 부르지 않는 이유는 cold-path capture가 archive
finalization/upload/indexing success를 뜻하지 않기 때문이다. 반대로
`VitalServerPacketDeliveryPort`는 selected provider에 packet을
전달하고 explicit acknowledgement를 읽는 boundary일 뿐, VitalServer의 clinical state나
archive upload receipt를 소유하지 않는다.

`RecorderGatewayIngressDurableRecord` 안에서도 한 payload retention을 두 의미로
부르지 않는다. `deliveryReplay`는 VitalServer delivery가 성공하면 해제할 수 있는
temporary replay byte이며, `coldPathPacketCapture`는 C45
`RecorderColdPathCapture`가 finalization될 때까지 보존할 archive-source byte다.
따라서 `clearReplayPayload`은 C45 capture payload를 지우지 않고,
`finalizeRecorderColdPathCapture`는 `.vital` formation이나 upload를 실행하지 않는다.
이름이 길어도 “어느 byte가 어떤 lifecycle을 따르는가”가 stack trace와 review에서
즉시 드러나는 편이 더 중요하다.

Go의 exported type·constructor도 같은 기준을 따른다. `Service`, `Repository`,
`Server`, `New`만으로는 caller가 import alias를 생략하거나 stack trace만 볼 때
owner를 잃는다. 예를 들어 Guest Runtime에서는
`GuestRuntimeTopologyApplicationService`, `GuestRuntimeTopologyStateRepository`,
`GuestRuntimeStateSQLiteRepository`, `GuestRuntimeControlHTTPServer`,
`NewGuestRuntimeTopologyApplicationServiceWithExternalUpstreamReader`를 쓴다.
이 이름들은 각각 topology workflow owner, topology persistence port, SQLite adapter
owner, HTTP presentation boundary, explicit external-upstream reader composition을
구분한다. `GuestRuntimeLabApplicationService`나
`GuestRuntimeArchiveApplicationService`를 topology service라고 부르거나 하나의
generic `Repository` port에 합치지 않도록 하는 것도 이 규칙의 목적이다.

### Host Agent 기준 구현

Host Agent는 이 원칙을 실제 directory·public symbol에 적용한 기준 구현이다.
새 기능은 아래 경계를 넘겨 짓지 않고, 같은 이름 규칙을 따른다.

| package | 읽을 수 있어야 하는 책임 | 대표 public symbol |
| --- | --- | --- |
| `hostagentdomain` | Host가 소유한 installation, endpoint, lifecycle/update/operational policy | `GuestLifecycleCommand`, `HostUpdateJournal`, `ApplyGuestRuntimeControlTransportObservation` |
| `hostagentapplication` | Host-owned state를 port로 읽고 command를 orchestration | `HostAgentControlApplicationService`, `HostUpdateApplicationService`, `HostTimeAuthorityApplicationService`, `HostTelemetryPipelineApplicationService` |
| `hostagentcontrolhttpapi` | `/v1/platform/*` HTTP presentation 및 allowlisted Guest Runtime Control facade | `HostAgentControlHTTPServer`, `HostAgentControlHTTPModules` |
| `hoststatesqliterepository` | Host Agent state를 SQLite로 read/write하는 adapter | `HostAgentStateSQLiteRepository`, `OpenHostStateSQLiteRepository` |
| `guestruntimecontrolhttpclient` | C33이 명시한 Guest Runtime Control HTTP endpoint에 effect하는 adapter | `GuestRuntimeControlHTTPClient` |

예를 들어 `HostAgentControlStateRepository`는 generic `Repository`보다 **Host
Agent**, **control state**, **repository port**를 함께 보인다. 이 port의
`ReadHostPlatformInstallation`, `ReadGuestRuntimeControlEndpoint`,
`PersistGuestRuntimeControlEndpointObservation`도 read와 write를 구별한다.
`HostAgentControlHTTPServer`는 generic `Server`가 아니라 어느 HTTP boundary가
Host-owned control contract를 presentation하는지 보인다. 따라서 호출부는
`NewHostAgentControlApplicationService`와
`NewHostAgentControlHTTPServerWithModules`만 읽어도 lifecycle, update, time,
telemetry application service가 HTTP edge에서 compose된다는 사실을 파악할 수 있다.

이 정렬은 Go package path의 길이를 늘리기 위한 것이 아니다. `internal/domain`,
`internal/application`, `internal/httpapi`만 남기면 각 package를 열기 전에는 어느
bounded context인지 알 수 없다. 반대로 `hostagentdomain`,
`hostagentapplication`, `hostagentcontrolhttpapi`는 import와 stack trace에도 owner와
layer를 남긴다. 외부 HTTP URL·JSON field·failure code는 이 내부 명명 정렬만으로
변경하지 않는다.

### Host Updater 기준 구현

Host Updater는 설치된 Host Agent가 아니라 C25가 선택한 **다음 updater**다. Host
Agent가 C29 update journal을 소유하고 C25 bootstrap envelope만 검증하는 반면, Host
Updater는 C30 handoff와 검증된 C26 specification으로 C28 execution evidence와 C27
completion command를 만든다. 그러므로 `UpdateReport`, `Artifact`, `Plan`처럼 다른
bounded context에도 존재할 수 있는 이름을 public model에 두지 않는다.

| package | 읽을 수 있어야 하는 책임 | 대표 public symbol |
| --- | --- | --- |
| `hostupdaterdomain` | C26/C27/C28/C30의 pure planning·correlation·settlement policy | `ProductUpdateArtifact`, `StagedProductUpdatePlanningInput`, `PlanStagedProductUpdateExecution`, `StagedProductUpdateCompletionCommand` |
| `hostupdaterstagedupdatecompletionapplication` | verified handoff/evidence read와 Host-local C27 publication 순서 | `StagedProductUpdateCompletionWorkflow`, `PublishStagedProductUpdateCompletion` |
| `stagedupdateinvocationfile` | Host-staged C30과 digest-bound C26의 strict filesystem read | `StagedProductUpdateInvocationFileReader`, `ReadStagedProductUpdatePlanningInput` |
| `updateexecutionreportfile` | next updater가 C55 receipts에서 만든 one C28 evidence document의 strict read/write | `StagedProductUpdateExecutionReportFileReader`, `WriteStagedProductUpdateExecutionReport` |
| `hostlocalupdatecompletionpublisher` | explicit Host-local endpoint로 C27 전달 | `HostLocalStagedProductUpdateCompletionHTTPPublisher` |

`ProductUpdateLayerRollbackPlan`은 rollback을 **실행했다는 fact**가 아니라 C26이
선언한 desired rollback artifact availability다. 실제 C28의 rollback fact는
`StagedProductUpdateRollbackEvidence`로 따로 둔다. 이 두 이름을
`Rollback`으로 합치면 desired input과 observed outcome이 섞여 missing evidence가
rollback success처럼 해석될 수 있다. 같은 이유로 `SchemaVersion` JSON field는
versioned wire contract의 고정 field로 유지하되, Go constant는
`HostUpdaterDocumentSchemaVersion`으로 지정하여 그 버전이 어느 bounded context의
문서에 적용되는지 드러낸다.

### Guest Runtime 기준 구현

Guest Runtime도 Host Agent와 같은 방식으로 Guest ownership을 package와 public
symbol에 남긴다. `guestruntimeapplication`은 Host Agent의 process, filesystem,
SQLite를 알지 못하며, `guestruntimedomain`은 Guest Runtime SQLite나 HTTP listener를
열지 않는다.

| package | 읽을 수 있어야 하는 책임 | 대표 public symbol |
| --- | --- | --- |
| `guestruntimedomain` | Guest-owned topology, Lab, archive, external integration, time, telemetry policy | `RuntimeTopology`, `LabSession`, `ArtifactManifest`, `ClockQuality` |
| `guestruntimeapplication` | Guest Runtime state port와 provider port를 sequencing하는 use case | `GuestRuntimeTopologyApplicationService`, `GuestRuntimeLabApplicationService`, `GuestRuntimeArchiveApplicationService` |
| `guestruntimecontrolhttpapi` | versioned `/v1/runtime/*` HTTP presentation | `GuestRuntimeControlHTTPServer`, `GuestRuntimeControlHTTPModules` |
| `gueststatesqliterepository` | Guest-owned state를 SQLite로 read/write하는 adapter | `GuestRuntimeStateSQLiteRepository` |

`GuestRuntimeTopologyStateRepository`,
`GuestRuntimeLabStateRepository`, `GuestRuntimeArchiveStateRepository`처럼 port를
나누는 이유는 저장 기술이 아니라 **aggregate owner와 revision guard가 다르기
때문**이다. `GuestRuntimeLabArchiveLifecycleCoordinator`는 Lab delete 전에 Archive
retention fact를 읽는 순서만 orchestration한다. Lab state나 Archive receipt를 직접
소유하는 generic `Coordinator`가 아니다.

Guest Runtime의 application/port API도 수신자 type만 추적해야 뜻이 드러나는
`Get`, 단독 `Apply`, `Export`, `Emit`을 쓰지 않는다. `Read…`는 명시된 owner의
현재 fact를 읽고, `List…`는 collection projection을 읽고, `Apply…`는 그 뒤에
aggregate noun을 붙여 versioned command를 적용하며, `Execute…Command`는 외부
effect까지 포함한 workflow임을 나타낸다. `Read…Document`는 HTTP에 format할
`ReadResult`이고, `Read…State`는 다른 Guest bounded context가 typed failure를
보존하며 소비하는 raw owner boundary라는 차이도 이름에 남긴다.

| Bounded context | 읽기 | command/effect | cross-context owner fact |
| --- | --- | --- | --- |
| Runtime Topology | `ReadRuntimeTopology`, `ReadRuntimeTopologyCapabilityDocument` | `ApplyRuntimeTopology` | `ReadRuntimeTopologyOperationByRequestID` |
| Lab | `ReadLabSession`, `ReadLabVirtualRecorder` | `CreateLabSession`, `ExecuteLabResourceCommand` | `ReadStoppedLabVirtualRecorderArchiveSource` |
| Archive | `ReadArtifactManifest`, `ReadArtifactExportReceipt` | `ExecuteArtifactExportCommand` | `ListArtifactsRetainedForResource` |
| External Upstream | `ReadExternalUpstreamIntegrationDocument` | `ApplyExternalUpstreamIntegration` | `ReadExternalUpstreamIntegrationState` |
| Outbound Relay | `ReadOutboundRelayTarget` | `ApplyOutboundRelayTarget` | provider reference is `OutboundRelayObservationProviderReference` |
| Time / Observation / Telemetry | `ReadGuestClockQuality`, `ReadCatalogObservation`, `ReadTelemetryPipeline` | `ApplyTimeAuthority`, `IngestCatalogObservation`, `EmitTelemetrySignal` | each state repository has its own `Read…OperationByRequestID` port |

Archive adapter verbs follow the same rule: `ArchiveExportProviderReference`,
`UploadArtifactExportPayload`, `VerifyUploadedArtifactIndex` tell a reader that
the provider identity is configuration, then that it uploads immutable artifact
bytes, then verifies the resulting index. `Reference`, `Upload`, `VerifyIndex`
would make a caller inspect implementation to know whether an operation means
metadata lookup, patient data delivery, or archive export.

### Host Edge Proxy 기준 구현

Host Edge Proxy는 C36 Host public trust boundary다. Guest Runtime readiness,
VitalServer health, route delivery receipt를 소유하지 않는다. complete C36 desired
input을 validate한 뒤, explicit route만 match하고, configured Host-local upstream으로
HTTP/WebSocket bytes를 forward하는 adapter다. 따라서 generic `domain`이나
`edgehttpserver` 대신 owner·boundary·role을 import path에 함께 남긴다.

| package | 읽을 수 있어야 하는 책임 | 대표 public symbol |
| --- | --- | --- |
| `hostedgeproxydomain` | C36 route ordering, trust-boundary policy, configured route selection | `HostEdgeProxyDeploymentConfiguration`, `ValidateHostEdgeProxyDeploymentConfiguration`, `ResolveHostEdgeProxyRoute` |
| `hostedgeproxydeployment` | exactly one C36 JSON document의 strict decode | `LoadHostEdgeProxyDeploymentConfiguration` |
| `hostedgeproxyhttpserver` | configured HTTP/WebSocket forward와 client identity header replacement | `NewHostEdgeProxyHTTPHandler` |

`HostEdgeProxyRoute.ConfiguredHTTPUpstreamURL`은 route의 C36 target만 pure하게
표현한다. `TargetURL`은 request Host header나 dynamic service discovery를 resolve하는
지 구별할 수 없다. `HostEdgeProxyDeploymentConfigurationUnavailableError`와
`HostEdgeProxyDeploymentConfigurationInvalidError`도 C36 input의 **read failure**와
**decode/semantic failure**를 distinct하게 보존한다.

새 Guest-local topology도 같은 기준으로 `guest-product-process-supervisor`라고
쓴다. 이 이름은 Host service manager나 generic process manager가 아니라 **Guest
Product**의 **process lifetime**을 감독한다는 소유자·managed concept·role을 함께
보인다. `GuestProductProcessDeploymentConfiguration`은 `guest-runtime.json`처럼
한 component로 오해될 수 있는 이름보다 두 required product process의 desired
deployment boundary를 명확히 한다.

### Guest Product Process Supervisor 기준 구현

Guest Product Process Supervisor는 Guest Runtime이나 Recorder Gateway의 state owner가
아니다. C37 desired input을 strict decode하고, pure policy가 만든 invocation을 OS
process adapter에 전달하며, child exit이라는 **관측 사실**에 대해 선언된 sibling
termination effect만 sequencing한다. 그러므로 package 이름도 generic
`internal/domain`, `internal/application`이 아니라 다음처럼 bounded context를
포함한다.

| package | 읽을 수 있어야 하는 책임 | 대표 public symbol |
| --- | --- | --- |
| `guestproductprocesssupervisordomain` | C37 semantic validation과 required process invocation 계획 | `GuestProductProcessDeploymentConfiguration`, `ValidateGuestProductProcessDeploymentConfiguration`, `PlanGuestProductProcessInvocations` |
| `guestproductprocesssupervisorapplication` | start, observed exit, sibling stop, explicit shutdown 순서 | `RunGuestProductProcessDeployment`, `GuestProductProcessLifecycleHandle` |
| `adapters/guestproductdeploymentconfigurationfile` | C37/C44/C46 desired document의 strict file decode | `LoadGuestProductProcessDeploymentConfiguration`, `LoadGuestProductVitalServerTopologyDeployment`, `LoadExternalVitalServerDeliveryConfiguration` |
| `guestprocessoslauncher` | planned child process의 OS start/wait/terminate effect | `OperatingSystemGuestProductProcessLauncher` |

`GuestProductProcessLifecycleHandle.WaitForGuestProductProcessExit`은 단순한
`WaitForExit`보다 “어느 process의 어떤 사실을 읽는가”를 남긴다.
`GuestProductProviderCapabilityReference`는 configured provider selection이고,
reachable/accepted 상태가 아니다. `GuestProductProcessDeploymentConfigurationSchemaVersion`도
bare `SchemaVersion`이 아니라 C37 boundary에 속한 version임을 import와 test에서
보존한다. 이러한 길이는 중복이 아니라, stack trace·search result·운영 오류에서
owner와 state meaning을 잃지 않기 위한 contract다.

release-build adapter도 기술 이름만으로 package를 만들지 않는다. 다만 이름이
구체적이라는 사실만으로 authority가 올바른 것은 아니다. 이전
`guest-root-filesystem-editor`와
`GuestRootFilesystemEditorMaterializationPlan`은 “Host release build가 Guest root를
직접 수정한다”는 잘못된 authority를 이름으로 정상화했다. Guest root filesystem의
owner는 Guest이므로 그 module과 contract는 제거되었다.

이를 대체하는 `guest-product-bootstrap-volume-composer` 안의
`GuestProductBootstrapVolumeCompositionPlan`,
`ExecuteGuestProductBootstrapVolumeComposition`,
`NoCloudGuestProductBootstrapVolumeAdapter`는 각각 **Guest Product**라는 bounded
context, **bootstrap volume**이라는 managed artifact, **composition/NoCloud**라는
effect role과 selected mechanism을 보인다. 이 이름만으로도 Host가 만드는 것은
read-only delivery volume이고 Guest cloud-init이 후속 root write를 소유함을 읽을 수
있다. `diskfs`, `ext4`, 또는 `image-editor` 하나만으로 package를 부르면 이
전달 방향과 authority가 사라진다.

같은 경계에서 `guest-root.raw`라는 filename은 release byte와 VM이 실제로 쓰는
runtime disk를 구분하지 못한다. 새 Host-side provisioning model에는
`GuestRootStorageReleaseArtifact`, `GuestRuntimeDiskWorkspace`,
`GuestRuntimeDiskProvisioner`, `ProvisionGuestRuntimeDisk`처럼 각각 **immutable
release input**, **Host-owned persistent runtime location**, **effect owner**,
**명시적 copy/provision effect**를 드러내는 이름을 사용한다. `copyDisk`,
`prepareVM`, `workingImage`는 copy의 이유·overwrite guard·write owner를 감춘다.
특히 release artifact를 VM이 attach할 파일로 다시 부르는 것은 release provenance와
Guest mutable state를 같은 noun으로 합치는 것이므로 금지한다.

## 4. 함수 이름과 side effect

함수 앞 동사는 역할을 고정한다.

| 동사 | 의미 | side effect |
| --- | --- | --- |
| `Validate…` | complete input의 rule 검사 | 없음 |
| `Plan…` / `Resolve…` | complete input에서 decision/command 생성 | 없음 |
| `Load…` / `Read…` | named external source 읽기 | 있음; unavailable/invalid을 구분 |
| `Open…` | named state store 또는 external runtime boundary를 열기 | 있음; permission/connection/open failure를 그대로 보고 |
| `Persist…` / `Publish…` | named owner의 state/effect 기록 | 있음 |
| `Execute…` | declared external effect 실행 | 있음 |
| `Compose…` | explicit build/deployment input으로 artifact layout 생성 | build filesystem에만 있음 |

`Get…`은 read인지 cache lookup인지 external I/O인지 알 수 없으므로 public boundary에
사용하지 않는다. `Handle…`도 command, event, HTTP request 중 무엇인지 드러나지
않으면 `Admit…Command`, `Route…Request`처럼 구체화한다.

## 5. 새 코드 체크리스트

새 file 또는 public symbol을 추가하기 전에 확인한다.

1. 이름에 owner 또는 bounded context가 있는가?
2. domain noun과 technical adapter noun이 한 이름에 섞이지 않았는가?
3. pure policy가 `Repository`, `HTTP`, `SQLite`, `launchd`, `VZ` 같은 infrastructure
   이름에 의존하지 않는가?
4. configuration, live state, evidence, command, receipt 중 어떤 것인지 이름과
   schema/catalog에서 구별되는가?
5. optional input을 default로 추측하지 않고 `unavailable`, `invalid`, `unsupported`
   중 올바른 결과로 보고하는가?
6. 오래 유지할 artifact와 module 이름에 임시 작업 순서나 구현 history가 남아
   있지 않은가?

### 5-1. 이름만으로 가능한 첫 질문

새로 합류한 사람이 directory 목록, import 목록, public API, error message만
보아도 아래 질문에 답할 수 있어야 한다. 답할 수 없다면 이름을 줄이는 것이 아니라
**domain noun, owner, boundary role**을 보강한다.

| 첫 질문 | 이름에서 보여야 하는 것 | 예시 |
| --- | --- | --- |
| 누가 이 상태를 소유하는가? | bounded context 또는 runtime location | `GuestRuntimeTopologyApplicationService`, `HostPlatformInstallationSQLiteRepository` |
| 무엇을 관리하는가? | concrete domain resource 또는 operation | `GuestProductBootstrapVolumeCompositionPlan`, `RecorderGatewayDeliveryReceipt` |
| 이 코드가 결정하는가, 실행하는가, 읽는가? | policy/application/adapter/presentation 역할 | `Plan…`, `Execute…`, `Read…`, `…Ext4Adapter` |
| 어떤 외부 mechanism에 의존하는가? | adapter 끝의 concrete mechanism | `NoCloudGuestProductBootstrapVolumeAdapter` |

`Manager`, `Helper`, `Utils`, `Common`, `Core`, `Service`, `Repository`만으로 끝나는
module 또는 public type은 금지한다. 그런 단어는 role을 보조할 수는 있어도 ownership과
managed concept을 대신하지 못한다. 예를 들어 `FilesystemManager`는 어느 filesystem의
무엇을 어떤 authority로 바꾸는지 감추지만,
`GuestProductBootstrapVolumeCompositionPlan`과
`NoCloudGuestProductBootstrapVolumeAdapter`의 조합은 선언된 Guest Product payload를
read-only delivery artifact로 만드는 application input과 NoCloud effect adapter를
분리해 보여 준다. Guest root에 write하는 effect는 이 Host-side module의 책임이
아니다.

test-only executable도 이 규칙의 예외가 아니다. 예를 들어
`guest-runtime-control-http-acceptance-fixture`는 generic `test-server`나
`guest-runtime-mock`보다 길지만, **Guest Runtime application**, **Control HTTP
contract**, **acceptance fixture**라는 세 사실을 함께 보여 준다. 이 entry point는
cross-host HTTP contract를 위한 TCP listener만 bind하며 production Linux Guest의
AF_VSOCK listener를 대신하지 않는다. 따라서 fixture를 읽는 사람은 이 test가
application/HTTP evidence인지 C32↔C37 transport evidence인지를 이름만으로 구분할 수
있다.

### 5-2. Topology와 provider의 이름도 owner를 생략하지 않는다

Guest Product C37/C44/C46에서 `provider`, `integrationProvider`, `endpoint`,
`deploymentKind`만으로는 서로 다른 bounded context의 사실을 한 단어로 뭉개므로 쓰지
않는다. `GuestProductProviderCapabilityReference`는 **어느 adapter capability를 선택했는지**만
가리키는 공통 value object이고, 이를 실제로 사용하는 role은
`ExternalUpstreamObservationProvider`, `OutboundRelayObservationProvider`,
`ArchiveExportProvider`, `VitalServerDeliveryProvider`처럼 분리한다. 그러므로
External Upstream의 관측 provider를 바꾼다고 Outbound Relay의 lifecycle이나
Recorder delivery provider가 바뀌는 것처럼 읽히지 않는다.

같은 원칙으로 C44 `GuestProductVitalServerTopologyDeployment`는
`topologyKind=bundled-vitalserver|external-vitalserver`라는 **placement declaration**만
소유한다. External target의 address는 C44에 넣지 않고, C46
`ExternalVitalServerDeliveryConfiguration.vitalServerPacketDeliveryEndpoint`가 C44-selected
integration/provider에 대해 소유한다. Bundled target은 C44가 C64 configuration resource ID와
declared Guest-loopback delivery endpoint를 함께 소유한다. 이는 C64 manager API endpoint나
container readiness가 아니라 release가 선택한 packet delivery intent다.
`ResolveRecorderGatewayVitalServerDelivery`는 C37 document path와 C44/C46 또는 C44/C64의
full identity를 대조하는 pure function이며, endpoint에 연결하거나 reachability/delivery
success fact를 만들지 않는다. `RecorderGatewayVitalServerDeliveryURL`은 그 resolved desired
endpoint를 command argument 문자열로만 표현한다.

따라서 `VitalServerDeliveryEndpoint`, `VitalServerDeliveryProvider`, `topologyKind`를
C37 process deployment의 direct field로 다시 넣지 않는다. C37은
`VitalServerTopologyDeploymentPath`와
`ExternalVitalServerDeliveryConfigurationPath`라는 **읽어야 할 owner document**만
선언한다. C44는 placement, C46은 external delivery configuration, resolver는 equality
decision, Recorder Gateway는 one packet delivery attempt를 각각 맡는다. `URL`,
`endpoint`, `kind`만으로 public type/field/helper 이름을 만들면 caller가 connection
fact를 만들 수 있다고 오해할 수 있으므로 이 full noun을 유지한다.

Guest Runtime 실행 argument도 같은 언어를 유지한다.
`--external-upstream-observation-provider-*`와
`--outbound-relay-observation-provider-*`는 각각 어떤 **observation adapter**를
선택하는지 드러낸다. 이전처럼 두 argument family를 `…-provider-*`라고만 두면
operator와 다음 유지보수자가 이를 packet delivery provider 또는 upstream lifecycle
owner로 잘못 읽을 수 있다. adapter directory와 constructor 역시
`externalupstreamobservationprovider` /
`ConfiguredExternalUpstreamObservationProfile`,
`outboundrelayobservationprovider` /
`ConfiguredOutboundRelayObservationProfile`로 나눈다. 두 profile은 같은 outcome
문자열을 허용할 수 있어도 서로의 resource, socket traffic, delivery receipt를 만들지
않는다.

이처럼 공통 구조가 같더라도 domain meaning이 다르면 이름을 하나의 generic model로
합치지 않는다. 반대로 `ProviderCapabilityReference`처럼 **동일한 fact와 invariant를
공유하는 value object**만 공통으로 둔다. 이는 중복 제거보다 ubiquitous language와
state owner를 우선하는 선택이다.

### 5-3. Recorder Gateway는 `upstream`이 아니라 VitalServer delivery를 말한다

Recorder Gateway가 전달하는 대상은 generic message bus나 임의의 상위 서비스가
아니라, `send_data` acknowledgement 계약을 제공하는 **선택된 VitalServer**다. 따라서
application port는 `UpstreamDeliveryPort`가 아니라 `VitalServerDeliveryPort`, input은
`VitalServerDeliveryInput`, Socket.IO adapter는
`SocketIoVitalServerDeliveryPort`라고 부른다. Directory도
`adapters/vitalserverdelivery/`로 유지한다. `upstream/`이라고 하면 External Upstream
관측 resource, Outbound Relay, Host proxy 중 무엇인지 알 수 없고, adapter가 topology를
선택하거나 connection state를 소유하는 것처럼 읽힌다.

실행 configuration과 CLI도 같은 말을 쓴다.
`vitalServerDeliveryURL`,
`vitalServerDeliveryAcknowledgementTimeoutMilliseconds`,
`--vitalserver-delivery-url`,
`--vitalserver-delivery-acknowledgement-timeout-ms`는 endpoint가 **packet delivery**에
쓰이며 timeout이 **VitalServer acknowledgement**만 기다린다는 사실을 보여 준다.
`url`, `timeout`, `upstream-url`처럼 짧은 이름은 HTTP control endpoint나 External
Upstream observation timeout으로 오독될 수 있으므로 public deployment/configuration
field에 쓰지 않는다.

모든 C13 failure issue의 `dependency` 역시 adapter가 하드코딩한
`bundled-upstream`이 아니라 resolved C44/C46 `VitalServerDeliveryProvider.id`다. 그러므로 external
VitalServer provider에서 발생한 unavailable/unknown/failed outcome이 bundled topology의
실패로 바뀌지 않는다. provider id가 없으면 adapter construction이 실패하며, fallback
provider를 만들어 delivery attempt를 성공처럼 계속할 수 없다.

`runtime-platform/tooling/verify_boundaries.py`는 persistent path component인
`phase`, `phase2`, `phase-…`, `phase_…`를 merge 전에 거부한다. 또한 Host Agent와
Guest Runtime의 실제 `internal/` tree에서는 generic `domain`, `application`,
`httpapi` directory를 거부하고, 위에서 정한 contextual layer directory가 존재하는지
검사한다. Host Agent와 Guest Runtime의 application/port source에서는 `Get…`, 단독
`Apply`, `Export`, `Emit`, `Ingest`, `CreateSession`, `ExecuteResource`, `Reference`,
`Upload`, `VerifyIndex`, `New`처럼 aggregate 또는 effect를 숨기는 exported method도
거부한다. 이 검사는 module, package, artifact directory와 application boundary의
최소 안전장치다. 여전히 public type과 helper의 domain meaning 전체를 자동으로
판별할 수는 없으므로 위 질문으로 code review에서 계속 확인한다.

이 기준은 미관을 위한 규칙이 아니다. owner와 failure 의미를 읽을 수 있게 하여
cross-platform deployment, update recovery, Recorder data path, Lab deletion처럼
여러 모듈을 넘는 흐름도 안전하게 변경하기 위한 운영 규칙이다.

## 6. 공개 계약 이후의 명명 변경

아직 배포되지 않은 계약은 이 기준에 맞게 이름을 바로잡고, 그 사실을 계약
baseline 갱신 사유에 남긴다. 예를 들어 macOS의 실제 owner가 one-shot bridge가
아니라 long-lived supervisor임을 발견했다면, 미출시 C33의
`bridgeExecutablePath`를 `macOSVirtualMachineSupervisorExecutablePath`로 유지한 채
모호한 공통 이름을 남겨서는 안 된다.

반대로 외부에 배포된 v1 계약의 field, URN, schema source 이름은 같은 방식으로
고쳐 쓰지 않는다. 새 명칭을 가진 v2 계약 또는 명시적 migration을 만들고, 기존
consumer가 관측하는 missing/invalid 의미를 유지해야 한다. compatibility baseline은
이 경계를 강제한다. 지금 `runtime-platform/`의 C21/C30/C32/C33/C37 baseline 재생성은
아직 외부 release artifact가 없는 신규 플랫폼에서만, 명명 정렬·C30 completion
correlation 보완·C32 Host-local bridge와 C37 Guest virtio-socket listener의 explicit
declaration을 반영하기 위해 허용된다.
