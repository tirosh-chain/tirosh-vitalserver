# macOS Release Package Assembly Boundary

> 상태: **C47 declaration·receipt·CLI와 deterministic test 구현 완료 / Apple Developer ID package의 실제 clean-Host 설치 증거는 C24에서 별도 pending**

## 1. 왜 별도 경계인가

C41 input assembly, C35 Guest artifact compilation, macOS PKG composition, expanded-PKG
verification은 각각 다른 일을 한다. 이들을 shell history나 많은 CLI option으로 연결하면
release operator가 어떤 source, artifact, signing input, output을 하나의 release build로
선택했는지 재현하기 어렵고, 같은 fact를 서로 다른 option으로 중복 입력해 drift를 만들기
쉽다.

C47은 이 orchestration input과 build receipt를 Release process의 language로 만든다.

| 대상 | owner | 책임 | 소유하지 않는 사실 |
| --- | --- | --- | --- |
| C47 `MacOSReleasePackageAssemblyDeclaration` | Release process | 하나의 C41→C35→PKG→expanded-PKG verification invocation에 필요한 explicit input 선택 | PKG가 존재·서명·설치되었다는 사실 |
| C41 `GuestArtifactCompilationInputAssemblyDeclaration` | Release input assembler | Host build-machine source를 immutable C35 input root로 복사 | Guest artifact compilation 또는 package result |
| C35 `GuestArtifactCompiler` | Release build orchestration | named C35 input/builder를 compile하고 C34/C35 output을 publish | package installation |
| `MacOSHostPackageComposer` | package adapter | `pkgbuild` candidate에서 C23/C32–C46/C34/C35가 선언한 Installer file inventory만 재구성하고 final PKG를 publish | PKG installation 또는 Host service running |
| `MacOSHostPackageVerifier` | package adapter | expanded PKG payload identity를 observe/verify하고 undeclared AppleDouble sidecar를 reject | package signature acceptance 또는 clean Host state |
| C47 `MacOSReleasePackageAssemblyReceipt` | Release process | one completed assembly의 C41/C35/C34/PKG/verification identity를 immutable receipt로 retain | C24 delivery proof |

`MacOSReleasePackageAssemblyDeclaration`은 C41의 source selection을 복사하지 않는다.
그 대신 C41 declaration path를 명시하고, C41이 선언한 C35 output role에서 kernel,
initrd, storage source path를 derive한다. 실제 C41 assembly 뒤 C35 command를 다시 parse해
그 derived path가 actual C35 output과 같은지 확인한다. 따라서 C47이 C41/C35 ownership을
가로채지 않는다.

## 2. 흐름과 명명

```text
C47 MacOSReleasePackageAssemblyDeclaration
  ├─ selected C23 ReleaseDeliveryPlan
  ├─ C41 GuestArtifactCompilationInputAssemblyDeclaration
  ├─ Host artifacts + C32/C33/C36/C37/C38/C39/C44/(C46) sources
  ├─ separate PKG and VM-supervisor code-signing inputs
  ├─ explicit PKG/pkgutil executable paths and new output destinations
  │
  ▼
GuestArtifactCompilationInputAssembler (C41)
  ▼
GuestArtifactCompiler (C35 → C34 + C35 receipt)
  ▼
MacOSHostPackageComposer
  ▼
MacOSHostPackageVerifier
  ▼
C47 MacOSReleasePackageAssemblyReceipt
```

`Declaration`은 desired release-build input이다. `Receipt`은 completed build evidence다.
`MacOSReleasePackageAssembly`라는 긴 noun은 “macOS package를 만드는 generic build”가
아니라 **release identity가 있는 Host product package assembly**임을 보여 준다.
`MacOSHostPackageComposition`은 package adapter-local input이고, C47 declaration은 그
adapter와 C41/C35 workflow를 호출하는 Release process input이다. 둘을 같은
`PackageConfig`나 `BuildRequest`라는 이름으로 합치지 않는다.

## 3. C47의 explicit input과 guard

C47 declaration은 다음을 모두 명시한다.

- C23 plans document path와 selected release plan ID
- C41 declaration path and new assembled-input root
- new C35 output directory and builder timeout
- Host Agent, Host Edge Proxy, **Host Installation Manager**, macOS VM
  Supervisor, Guest Product Process Supervisor artifact paths
- C32/C33/C36/C37/C38/C39/C44와 optional C46 source paths
- payload base path, new PKG output path, `pkgbuild` path, package signing
  input, VM Supervisor code-signing input, `pkgutil` path
- new C47 receipt output path

The declaration must name **new** C41 root, C35 output directory, PKG path,
and receipt path. C47 never accepts `replaceOutput`. It rejects an existing
destination or overlapping output paths before C41 performs any copy. A
corrected build therefore uses a new assembly ID/output directory/receipt path;
it cannot overwrite an earlier receipt and rewrite release history.

