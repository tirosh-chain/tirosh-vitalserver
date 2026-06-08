# PWA Runtime Overview Bridged Interface Contract Mismatch

## Summary

- ID: TS-056
- Category: Runtime Control PWA / Network
- Owner: Runtime Control API contract
- Status: resolved

## Symptom

Remote Console Status 화면에서 아래 오류가 반복된다.

```text
Runtime Control API contract mismatch
The response for /runtime/overview did not match the PWA contract.
First mismatch: settings.bridgedinterface (invalid_type) Invalid input
```

## Cause

`RuntimeSettings.bridgedInterface`는 shared network mode에서 값이 없을 수 있는 Host-owned runtime state다. 이 부재는 빈 문자열 fallback이 아니라 explicit `null`로 표현되어야 한다.

기존 계약은 Swift `RuntimeSettings.bridgedInterface`를 optional로 두면서 wire JSON에서 nil을 생략할 수 있었고, PWA Zod schema/OpenAPI generated type은 `string`만 허용했다. 따라서 Helper가 shared mode 상태를 explicit value 없이 내보낼 때 PWA가 `/runtime/overview` 전체를 contract mismatch로 거부했다.

## Fix Direction

- Runtime Control API는 `bridgedInterface` 필드를 항상 포함한다.
- Bridged interface가 없으면 `bridgedInterface: null`을 인코딩한다.
- PWA contract schema는 `bridgedInterface`를 required `string | null`로 검증한다.
- 누락된 `bridgedInterface`는 contract failure로 유지한다.

## Prevention

PWA fixture는 happy-path string만 검증하면 안 된다. Host-owned optional state는 최소한 아래 둘을 함께 검증한다.

- explicit absence value, 예: `bridgedInterface: null`
- missing key rejection, 예: `bridgedInterface` 필드 누락

UI는 missing/null을 빈 문자열로 보정해서 domain state를 만들면 안 된다. 표시나 form draft에서만 필요할 때 사람이 입력하기 좋은 형태로 변환한다.
