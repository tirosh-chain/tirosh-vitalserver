# Guest Artifact Compilation Input Assembly Boundary

## 목적

C35는 Guest artifact compiler가 소비하는 immutable input이다. 그러나 release
candidate는 build-machine의 절대 경로에 존재한다. 이 둘을 같은 문서에 섞으면 C35가
개발자 Mac의 directory, cache, 혹은 현재 checkout을 product input으로 보게 된다.

C41 `GuestArtifactCompilationInputAssemblyDeclaration`은 그 사이를 분리한다.
Release input assembler만 Host build-machine source path를 읽고, 새 input root 안에
복사한 byte identity를 C35와 C41 receipt로 남긴다. C35, C34, C35 receipt, 그리고
package input에는 source absolute path를 남기지 않는다.

## 역할과 소유자

| 구성요소 | owner | 책임 | 소유하지 않는 것 |
| --- | --- | --- | --- |
| C41 `GuestArtifactCompilationInputAssemblyDeclaration` | Release input assembler caller | actual release source, selected bootstrap-artifact composer source, input-root destination을 명시 | source 자동 탐색, base download, cache 선택 |
| `GuestArtifactCompilationInputAssembler` | Release build | source byte 복사, identity capture, C35/C41 receipt을 한 new input root에 atomically publish | Guest image compile, ext4 write, boot, package compose |
| C35 `GuestArtifactCompilationCommand` | GuestArtifactCompiler | relative input path, source size/SHA-256, selected builder identity, output layout | build-machine absolute path, source selection |
| C41 `GuestArtifactCompilationInputAssemblyReceipt` | Release input assembler | C41 declaration digest, assembled C35/builder/input identity, completion time | Guest build/boot/install success |
| `GuestProductBootstrapArtifactComposer` | selected C35 builder | C35/C37/C38/C39/C44, C59 Guest Product Release Manager binary/configuration, external topology의 C46을 C40 `CIDATA` bootstrap-volume composition으로 바꿈 | builder/base 선택, Guest root write, Guest boot |

전달 방향은 한 방향이다.

```text
C41 declaration: explicit Host source paths
       |
       v
GuestArtifactCompilationInputAssembler
       |  new immutable input root
       |  - builders/guest-product-bootstrap-artifact-composer
       |  - inputs/...
       |  - guest-artifact-compilation-command.json (C35)
       |  - guest-artifact-compilation-input-assembly-receipt.json (C41)
       v
GuestArtifactCompiler -> selected C35 builder -> C34 + C35 receipt
```

## Atomicity와 failure 의미

Assembler는 caller가 지정한 **존재하지 않는** output root의 sibling temporary
directory에서만 작업한다. 다음을 모두 통과한 뒤에만 directory rename으로 publish한다.

1. C41 schema와 product source ID/path uniqueness
2. absolute, regular, non-symlink source file 확인
3. selected bootstrap-artifact composer의 executable bit 확인
4. source copy 후 byte size/SHA-256 capture
5. generated C35 strict parse
6. generated C41 receipt schema validation

하나라도 실패하면 final input root는 만들어지지 않는다. 이미 존재하는 output root,
source symlink, non-executable composer, incomplete product source는 모두 explicit
failure다. Assembler는 old input root를 재사용하거나 missing source를 placeholder로
바꾸지 않는다.

`completedAt`은 `GuestArtifactCompilationInputAssembler`가 source copy와 C35
command validation을 모두 마친 뒤 기록하는 UTC completion evidence다. caller는
source와 새 output root를 선택할 수 있지만, 아직 수행하지 않은 assembler effect의
완료 시각을 선언할 수 없다. 테스트에서는 이 assembler-owned clock을 명시적으로
substitute한다.

## Invocation과 다음 경계

```sh
python3 -m tooling.guest_artifact_compilation_input_assembler \
  --assembly-declaration /absolute/C41.json \
  --assembled-input-root /absolute/guest-c35-input

python3 -m tooling.guest_artifact_compiler \
  --compilation-command /absolute/guest-c35-input/guest-artifact-compilation-command.json \
  --input-root /absolute/guest-c35-input \
  --builder-executable /absolute/guest-c35-input/builders/guest-product-bootstrap-artifact-composer \
  --output-directory /absolute/guest-artifact-output \
  --builder-timeout-seconds 1800
```

첫 command의 success는 source selection and identity evidence일 뿐이다. 두 번째
command의 success는 C35 input/output correlation일 뿐이다. ARM64 Linux base가 실제로
boot하는지, systemd가 unit을 실행하는지, macOS package가 clean Host에 설치되는지는
각각 Guest smoke와 C24 evidence가 소유한다.

현재 repository에는 C42 source extractor, C43 root-storage partition assembler, C41
schema/assembly tool, self-contained C35 `GuestProductBootstrapArtifactComposer`, C40
`GuestProductBootstrapVolumeComposer`가 있다. 이들은 C43 root base를 byte-identical로
유지하면서 별도의 read-only `CIDATA` ISO9660 artifact를 만들도록 wiring되어 있고,
focused composition test가 그 두 artifact role을 확인한다.

다만 C43 output과 release-candidate service artifacts를 함께 명시한 actual C41
declaration/receipt, Guest boot smoke, signed macOS package와 C24 clean-host evidence는
아직 없다. 이 absence는 `pending`/unavailable release capability이며 fallback으로
채우지 않는다.
