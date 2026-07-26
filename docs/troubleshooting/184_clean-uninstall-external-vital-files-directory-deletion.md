# Clean uninstall must preserve the configured external Vital files directory

> ID: TS-184
> Category: Uninstall / Packaging
> Owner: macOS runtime Application / HostCLI
> Status: implemented; package verification pending

## Symptoms

- Helper의 `Clean Uninstall`을 실행한 뒤 사용자가 설정한 외부 Vital files directory 전체가 사라질 수 있습니다.
- 외장 volume, NAS mount, 다른 제품과 공유하는 directory를 Vital files directory로 설정한 경우에도 같은 위험이 있습니다.
- 영향받는 구현의 uninstall log에는 외부 경로에 대한 별도 `preserved configured external vital files directory` 결정이 없습니다.

정상 동작은 clean uninstall이 제품 root 내부의 Helper-managed 기본 Vital files directory만 제거하고, configured external directory 자체는 그대로 두는 것입니다.

## Impact

- `.vital` 파일뿐 아니라 같은 외부 directory에 사용자가 둔 다른 파일도 재귀 삭제될 수 있는 데이터 손실 위험이 있습니다.
- 삭제된 외부 데이터는 package 재설치로 복구되지 않습니다.
- 외부 directory를 보존하도록 삭제만 막고 완료 검증 계약을 바꾸지 않으면, directory가 남았다는 이유로 uninstall이 실패할 수 있습니다.

## Cause

Clean uninstall removal plan이 configured external Vital files directory를 manager app과 같은 제거 대상으로 추가했습니다. HostCLI의 cleanup completion verifier도 같은 외부 directory의 부재를 성공 조건으로 사용했습니다.

그러나 현재 제품에는 외부 directory 또는 그 안의 개별 entry가 제품 소유임을 증명하는 marker/manifest 계약이 없습니다. 설정됐다는 사실은 접근 경로를 제공할 뿐 삭제 소유권을 제공하지 않습니다. 삭제 계획이 설정 경로를 제품 소유 상태로 잘못 해석한 것이 원인입니다.

## Checks

먼저 현재 설정 경로와 uninstall log를 확인합니다.

```sh
sudo tail -n 250 /private/tmp/tirosh-vitalserver-uninstall.log
sudo /usr/local/bin/vitalserver-vm runtime status
```

외부 경로를 사용하는 수정 버전의 clean uninstall에는 다음 형식의 결정이 기록되어야 합니다.

```text
preserved configured external vital files directory path=<path> reason=no-product-owned-removal-contract
```

이 로그는 경로의 존재나 파일 내용을 추정한 결과가 아니라, 외부 directory가 제거 계약에 포함되지 않는다는 Application 정책 결정입니다.

## Actions

1. 영향받는 설치본에서는 외부 Vital files directory를 설정한 상태로 clean uninstall을 실행하지 않습니다.
2. 제거 전에 외부 `.vital` 데이터의 별도 backup을 확인합니다.
3. 가능하면 데이터를 보존하는 standard uninstall을 사용합니다.
4. TS-184 수정이 포함된 package로 갱신한 뒤 clean uninstall을 수행합니다.
5. 이미 외부 directory가 삭제됐다면 설치 프로그램을 다시 실행하기 전에 filesystem snapshot 또는 별도 backup에서 복구합니다.

## Prevention

- clean/standard 여부와 관계없이 configured external Vital files directory를 removal target에 넣지 않습니다.
- 외부 directory를 cleanup completion verification 대상에도 넣지 않습니다.
- clean uninstall UI 문구는 Helper-managed 기본 directory와 configured external directory의 보존 경계를 구분합니다.
- Application, Workflow, HostCLI composition 테스트에서 외부 directory와 그 안의 `.vital` 파일이 남는 것을 검증합니다.
- 미래에 제품 생성 entry만 선택적으로 삭제하려면 directory 전체가 아니라 schema-versioned product-owned marker/manifest가 명시한 entry만 대상으로 하는 별도 계약을 먼저 설계해야 합니다. Marker가 없거나 읽기/검증에 실패하면 삭제하지 않고 실패를 명시해야 합니다.

## Operational Notes

- `--clean`은 제품이 관리하는 runtime state를 초기화하는 명령이지, 설정으로 참조된 모든 외부 storage를 소유한다는 선언이 아닙니다.
- external directory 보존은 best-effort fallback이 아니라 삭제 범위 정책입니다.
- Helper-managed 기본 Vital files directory는 product root 아래에 있으므로 clean uninstall에서 product root와 함께 제거됩니다. Standard uninstall에서는 기존처럼 임시 보존 후 복원됩니다.

## Related Cases

- [TS-042](042_host-install-uninstall-state-contract-gap.md)
- [TS-065](065_clean-uninstall-reset-installer-boundary.md)

## Follow-up

- 2026-07-27: external directory를 제거 계획과 cleanup completion verifier에서 제외하고 Swift Application/Workflow/HostCLI 테스트를 추가했습니다. Package 설치본 검증은 아직 필요합니다.