The package signing input and VM Supervisor code-signing input remain
separate because they authorize different macOS artifacts. Installer package
mode is either `unsigned` or `developer-id`; VM Supervisor mode is `unsigned`,
`ad-hoc`, or `developer-id`. `developer-id` requires the named identity;
`ad-hoc` must not contain one and is valid only for a controlled development
installation. `unsigned` must not quietly retain an identity, codesign
executable, or entitlement path from an earlier command. A `developer-id` PKG
requires a `developer-id` Supervisor. The separate [macOS Development
Installation Evidence](macos-development-installation-evidence-boundary.md)
boundary owns the valid unsigned-PKG/ad-hoc-Supervisor combination; it is not
C24 release proof.

## 4. Receipt meaning

The receipt contains no build-machine source paths. It records only:

- C47 declaration digest and selected C23 release identity;
- C41 assembly ID plus C41 receipt digest;
- C35 compilation/artifact-set IDs plus C35 receipt and C34 manifest digests;
- PKG filename/digest and the expanded-PKG verifier's release-plan,
  payload-base-path, and digest observation;
- receipt completion time.

The composer and verifier digest must both equal the actual output PKG digest.
If either adapter returned a different value, C47 fails instead of publishing a
receipt.

`MacOSHostPackageComposer` copies **declared regular-file bytes** into its
staging payload and assigns the package-owned executable/non-executable mode;
it does not preserve a build Mac's timestamps or copy source extended
attributes deliberately. Recent macOS `pkgbuild` can nevertheless serialize
Host-owned extended attributes as `._*` AppleDouble entries in its generated
CPIO `Payload` and `Scripts`. Therefore that output is named a
`pkgbuild component candidate`, never the release artifact.

The composer uses `MacOSInstallerComponentCpioArchive` to retain each declared
CPIO entry byte-for-byte while removing only AppleDouble carrier entries,
regenerates the payload BOM and `PackageInfo` inventory from declared files,
and reassembles the component package with XAR distribution metadata only.
`MacOSInstallerPackageSigning` applies `productsign` **after** that
recomposition; it cannot sign a candidate whose inventory will subsequently
change. `MacOSHostPackageVerifier` independently observes
`pkgutil --payload-files` and rejects any remaining `._*` carrier. The carrier
prefix has no C23/C32–C46/C34/C35 product-file role, so an otherwise successful
`pkgbuild` invocation is not sufficient build evidence.

This is deterministic **build evidence**, not C24 `artifact-integrity`. C24
still requires an actual signed artifact observation, then clean install,
service registration, reboot, update, rollback, and uninstall/reinstall
evidence on a matching Host.

## 5. Operator command

The release-build application has one explicit entry point:

```sh
cd /absolute/source/runtime-platform
python3 -m tooling.macos_release_package_assembly \
  --assembly-declaration /absolute/release-input/macos-release-package-assembly.json
```

The equivalent Make entry point still requires the same explicit input; it has
no declaration default:

```sh
make -C /absolute/source/runtime-platform macos-release-package-assembly \
  MACOS_RELEASE_PACKAGE_ASSEMBLY_DECLARATION=/absolute/release-input/macos-release-package-assembly.json
```

The command has no product-version, service-label, source-image, endpoint,
output, or C41/C35 completion-time input. C23 owns release identity; C41 owns
Guest source selection; the C41 assembler and C35 compiler each record their
own completion time only after their effects succeed. C47 merely supplies each
named owner document/adapter input and writes a new receipt after all
underlying boundaries succeed.

The C47 receipt becomes input to release review and the later C24 evidence
workflow. The command does not mutate
`product/delivery/release-delivery-proofs.v1.json`, start a Guest, invoke an
installer, or infer clean-Host success.

The package composer materializes C48 `HostProductInstallationManifest` only
after every immutable release-slot byte, launchd plist, and VM Supervisor
signature is final.
It packages the Host Installation Manager in both the release slot and the
Installer script boundary. The script sequence is C50 `preflight` →
`quiesce-services` before payload write and `activate-release` after it; the
scripts do not independently infer state or execute launchd bootout policy.
See [Host Installation Lifecycle](host-installation-lifecycle.md) for the
owner and recovery semantics.

## 6. Failure meanings

| observation | result |
| --- | --- |
| C47 document/path/schema invalid | no C41 effect and no receipt |
| C23 plan unavailable or PKG basename differs | no C41 effect and no receipt |
| a C41/C35/PKG/receipt destination exists or overlaps | no C41 effect and no receipt |
| C41 source or C35 builder fails | C47 fails; no package/receipt success claim |
| C35 output does not match C41-derived package sources | package composition is not invoked |
| C34/C35/C37–C46 provenance or package payload fails | no C47 receipt |
| composer/verifier digest differs from output PKG | no C47 receipt |

Related boundaries: [Guest Artifact Build](guest-artifact-build-boundary.md),
[Product Delivery Release Identity](product-delivery-release-identity-boundary.md),
and [macOS Clean-Host Release Evidence](macos-clean-host-release-evidence-boundary.md).
For the build-Host metadata failure pattern that motivated the declared
Installer inventory boundary, see [macOS `pkgbuild` AppleDouble payload
carriers](../troubleshooting/154_macos_pkgbuild_appledouble_payload_carriers.md).
