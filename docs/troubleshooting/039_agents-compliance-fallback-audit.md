# 039 AGENTS.md 상태/실패 fallback 감사

## Metadata

- ID: TS-039
- Category: Architecture / Runtime Control / Observability / TestKit
- Owner: VitalServer
- Status: active
- Created: 2026-06-01
- Related:
  - [AGENTS.md](../../AGENTS.md)
  - [TS-032 macOS runtime explicit responsibility review](032_macos-runtime-explicit-responsibility-review.md)
  - [TS-038 guest kernel panic watchdog restart loop](038_guest-kernel-panic-watchdog-restart-loop.md)

## Summary

AGENTS.md 기준으로 runtime/control 관련 apps/packages의 상태 추론, fallback, 실패 은폐 후보를 확장 감사한다.

이 TS는 즉시 코드 수정을 목표로 하지 않는다. 우선 발견된 후보를 명시적으로 등록하고, 이후 위험도와 소유 레이어에 따라 별도 수정 단위로 분해한다.

## Review Scope

- Date: 2026-06-01
- Branch: `hotfix/recorder-anomaly-details`
- Scope:
  - `apps/vitalserver-macos-runtime`
  - `apps/vitalserver-runtime-pwa`
  - `packages/vitalserver-testkit`
  - `apps/vitaldb-observer`
  - `packages/vitalserver-devtools`
  - 이 범위 밖의 apps/packages는 이번 pass에서 제외한다.
- Baseline:
  - 직전 AGENTS.md 리뷰에서 30개 항목을 이미 확인했다.
  - 본 문서는 그 이후 추가로 추적할 후보를 등록한다.
  - 기준 branch/commit과 기존 30개 항목의 원문은 후속 수정 전에 다시 확인한다.
- Scale:
  - `apps` / `packages` 내 Swift, TypeScript, TSX, Python 파일 약 3,243개
  - 총 약 687,164 LOC
  - 위 수치는 감사 당시 로컬 측정값이며, 재분류 전 같은 명령으로 재측정한다.

## Symptoms

- UI가 읽기 실패, 누락, decode 실패를 `0`, `[]`, `Unknown`, `Stopped`, `Waiting`, `normal` 같은 값으로 표시하거나 전파할 수 있다.
- Host 런타임이 Guest 상태를 명시 계약이 아니라 probe, 파일, 오래된 상태 문서, 로그성 결과로 추정하는 후보가 있다.
- Observability와 recorder activity가 누락/실패/실제 0을 구분하지 못하는 후보가 있다.
- TestKit과 PWA가 요청 기본값을 직접 만들어 domain state처럼 전달하는 후보가 있다.
- SQLite, JSONL, Redis, 파일 시스템 adapter가 읽기 실패를 빈 값으로 축소하는 후보가 있다.

## Impact

- 실제 장애가 정상, 비어 있음, 아직 없음, 기다리는 중으로 보일 수 있다.
- recovery planner가 명시 상태가 아니라 주변 증상으로 restart/repair 결정을 만들 수 있다.
- PWA와 Swift UI가 같은 원천 데이터를 다르게 해석할 수 있다.
- 장애 재현 시점에 필요한 원인 정보가 사라져 troubleshooting 비용이 커진다.
- AGENTS.md의 핵심 원칙인 "state owner provides explicit state"가 약해진다.

## Cause Hypothesis

1. 여러 read API가 `Optional`, 빈 배열, 빈 문자열로 실패와 결측을 표현한다.
2. UI 편의 처리가 domain state 보정처럼 동작한다.
3. contract schema가 optional/passthrough 중심이라 provider 계약 위반을 초기에 잡지 못한다.
4. health/recovery 계층이 명시 lifecycle contract보다 probe 결과를 더 신뢰하는 경로가 있다.
5. best-effort persistence와 observability 기록 실패가 사용자 또는 operator에게 충분히 표면화되지 않는다.

## Audit Commands

```sh
rg -n '\?\?|try\?|catch|return \[\]|return nil|Unknown|not reported|default|fallback|passthrough|optional' apps packages
find apps packages -type f \( -name '*.swift' -o -name '*.ts' -o -name '*.tsx' -o -name '*.py' \) -print
```

## Additional Finding Inventory

아래 항목은 "수정 확정 목록"이 아니라 AGENTS.md 기준으로 추가 확인이 필요한 추적 후보이다. 각 항목은 수정 전에 소유 레이어와 계약 의미를 다시 확인해야 한다.

1. `apps/vitalserver-runtime-pwa/src/pages/status/StatusPage.tsx`: VitalServer URL이 `status.proxyPort`, `settings.proxyPort`, 앱 기본 포트 순서로 합성된다. Runtime endpoint state를 UI가 보정한다.
2. `apps/vitalserver-runtime-pwa/src/pages/status/StatusPage.tsx`: Remote Console URL도 설정 누락 시 기본 포트로 구성된다. 설정 누락과 실제 기본값을 구분하지 못한다.
3. `apps/vitalserver-runtime-pwa/src/pages/status/StatusPage.tsx`: data directory 통계의 `fileCount`가 누락 시 `0`으로 표시된다. 미관측과 실제 빈 디렉터리가 섞일 수 있다.
4. `apps/vitalserver-runtime-pwa/src/pages/status/StatusPage.tsx`: active recorder connections가 누락 시 `0`으로 표시된다. provider 미응답과 실제 연결 0이 섞일 수 있다.
5. `apps/vitalserver-runtime-pwa/src/pages/status/StatusPage.tsx`: resource usage 누락/invalid object가 `Unknown`으로만 축소된다. read failure와 not reported가 분리되지 않는다.
6. `apps/vitalserver-runtime-pwa/src/pages/testkit/TestKitPage.tsx`: Bed 생성 기본 개수와 prefix를 UI가 소유한다. TestKit provider contract인지 사용자 입력 기본값인지 경계가 흐리다.
7. `apps/vitalserver-runtime-pwa/src/pages/testkit/TestKitPage.tsx`: Recorder 생성 기본 개수, scenario, signal, interval을 UI state로 만든다. domain default와 UI preset이 섞일 수 있다.
8. `apps/vitalserver-runtime-pwa/src/pages/testkit/TestKitPage.tsx`: `beds`와 `sessions`가 status 누락 시 빈 배열로 처리된다. 읽기 실패와 실제 없음이 동일해진다.
9. `apps/vitalserver-runtime-pwa/src/pages/testkit/TestKitPage.tsx`: start 가능 여부가 local selected bed count와 busy flag로 결정된다. TestKit service readiness owner가 아닌 UI가 operation state를 판단한다.
10. `apps/vitalserver-runtime-pwa/src/pages/testkit/TestKitPage.tsx`: scenario/signal request가 UI string cast에 의존한다. request contract validation보다 UI 타입 단언이 앞선다.
11. `apps/vitalserver-runtime-pwa/src/pages/testkit/TestKitPage.tsx`: empty VRecoder code가 `null`로 전송된다. 자동 생성 의미와 명시적 미지정 의미가 contract에 드러나야 한다.
12. `apps/vitalserver-runtime-pwa/src/pages/testkit/TestKitPage.tsx`: duration/maxMessages가 `null`로 고정된다. 제한 없음과 UI 미지원이 같은 값으로 보일 수 있다.
13. `apps/vitalserver-runtime-pwa/src/pages/testkit/TestKitPage.tsx`: shiftTime/generateFrames가 `true`로 고정된다. TestKit behavior owner가 UI로 이동한다.
14. `apps/vitalserver-runtime-pwa/src/pages/testkit/TestKitPage.tsx`: enabled 누락이 `false`로 표시된다. disabled와 status read failure가 섞인다.
15. `apps/vitalserver-runtime-pwa/src/pages/testkit/TestKitPage.tsx`: service state 누락이 `Unknown`으로 표시된다. missing, failed, unsupported를 구분하지 못한다.
16. `apps/vitalserver-runtime-pwa/src/pages/testkit/TestKitPage.tsx`: sessions/beds count가 fallback 빈 배열 길이에 의존한다. read issue가 count 0으로 흐를 수 있다.
17. `apps/vitalserver-runtime-pwa/src/domain/runtime-control/recorders/recorderActivity.ts`: activity points 누락 또는 invalid bucket seconds가 빈 series로 변환된다.
18. `apps/vitalserver-runtime-pwa/src/domain/runtime-control/recorders/recorderActivity.ts`: parse 가능한 latest timestamp가 없으면 빈 series가 된다. invalid data와 no activity가 섞인다.
19. `apps/vitalserver-runtime-pwa/src/domain/runtime-control/recorders/recorderActivity.ts`: `points ?? []`가 activity read failure를 빈 activity로 축소할 수 있다.
20. `apps/vitalserver-runtime-pwa/src/domain/runtime-control/recorders/recorderActivity.ts`: timestamp 정렬 fallback이 `0`에 의존한다. invalid timestamp ordering이 암묵적으로 만들어진다.
21. `apps/vitalserver-runtime-pwa/src/domain/runtime-control/recorders/recorderActivity.ts`: bucket seconds 누락이 `60`으로 보정된다. provider contract 누락과 실제 1분 bucket이 섞인다.
22. `apps/vitalserver-runtime-pwa/src/domain/runtime-control/recorders/recorderActivity.ts`: invalid bucket timestamp가 skip된다. contract failure가 사용자에게 보이지 않는다.
23. `apps/vitalserver-runtime-pwa/src/domain/runtime-control/recorders/recorderActivity.ts`: bucket 초기값이 message/byte/room count `0`으로 만들어진다. synthetic bucket과 observed zero가 구분되지 않는다.
24. `apps/vitalserver-runtime-pwa/src/domain/runtime-control/recorders/recorderActivity.ts`: missing message/byte/room count가 `0`으로 합산된다.
25. `apps/vitalserver-runtime-pwa/src/domain/runtime-control/recorders/recorderActivity.ts`: empty bucket이 빈 chart로 반환된다. no observations와 unavailable이 섞일 수 있다.
26. `apps/vitalserver-runtime-pwa/src/domain/runtime-control/recorders/recorderActivity.ts`: missing time bucket을 zero bucket으로 채운다. chart rendering에는 유효할 수 있지만 synthetic state flag가 없다.
27. `apps/vitalserver-runtime-pwa/src/domain/runtime-control/recorders/recorderActivity.ts`: invalid timestamp parse가 `null`로 축소된다. invalid timestamp reason이 사라진다.
28. `apps/vitalserver-runtime-pwa/src/components/CommandResult.tsx`: missing exit code가 `unknown` 문자열로 표시된다. command not run, command failed to report, unsupported가 분리되지 않는다.
29. `apps/vitalserver-runtime-pwa/src/components/CommandResult.tsx`: missing stdout/stderr가 빈 문자열로 표시된다. output 없음과 read failure가 섞일 수 있다.
30. `apps/vitalserver-runtime-pwa/src/domain/runtime-control/events/eventFilters.ts`: unknown period가 기본 기간으로 fallback된다. invalid filter state가 조용히 정상화된다.
31. `apps/vitalserver-runtime-pwa/src/domain/runtime-control/runtimeControlSchemas.ts`: capabilities contract가 optional 중심이다. provider가 capability state를 누락해도 schema가 통과할 수 있다.
32. `apps/vitalserver-runtime-pwa/src/domain/runtime-control/runtimeControlSchemas.ts`: settings contract가 optional 중심이다. settings read failure와 unset setting이 UI에서 뒤섞일 수 있다.
33. `apps/vitalserver-runtime-pwa/src/domain/runtime-control/runtimeControlSchemas.ts`: container observation fields가 optional이다. container read contract 위반을 조기에 막지 못한다.
34. `apps/vitalserver-runtime-pwa/src/domain/runtime-control/runtimeControlSchemas.ts`: recorder activity observation count fields가 optional이다. missing count와 zero count가 downstream에서 섞일 수 있다.
35. `apps/vitalserver-runtime-pwa/src/domain/runtime-control/runtimeControlSchemas.ts`: recorder identity/status fields가 optional이다. identity 없는 recorder record가 UI까지 도달할 수 있다.
36. `apps/vitalserver-runtime-pwa/src/domain/runtime-control/runtimeControlSchemas.ts`: bed identity/status fields가 optional이다. bed relationship state의 owner contract가 약하다.
37. `apps/vitalserver-runtime-pwa/src/domain/runtime-control/runtimeControlSchemas.ts`: anomaly kind/severity/timestamp/subject/message가 optional이다. anomaly로 등록된 원인이 불완전해질 수 있다.
38. `apps/vitalserver-runtime-pwa/src/domain/runtime-control/runtimeControlSchemas.ts`: overview status/settings/release/install/vitalRecorder가 optional이다. overview contract failure가 빈 section으로 흐를 수 있다.
39. `apps/vitalserver-runtime-pwa/src/domain/runtime-control/runtimeControlSchemas.ts`: runtime event document의 event type/timestamp/source/status가 optional이다. event identity contract가 약하다.
40. `apps/vitalserver-runtime-pwa/src/domain/runtime-control/runtimeControlSchemas.ts`: event history의 events/matchingCount가 optional이다. read issue와 empty event list가 섞인다.
41. `apps/vitalserver-runtime-pwa/src/domain/runtime-control/runtimeControlSchemas.ts`: activity bucket/point counts가 optional이다. recorder activity graph가 provider contract 누락을 보정하게 된다.
42. `apps/vitalserver-runtime-pwa/src/domain/runtime-control/runtimeControlSchemas.ts`: VitalDB recorder record identity/status/counts/activity가 optional이다. recorder list에서 누락을 정상 데이터로 렌더링할 수 있다.
43. `apps/vitalserver-runtime-pwa/src/domain/runtime-control/runtimeControlSchemas.ts`: VitalDB bed record identity/status/counts가 optional이다. bed list에서 contract failure가 표면화되지 않을 수 있다.
44. `apps/vitalserver-runtime-pwa/src/domain/runtime-control/runtimeControlSchemas.ts`: activity history source/bucketCount가 optional이다. activity provenance가 약해진다.
45. `apps/vitalserver-runtime-pwa/src/domain/runtime-control/runtimeControlSchemas.ts`: log text가 optional이다. log read failure와 empty log가 분리되지 않을 수 있다.
46. `apps/vitalserver-runtime-pwa/src/domain/runtime-control/runtimeControlSchemas.ts`: export destination이 optional이다. export command result contract가 약하다.
47. `apps/vitalserver-runtime-pwa/src/domain/runtime-control/runtimeControlSchemas.ts`: update summary가 optional이다. update flow state owner가 명확하지 않다.
48. `apps/vitalserver-macos-runtime/Sources/MacRuntimeControlApp/Presentation/Views/RuntimeStatusPanel.swift`: remote client host가 public host 누락 시 local hostname 또는 `localhost`로 보정된다.
49. `apps/vitalserver-macos-runtime/Sources/MacRuntimeControlApp/Presentation/Views/RuntimeStatusPanel.swift`: resource usage nil이 progress `0`으로 렌더링된다. 미측정과 0% 사용량이 시각적으로 섞인다.
50. `apps/vitalserver-macos-runtime/Sources/MacRuntimeControlApp/Presentation/Views/RuntimeRecordersPanel.swift`: selected recorder가 없으면 첫 visible recorder를 선택한다. UI selection state가 data state처럼 보일 수 있다.
51. `apps/vitalserver-macos-runtime/Sources/MacRuntimeControlApp/Presentation/Views/RuntimeRecordersPanel.swift`: recorder IP/bed/lastSeen 누락이 `unknown`으로 축소된다.
52. `apps/vitalserver-macos-runtime/Sources/MacRuntimeControlApp/Presentation/Views/RuntimeRecordersPanel.swift`: latest activity가 array last element에 의존한다. provider ordering contract가 명시되지 않으면 UI가 latest를 추정한다.
53. `apps/vitalserver-macos-runtime/Sources/MacRuntimeControlApp/Presentation/Views/RuntimeRecordersPanel.swift`: total packet과 latest bucket 계산이 UI에서 수행된다. activity summary owner 경계가 흐리다.
54. `apps/vitalserver-macos-runtime/Sources/MacRuntimeControlApp/Presentation/Views/RuntimeRecordersPanel.swift`: empty activity timeline/buckets가 "no activity"로 보인다. read failure가 별도 필드 없으면 사라진다.
55. `apps/vitalserver-macos-runtime/Sources/MacRuntimeControlApp/Presentation/Views/RuntimeRecordersPanel.swift`: missing metadata가 `unknown`으로 표시된다. missing과 failed가 분리되지 않는다.
56. `apps/vitalserver-macos-runtime/Sources/MacRuntimeControlApp/Presentation/Views/RuntimeBedsPanel.swift`: selected bed가 없으면 첫 visible bed를 선택한다. selection fallback이 state 해석에 섞인다.
57. `apps/vitalserver-macos-runtime/Sources/MacRuntimeControlApp/Presentation/Views/RuntimeBedsPanel.swift`: linked recorder가 current recorder list에서 client-side join으로 계산된다. relationship owner contract가 약하다.
58. `apps/vitalserver-macos-runtime/Sources/MacRuntimeControlApp/Presentation/Views/RuntimeBedsPanel.swift`: missing bed name/vrcode가 `unknown`으로 표시된다.
59. `apps/vitalserver-macos-runtime/Sources/MacRuntimeControlApp/Presentation/Views/RuntimeBedsPanel.swift`: bed anomaly zero가 `-`로 표시된다. 0과 not reported가 모델에서 분리되어 있는지 확인이 필요하다.
60. `apps/vitalserver-macos-runtime/Sources/MacRuntimeControlApp/Presentation/Views/RuntimeBedsPanel.swift`: linked recorder status/IP를 UI가 current recorders에서 추론한다.
61. `apps/vitalserver-macos-runtime/Sources/MacRuntimeControlApp/Presentation/Views/RuntimeAdvancedPanel.swift`: runtime version 누락이 `unknown`으로 표시된다.
62. `apps/vitalserver-macos-runtime/Sources/MacRuntimeControlApp/Presentation/RuntimeStatusDisplayPolicy.swift`: missing runtime state가 installed/not-ready 조건에서 `starting`으로 매핑될 수 있다.
63. `apps/vitalserver-macos-runtime/Sources/MacRuntimeControlApp/Presentation/RuntimeStatusDisplayPolicy.swift`: host proxy HTTP 미성공이 waiting/unavailable로 매핑된다. probe failure와 explicit service state가 섞일 수 있다.
64. `apps/vitalserver-macos-runtime/Sources/MacRuntimeControlApp/Presentation/RuntimeStatusDisplayPolicy.swift`: actionNeeded가 service/proxy probe 결과로 repairRuntimeServices를 산출한다.
65. `apps/vitalserver-macos-runtime/Sources/MacRuntimeControlApp/Presentation/RuntimeStatusDisplayPolicy.swift`: display policy가 status copy에 observation을 주입한 뒤 recorder summary를 만든다. presentation layer가 read model을 재구성한다.
66. `apps/vitalserver-macos-runtime/Sources/MacRuntimeControlApp/Presentation/RuntimeStatusDisplayPolicy.swift`: latest recorder IP 누락이 `unknown`으로 표시된다.
67. `apps/vitalserver-macos-runtime/Sources/MacRuntimeControlApp/Presentation/RuntimeStatusDisplayPolicy.swift`: 여러 recovery action이 repairRuntimeServices로 collapse된다. operator action specificity가 약해진다.
68. `apps/vitalserver-macos-runtime/Sources/MacRuntimeControlApp/Presentation/RuntimeStatusDisplayPolicy.swift`: uptime이 compose service, status startedAt, observed seconds 사이를 fallback한다.
69. `apps/vitalserver-macos-runtime/Sources/MacRuntimeControlApp/Presentation/RuntimeStatusDisplayPolicy.swift`: missing compose service observation이 `waiting`으로 표시된다.
70. `apps/vitalserver-macos-runtime/Sources/MacRuntimeControlApp/Presentation/RuntimeStatusDisplayPolicy.swift`: running service with no health가 healthy로 취급될 수 있다.
71. `apps/vitalserver-macos-runtime/Sources/Core/Health/RuntimeObservationHealthPolicy.swift`: missing container observation이 failure reason empty list로 처리된다.
72. `apps/vitalserver-macos-runtime/Sources/Core/Health/RuntimeObservationHealthPolicy.swift`: missing VitalDB observation이 failure reason empty list로 처리된다.
73. `apps/vitalserver-macos-runtime/Sources/Core/Health/RuntimeObservationHealthPolicy.swift`: container failure reason 존재만으로 VM restart 필요 여부가 결정된다. restart owner contract인지 확인이 필요하다.
74. `apps/vitalserver-macos-runtime/Sources/Core/Health/RuntimeObservationHealthPolicy.swift`: duplicate/offline/stale recorder anomaly가 runtime health에서 제외된다. anomaly policy와 operator visibility 기준을 명시해야 한다.
75. `apps/vitalserver-macos-runtime/Sources/Core/Health/RuntimeRecoveryPlanner.swift`: missing vmLifecycle이 waitingForGuest `false`로 처리된다.
76. `apps/vitalserver-macos-runtime/Sources/Core/Health/RuntimeRecoveryPlanner.swift`: missing VM IP, guest HTTP failure, container failure로 restartVM이 결정된다. 명시 lifecycle state보다 probe 기반 추론이 강하다.
77. `apps/vitalserver-macos-runtime/Sources/Core/Health/RuntimeRecoveryPlanner.swift`: VM restart 필요 시 proxy restart도 같이 설정된다. dependency action contract가 명시되어야 한다.
78. `apps/vitalserver-macos-runtime/Sources/Core/Health/RuntimeRecoveryPlanner.swift`: host proxy alive/ready가 probe booleans로 restartProxy를 만든다.
79. `apps/vitalserver-macos-runtime/Sources/Core/Health/RuntimeRecoveryPlanner.swift`: non-numeric HTTP status가 false로 축소된다. invalid response와 failed response가 섞인다.
80. `apps/vitalserver-macos-runtime/Sources/HostCLI/Runtime/RuntimeHealthChecker.swift`: file read helper가 `try?`로 nil을 반환한다. read failure와 missing/empty가 합쳐진다.
81. `apps/vitalserver-macos-runtime/Sources/HostCLI/Runtime/RuntimeHealthChecker.swift`: guest HTTP state가 nil이면 missing VM IP 중심으로 분류된다. HTTP read failure reason이 약하다.
82. `apps/vitalserver-macos-runtime/Sources/HostCLI/Runtime/RuntimeHealthChecker.swift`: guest bootstrap failure reason이 missing/failed bootstrap result에서 nil이 될 수 있다.
83. `apps/vitalserver-macos-runtime/Sources/HostCLI/Runtime/RuntimeHealthChecker.swift`: compose services가 guestState 누락 시 빈 배열로 처리된다.
84. `apps/vitalserver-macos-runtime/Sources/HostCLI/Runtime/RuntimeHealthChecker.swift`: modificationDate lookup이 `try?`로 nil 처리된다.
85. `apps/vitalserver-macos-runtime/Sources/HostCLI/Runtime/RuntimeHealthChecker.swift`: audit proxy status decode가 실패 시 nil 처리된다.
86. `apps/vitalserver-macos-runtime/Sources/HostCLI/Runtime/RuntimeLifecycle+Workflows.swift`: VM IP missing이 command display에서 `not reported` 문자열로 보정된다.
87. `apps/vitalserver-macos-runtime/Sources/HostCLI/Runtime/RuntimeApplyBundlePreflightRunner.swift`: rootfs size missing이 `0`으로 로그된다.
88. `apps/vitalserver-macos-runtime/Sources/HostCLI/Runtime/RuntimeGuestConfigWriter.swift`: admin password 누락 시 default password가 쓰일 수 있다. 보안/운영 설정 owner contract가 필요하다.
89. `apps/vitalserver-macos-runtime/Sources/HostCLI/Runtime/RuntimeDocuments.swift`: guest config optional fields가 decode 시 default로 채워질 수 있다.
90. `apps/vitalserver-macos-runtime/Sources/HostCLI/Runtime/RuntimeDocuments.swift`: guest runtime config file missing이 `.default` document로 처리될 수 있다.
91. `apps/vitalserver-macos-runtime/Sources/HostInfrastructure/Observability/JSONLRuntimeEventRepository.swift`: `recent(limit:)`가 read issue를 포함한 result에서 events만 반환한다.
92. `apps/vitalserver-macos-runtime/Sources/HostInfrastructure/Observability/JSONLRuntimeEventRepository.swift`: invalid JSONL line이 skipped issue로 남더라도 caller가 issue를 소비하지 않으면 event 누락이 조용해진다.
93. `apps/vitalserver-macos-runtime/Sources/HostInfrastructure/Observability/JSONLRuntimeEventRepository.swift`: file size attribute lookup 실패가 size `0`으로 처리될 수 있다.
94. `apps/vitalserver-macos-runtime/Sources/HostInfrastructure/Observability/SQLiteRuntimeObservabilityStore.swift`: best-effort latest observation load가 실패 시 nil이 될 수 있다.
95. `apps/vitalserver-macos-runtime/Sources/HostInfrastructure/Observability/SQLiteRuntimeObservabilityStore.swift`: best-effort list queries가 실패 시 empty result로 축소될 수 있다.
96. `apps/vitalserver-macos-runtime/Sources/HostInfrastructure/Observability/SQLiteRuntimeObservabilityStore.swift`: relationship rows의 missing text columns가 empty string으로 decode될 수 있다.
97. `apps/vitalserver-macos-runtime/Sources/HostInfrastructure/Observability/SQLiteVitalDBObservationRepository.swift`: latest observation load failure가 `try?`로 nil 처리될 수 있다.
98. `apps/vitalserver-macos-runtime/Sources/HostInfrastructure/RuntimeFile/SystemRuntimeFileStore.swift`: file size resource value missing이 `0`으로 처리될 수 있다.
99. `apps/vitalserver-macos-runtime/Sources/HostInfrastructure/RuntimeFile/SystemRuntimeFileStore.swift`: directory walk resource value failure가 `try?`로 무시될 수 있다.
100. `apps/vitalserver-macos-runtime/Sources/HostInfrastructure/RuntimeFile/SystemRuntimeStorageUsageProvider.swift`: capacity unavailable이 `0`으로 처리될 수 있다.
101. `apps/vitalserver-macos-runtime/Sources/MacHostRuntimeAdapter/RuntimeSettingsReader.swift`: missing bridge interface가 empty string으로 보정된다.
102. `apps/vitalserver-macos-runtime/Sources/MacHostRuntimeAdapter/RuntimeSettingsReader.swift`: autoRecovery/preventSleep 누락이 `true`로 보정된다.
103. `apps/vitalserver-macos-runtime/Sources/MacHostRuntimeAdapter/RuntimeSettingsReader.swift`: launchctl read failure가 startOnBoot nil로 축소되고 configurable false로 이어질 수 있다.
104. `apps/vitalserver-macos-runtime/Sources/MacHostRuntimeAdapter/RuntimeStatusReader.swift`: curl failure가 typed failure가 아니라 `"failed"` 문자열로 축소된다.
105. `apps/vitalserver-macos-runtime/Sources/MacHostRuntimeAdapter/RuntimeStatusReader.swift`: launchd load check가 exit code boolean으로 축소된다.
106. `apps/vitalserver-macos-runtime/Sources/MacHostRuntimeAdapter/RuntimeFileReaders.swift`: log bytes decode가 invalid UTF-8 replacement로 진행된다.
107. `apps/vitalserver-macos-runtime/Sources/MacHostRuntimeAdapter/RuntimeLogExporter.swift`: POSIX permission lookup missing이 `0`으로 기록될 수 있다.
108. `apps/vitalserver-macos-runtime/Sources/MacHostRuntimeAdapter/ProcessRunner.swift`: invalid UTF-8 command output이 empty string으로 처리될 수 있다.
109. `apps/vitalserver-macos-runtime/Sources/MacHostRuntimeAdapter/Testing/MacTestKitController.swift`: lastError 누락이 fallback message로 보정된다.
110. `apps/vitalserver-macos-runtime/Sources/MacHostRuntimeAdapter/Testing/MacTestKitController.swift`: endpoint unavailable detail이 `lastError ?? ""`에 의존한다.
111. `apps/vitalserver-macos-runtime/Sources/MacHostRuntimeAdapter/Testing/MacTestKitController.swift`: service state/health missing이 `not reported`로 표시된다.
112. `apps/vitalserver-macos-runtime/Sources/MacHostRuntimeAdapter/Testing/MacTestKitController.swift`: invalid UTF-8 response message가 HTTP code 문자열로 보정된다.
113. `apps/vitaldb-observer/vitaldb_observer/collector.py`: no audit list 또는 non-positive limit이 empty activity로 처리된다.
114. `apps/vitaldb-observer/vitaldb_observer/collector.py`: invalid audit timestamp가 skip된다.
115. `apps/vitaldb-observer/vitaldb_observer/collector.py`: missing vrcode audit event가 skip된다.
116. `apps/vitaldb-observer/vitaldb_observer/collector.py`: missing access log path/file이 empty observed connection list로 처리된다.
117. `apps/vitaldb-observer/vitaldb_observer/collector.py`: tail lines decode가 replacement mode로 수행된다.
118. `apps/vitaldb-observer/vitaldb_observer/collector.py`: invalid audit event가 `None`으로 skip된다.
119. `apps/vitaldb-observer/vitaldb_observer/collector.py`: malformed bed JSON이 raw value 또는 None으로 축소된다.
120. `apps/vitaldb-observer/vitaldb_observer/collector.py`: numeric parse error가 `0`으로 처리된다.
121. `apps/vitaldb-observer/vitaldb_observer/redis_client.py`: wrong Redis type이 empty list로 처리된다.
122. `apps/vitaldb-observer/vitaldb_observer/redis_client.py`: malformed SCAN response가 partial accumulated keys로 반환될 수 있다.
123. `packages/vitalserver-testkit/src/tirosh_vitalserver/testkit/application/recorder_session/store.py`: persisted session scenario 누락이 `normal`로 보정된다.
124. `packages/vitalserver-testkit/src/tirosh_vitalserver/testkit/application/recorder_session/store.py`: missing recorders/messages/cleanup state가 empty/zero로 보정된다.
125. `packages/vitalserver-testkit/src/tirosh_vitalserver/testkit/application/recorder_session/store.py`: connected/joinSent/messages/bytes missing이 false/zero로 보정된다.
126. `packages/vitalserver-testkit/src/tirosh_vitalserver/testkit/application/recorder_session/store.py`: event payload 누락이 empty list로 보정된다.
127. `packages/vitalserver-testkit/src/tirosh_vitalserver/testkit/application/recorder_session/manager.py`: recorder management provider가 없으면 cleanup이 success-like empty tuple로 끝날 수 있다.
128. `packages/vitalserver-testkit/src/tirosh_vitalserver/testkit/application/recorder_session/manager.py`: bed management provider가 없으면 bed cleanup이 success-like empty tuple로 끝날 수 있다.
129. `packages/vitalserver-testkit/src/tirosh_vitalserver/testkit/application/recorder_session/manager.py`: session save failure가 event로만 남고 API command result에 명시 실패로 반영되지 않을 수 있다.
130. `packages/vitalserver-testkit/src/tirosh_vitalserver/testkit/application/recorder_session/manager.py`: session delete persistence failure가 event로만 남을 수 있다.
131. `apps/vitalserver-runtime-pwa/src/pages/beds/BedsPage.tsx`: beds query data가 없으면 `[]`로 필터링된다. read failure와 empty list가 UI 흐름에서 같아질 수 있다.
132. `apps/vitalserver-runtime-pwa/src/pages/beds/BedsPage.tsx`: bedID가 없는 bed record는 `identifiedBeds`에서 제외된다. identity contract failure가 목록에서 사라질 수 있다.
133. `apps/vitalserver-runtime-pwa/src/pages/beds/BedsPage.tsx`: selected bed가 없으면 첫 identified bed를 선택한다. 선택 상태가 사용자의 명시 선택인지 UI 보정인지 구분되지 않는다.
134. `apps/vitalserver-runtime-pwa/src/pages/beds/BedsPage.tsx`: online/stale/assignment summary를 UI가 bed record 필드로 재계산한다. summary owner가 provider인지 UI인지 흐려진다.
135. `apps/vitalserver-runtime-pwa/src/pages/beds/BedsPage.tsx`: assignment count가 `Boolean(bed.vrcode)`로 계산된다. relationship contract가 아니라 문자열 존재 여부로 상태를 만든다.
136. `apps/vitalserver-runtime-pwa/src/pages/beds/BedsPage.tsx`: summary가 없으면 metrics가 `NOT_REPORTED`로 표시된다. unavailable과 query failure가 별도 상태인지 확인이 필요하다.
137. `apps/vitalserver-runtime-pwa/src/pages/beds/BedsPage.tsx`: bed name 누락이 `Unknown`으로 표시된다. missing name과 decode/read issue가 분리되지 않는다.
138. `apps/vitalserver-runtime-pwa/src/pages/beds/BedsPage.tsx`: bed vrcode 누락이 `Unknown`으로 표시된다. unassigned와 unknown assignment가 섞일 수 있다.
139. `apps/vitalserver-runtime-pwa/src/pages/beds/BedsPage.tsx`: table anomaly count가 누락 시 `0`으로 표시된다.
140. `apps/vitalserver-runtime-pwa/src/pages/beds/BedsPage.tsx`: detail heading이 name 누락 시 bedID를 표시한다. display fallback은 가능하지만 missing-name state가 사라진다.
141. `apps/vitalserver-runtime-pwa/src/pages/beds/BedsPage.tsx`: patient connected가 nullable boolean formatter로 `Unknown`이 된다. not reported와 decode failure 분리가 필요하다.
142. `apps/vitalserver-runtime-pwa/src/pages/beds/BedsPage.tsx`: observationCount 누락이 `0`으로 표시된다.
143. `apps/vitalserver-runtime-pwa/src/pages/beds/BedsPage.tsx`: invalid/missing timestamp가 sort value `0`이 된다. ordering failure가 오래된 데이터처럼 보일 수 있다.
144. `apps/vitalserver-runtime-pwa/src/pages/beds/BedsPage.tsx`: `shorten()`이 missing value를 `Unknown`으로 만든다. identity missing을 정상 display text로 축소한다.
145. `apps/vitalserver-runtime-pwa/src/pages/beds/BedsPage.tsx`: search filter가 falsy fields를 제거한다. missing field가 검색 불가능한 정상 record로 처리된다.
146. `apps/vitalserver-runtime-pwa/src/pages/recorders/RecordersPage.tsx`: missing recorder data가 `null` 후 `[]`로 흐른다. unavailable과 empty list가 섞일 수 있다.
147. `apps/vitalserver-runtime-pwa/src/pages/recorders/RecordersPage.tsx`: `presentInLatestObservation !== false`는 missing flag를 current로 취급한다.
148. `apps/vitalserver-runtime-pwa/src/pages/recorders/RecordersPage.tsx`: selected recorder가 없으면 첫 identified recorder를 선택한다.
149. `apps/vitalserver-runtime-pwa/src/pages/recorders/RecordersPage.tsx`: known/current/online/stale summary를 UI가 재계산한다. provider summary와 UI summary가 갈라질 수 있다.
150. `apps/vitalserver-runtime-pwa/src/pages/recorders/RecordersPage.tsx`: anomaly summary가 currentAnomalyCount missing을 `0`으로 합산한다.
151. `apps/vitalserver-runtime-pwa/src/pages/recorders/RecordersPage.tsx`: missing IP가 `Unknown`으로 표시된다. not reported, never connected, read failure가 섞인다.
152. `apps/vitalserver-runtime-pwa/src/pages/recorders/RecordersPage.tsx`: bed display가 bedName, bedID, `Unknown` 순서로 fallback된다. relationship state owner가 흐려진다.
153. `apps/vitalserver-runtime-pwa/src/pages/recorders/RecordersPage.tsx`: table anomaly count가 누락 시 `0`으로 표시된다.
154. `apps/vitalserver-runtime-pwa/src/pages/recorders/RecordersPage.tsx`: recorder version 누락이 `Unknown`으로 표시된다.
155. `apps/vitalserver-runtime-pwa/src/pages/recorders/RecordersPage.tsx`: detail observationCount 누락이 `0`으로 표시된다.
156. `apps/vitalserver-runtime-pwa/src/pages/recorders/RecordersPage.tsx`: activity readError가 있어도 chart rendering은 계속된다. incomplete와 valid chart data 경계가 약하다.
157. `apps/vitalserver-runtime-pwa/src/pages/recorders/RecordersPage.tsx`: vrcode 없는 recorder record는 목록에서 제외된다. identity contract failure가 UI에서 사라진다.
158. `apps/vitalserver-runtime-pwa/src/pages/recorders/RecordersPage.tsx`: missing/invalid lastSeenAt가 sort timestamp `0`이 된다.
159. `apps/vitalserver-runtime-pwa/src/pages/recorders/RecordersPage.tsx`: search filter가 missing fields를 제거한다. field-level read issue가 검색 결과에서 숨겨진다.
160. `apps/vitalserver-runtime-pwa/src/pages/recorders/RecordersPage.tsx`: current/history toggle이 provider state가 아니라 UI flag로 current set을 만든다.
161. `apps/vitalserver-runtime-pwa/src/pages/recorders/RecordersPage.tsx`: selectedKey가 selectedRecorder optional에 의존한다. selection fallback이 detail panel state를 만든다.
162. `apps/vitalserver-runtime-pwa/src/pages/recorders/RecordersPage.tsx`: `formatRecorderStatus`가 status missing을 `Unknown`으로 축소한다.
163. `apps/vitalserver-runtime-pwa/src/pages/recorders/RecordersPage.tsx`: `recorderStatusTone` default가 neutral이다. invalid status와 unknown status가 같은 tone이 된다.
164. `apps/vitalserver-runtime-pwa/src/pages/recorders/RecordersPage.tsx`: activityHistory가 optional prop이다. missing history와 no history가 chart layer에서 섞일 수 있다.
165. `apps/vitalserver-runtime-pwa/src/pages/observability/ObservabilityPage.tsx`: runtime event count가 query data missing 시 `0`이다.
166. `apps/vitalserver-runtime-pwa/src/pages/observability/ObservabilityPage.tsx`: daily event count가 query data missing 시 `0`이다.
167. `apps/vitalserver-runtime-pwa/src/pages/observability/ObservabilityPage.tsx`: guest log sync service missing이 `Stopped`로 표시된다.
168. `apps/vitalserver-runtime-pwa/src/pages/observability/ObservabilityPage.tsx`: recorder anomaly metric은 summary formatter에 의존한다. detail list와 count의 source mismatch를 감지하지 않는다.
169. `apps/vitalserver-runtime-pwa/src/pages/observability/ObservabilityPage.tsx`: observation snapshot이 없으면 anomaly section이 not available로 보인다. failed/unavailable/not loaded가 압축될 수 있다.
170. `apps/vitalserver-runtime-pwa/src/pages/observability/ObservabilityPage.tsx`: anomaly array length `0`은 "No recorder anomalies"로 표시된다. readError가 없으면 empty와 unobserved가 섞인다.
171. `apps/vitalserver-runtime-pwa/src/pages/observability/ObservabilityPage.tsx`: anomaly key fallback이 kind/index를 사용한다. anomaly identity missing을 UI가 보정한다.
172. `apps/vitalserver-runtime-pwa/src/pages/observability/ObservabilityPage.tsx`: period select value를 `RuntimeEventPeriod`로 cast한다. invalid UI state를 type system이 보장하지 않는다.
173. `apps/vitalserver-runtime-pwa/src/pages/observability/ObservabilityPage.tsx`: event list에서 `events ?? []`를 사용한다. contract omission이 empty list로 보일 수 있다.
174. `apps/vitalserver-runtime-pwa/src/pages/observability/ObservabilityPage.tsx`: event key가 id 누락 시 timestamp를 사용한다. event identity missing이 숨겨진다.
175. `apps/vitalserver-runtime-pwa/src/pages/observability/ObservabilityPage.tsx`: anomaly severity 누락이 `unknown`으로 표시된다.
176. `apps/vitalserver-runtime-pwa/src/pages/observability/ObservabilityPage.tsx`: anomaly kind 누락이 `unknown`으로 표시된다.
177. `apps/vitalserver-runtime-pwa/src/pages/observability/ObservabilityPage.tsx`: anomaly subject 누락이 `Unknown subject`로 표시된다.
178. `apps/vitalserver-runtime-pwa/src/pages/observability/ObservabilityPage.tsx`: anomaly message 누락이 default message로 표시된다.
179. `apps/vitalserver-runtime-pwa/src/pages/observability/ObservabilityPage.tsx`: event operation/source display가 `operation || source`로 fallback된다. event origin과 operation state가 섞인다.
180. `apps/vitalserver-runtime-pwa/src/pages/observability/ObservabilityPage.tsx`: event heading이 message, eventType, default text 순서로 fallback된다. missing event message가 contract issue로 보이지 않는다.
181. `apps/vitalserver-runtime-pwa/src/pages/observability/ObservabilityPage.tsx`: non-loaded VitalDB snapshot이 모두 `null` observation으로 변환된다.
182. `apps/vitalserver-runtime-pwa/src/pages/observability/ObservabilityPage.tsx`: observer status는 observation absence를 `Unavailable`로만 표현한다.
183. `apps/vitalserver-runtime-pwa/src/pages/observability/ObservabilityPage.tsx`: unknown anomaly severity tone이 neutral이다. invalid severity와 informational state가 visually 동일해질 수 있다.
184. `apps/vitalserver-runtime-pwa/src/pages/logs/LogsPage.tsx`: default log source가 `containers`로 고정된다. 최근 helper message 문제와 직접 연결된 source owner가 UI 기본값에 묶인다.
185. `apps/vitalserver-runtime-pwa/src/pages/logs/LogsPage.tsx`: default line limit이 `500`이다. log availability와 truncation state가 별도 표시되지 않는다.
186. `apps/vitalserver-runtime-pwa/src/pages/logs/LogsPage.tsx`: live mode가 기본 `true`다. polling/read freshness state가 명시 contract 없이 UI interval에 의존한다.
187. `apps/vitalserver-runtime-pwa/src/pages/logs/LogsPage.tsx`: export destination 기본값이 `/tmp/vitalserver-logs.zip`이다. host-side writable path capability와 UI default가 섞인다.
188. `apps/vitalserver-runtime-pwa/src/pages/logs/LogsPage.tsx`: log text missing이 empty string으로 처리된다.
189. `apps/vitalserver-runtime-pwa/src/pages/logs/LogsPage.tsx`: export destination display가 `file://` prefix를 제거한다. returned URI contract가 UI string 처리에 의존한다.
190. `apps/vitalserver-runtime-pwa/src/pages/logs/LogsPage.tsx`: empty log text가 "No log lines"로 표시된다. read succeeded empty와 response missing이 섞인다.
191. `apps/vitalserver-runtime-pwa/src/pages/logs/LogsPage.tsx`: canExportLogs missing이 disabled 상태로 표시된다. capability read failure와 unsupported capability가 구분되지 않는다.
192. `apps/vitalserver-runtime-pwa/src/pages/settings/SettingsPage.tsx`: empty settings draft로 먼저 렌더링된다. settings load 전 draft가 domain-like form state를 만든다.
193. `apps/vitalserver-runtime-pwa/src/pages/settings/SettingsPage.tsx`: runtimeControlPort parse failure가 `Unknown` preview로 표시된다. invalid input과 missing setting이 섞인다.
194. `apps/vitalserver-runtime-pwa/src/pages/settings/SettingsPage.tsx`: minimumDiskGiB missing이 input min `1`로 보정된다.
195. `apps/vitalserver-runtime-pwa/src/pages/settings/SettingsPage.tsx`: custom advertised URL 해제 시 publicHost를 empty string으로 만든다. absent와 explicit empty가 같은 request가 된다.
196. `apps/vitalserver-runtime-pwa/src/pages/settings/SettingsPage.tsx`: custom advertised URL 해제 시 publicPort를 proxyPort draft로 보정한다. derived state가 UI에 생긴다.
197. `apps/vitalserver-runtime-pwa/src/pages/settings/SettingsPage.tsx`: default advertised URL text가 `draft.proxyPort || 80`에 의존한다.
198. `apps/vitalserver-runtime-pwa/src/pages/settings/SettingsPage.tsx`: startOnBoot disabled 조건이 settings capability와 service capability를 UI에서 조합한다.
199. `apps/vitalserver-runtime-pwa/src/pages/settings/SettingsPage.tsx`: apply success exitCode missing이 `unknown`으로 표시된다.
200. `apps/vitalserver-runtime-pwa/src/pages/settings/SettingsPage.tsx`: runtime control port change redirect가 fixed 1초 timeout에 의존한다. apply completion state와 server readiness가 분리되지 않는다.
201. `apps/vitalserver-runtime-pwa/src/config/appSettings.ts`: API base URL missing이 empty string default로 처리된다.
202. `apps/vitalserver-runtime-pwa/src/config/appSettings.ts`: dev proxy target이 API base URL 또는 local default로 fallback된다.
203. `apps/vitalserver-runtime-pwa/src/config/appSettings.ts`: token missing이 dev token으로 fallback된다. production/runtime auth contract와 dev default 경계 확인이 필요하다.
204. `apps/vitalserver-runtime-pwa/src/config/appSettings.ts`: invalid numeric env value가 fallback number로 조용히 대체된다.
205. `apps/vitalserver-runtime-pwa/src/config/appSettings.ts`: invalid port env value가 fallback port로 대체된다.
206. `apps/vitalserver-runtime-pwa/src/config/appSettings.ts`: unknown boolean env value가 false로 해석된다. invalid config와 explicit false가 섞인다.
207. `apps/vitalserver-runtime-pwa/src/domain/runtime-control/formatting/time.ts`: missing datetime이 `Unknown`으로 표시된다.
208. `apps/vitalserver-runtime-pwa/src/domain/runtime-control/formatting/time.ts`: invalid local datetime은 raw value를 그대로 표시한다. invalid state가 typed error로 표면화되지 않는다.
209. `apps/vitalserver-runtime-pwa/src/domain/runtime-control/formatting/time.ts`: invalid uptime datetime이 `Unknown`으로 표시된다.
210. `apps/vitalserver-runtime-pwa/src/domain/runtime-control/formatting/http.ts`: successful HTTP 여부가 regex로 판단된다. HTTP state owner 대신 display parser가 reachability를 추정한다.
211. `apps/vitalserver-runtime-pwa/src/domain/runtime-control/formatting/http.ts`: missing HTTP status가 `Unknown`으로 표시된다.
212. `apps/vitalserver-runtime-pwa/src/domain/runtime-control/formatting/http.ts`: `failed` string을 unreachable로 해석한다. string contract가 typed status를 대체한다.
213. `apps/vitalserver-runtime-pwa/src/domain/runtime-control/formatting/http.ts`: runtime URL host가 browser location 또는 `127.0.0.1`로 추정된다.
214. `apps/vitalserver-runtime-pwa/src/domain/runtime-control/formatting/http.ts`: runtime URL port가 missing 시 app default proxy port로 대체된다.
215. `apps/vitalserver-runtime-pwa/src/domain/runtime-control/formatting/http.ts`: runtime control URL이 missing port 시 current origin 또는 local default로 대체된다.
216. `apps/vitalserver-runtime-pwa/src/domain/runtime-control/formatting/status.ts`: missing recorder status가 `Unknown`으로 표시된다.
217. `apps/vitalserver-runtime-pwa/src/domain/runtime-control/formatting/status.ts`: unknown recorder status label이 raw value로 표시된다. contract drift가 explicit error로 보이지 않는다.
218. `apps/vitalserver-runtime-pwa/src/domain/runtime-control/formatting/status.ts`: nullable boolean이 `Unknown`으로 표시된다. unavailable, not reported, invalid이 구분되지 않는다.
219. `apps/vitalserver-runtime-pwa/src/domain/runtime-control/formatting/runtimeState.ts`: missing runtime state가 `Unknown`으로 표시된다.
220. `apps/vitalserver-runtime-pwa/src/domain/runtime-control/formatting/runtimeState.ts`: unrecognized runtime state가 raw value로 표시된다. provider/client schema drift가 지나갈 수 있다.
221. `apps/vitalserver-runtime-pwa/src/domain/runtime-control/formatting/vitalRecorder.ts`: source가 vitalDBObservation이 아니면 metric 전체를 `NOT_REPORTED`로 처리한다. unavailable reason이 metric 단위로 사라진다.
222. `apps/vitalserver-runtime-pwa/src/console/hooks.ts`: overview polling interval이 2초로 고정된다. freshness owner가 API stream/result contract가 아니라 UI polling에 있다.
223. `apps/vitalserver-runtime-pwa/src/console/hooks.ts`: events polling interval이 5초로 고정된다. event delivery state가 polling에 의존한다.
224. `apps/vitalserver-runtime-pwa/src/console/hooks.ts`: settings polling interval이 5초로 고정된다. apply/read consistency 상태가 명시되지 않는다.
225. `apps/vitalserver-runtime-pwa/src/console/hooks.ts`: recorders/beds polling interval이 5초로 고정된다. recorder state lag가 UI interval에 묶인다.
226. `apps/vitalserver-runtime-pwa/src/console/hooks.ts`: host logs request가 helperMessage를 empty string으로 보낸다.
227. `apps/vitalserver-runtime-pwa/src/console/hooks.ts`: live log refetch interval이 2초로 고정된다. stream state와 polling state가 분리되지 않는다.
228. `apps/vitalserver-runtime-pwa/src/console/hooks.ts`: TestKit status polling interval이 2초로 고정된다.
229. `apps/vitalserver-runtime-pwa/src/console/hooks.ts`: create beds request에서 roomNames missing이 `[]`로 보정된다.
230. `apps/vitalserver-runtime-pwa/src/console/hooks.ts`: session action request가 `sessionID: null`을 허용한다. active session selection owner가 API/manager로 넘어간다.
231. `apps/vitalserver-runtime-pwa/src/console/hooks.ts`: TestKit mutation success가 status/recorders/beds를 모두 invalidate한다. 실제 변경 범위와 invalidation 범위가 분리되어 있지 않다.
232. `apps/vitalserver-runtime-pwa/src/console/requestBuilders.ts`: backup/update bundle request가 localPath kind를 UI builder에서 만든다.
233. `apps/vitalserver-runtime-pwa/src/console/requestBuilders.ts`: TestKit create beds request가 adminUserId `admin`을 builder에서 고정한다.
234. `apps/vitalserver-runtime-pwa/src/console/requestBuilders.ts`: sessionID trim 결과가 empty이면 `null`로 바뀐다.
235. `apps/vitalserver-runtime-pwa/src/infrastructure/console-api/consoleClient.ts`: client baseURL missing이 default app setting으로 fallback된다.
236. `apps/vitalserver-runtime-pwa/src/infrastructure/console-api/consoleClient.ts`: client token missing이 default app setting으로 fallback된다.
237. `apps/vitalserver-runtime-pwa/src/infrastructure/console-api/consoleClient.ts`: fetch implementation missing이 global fetch로 fallback된다. runtime dependency source가 implicit이다.
238. `apps/vitalserver-runtime-pwa/src/infrastructure/console-api/consoleClient.ts`: DELETE body가 항상 JSON string으로 인코딩된다. undefined body와 empty command semantics가 분리되지 않는다.
239. `apps/vitalserver-runtime-pwa/src/infrastructure/console-api/consoleClient.ts`: URL builder drops query values that are undefined. missing filter and explicit unset are identical.
240. `apps/vitalserver-macos-runtime/Sources/RuntimeControlAPI/Boundary/RuntimeControlHTTPBoundary.swift`: VitalDB recorders/recorder/relationships endpoints return nil for stream routing. unsupported stream capability is implicit.
241. `apps/vitalserver-macos-runtime/Sources/RuntimeControlAPI/Boundary/RuntimeControlHTTPBoundary.swift`: VitalDB observation stream returns only `snapshot.observation`. read state/readError is lost in the stream payload.
242. `apps/vitalserver-macos-runtime/Sources/RuntimeControlAPI/Boundary/RuntimeControlHTTPBoundary.swift`: error stream JSON encoding failure yields empty Data.
243. `apps/vitalserver-macos-runtime/Sources/RuntimeControlAPI/Boundary/RuntimeControlHTTPBoundary.swift`: error response JSON encoding failure yields nil body.
244. `apps/vitalserver-macos-runtime/Sources/RuntimeControlAPI/Boundary/RuntimeControlHTTPBoundary.swift`: SSE data invalid UTF-8 becomes `{}`.
245. `apps/vitalserver-macos-runtime/Sources/RuntimeControlAPI/Boundary/RuntimeControlHTTPBoundary.swift`: SSE id missing becomes empty string.
246. `apps/vitalserver-macos-runtime/Sources/RuntimeControlAPI/Boundary/RuntimeControlHTTPBoundary.swift`: SSE event missing becomes `message`.
247. `apps/vitalserver-macos-runtime/Sources/RuntimeControlAPI/Boundary/RuntimeControlHTTPBoundary.swift`: query parameter duplicate names are collapsed into the last value.
248. `apps/vitalserver-macos-runtime/Sources/RuntimeControlAPI/Boundary/RuntimeControlHTTPBoundary.swift`: runtime event limit missing becomes default limit.
249. `apps/vitalserver-macos-runtime/Sources/RuntimeControlAPI/Boundary/RuntimeControlHTTPBoundary.swift`: runtime event type query maps raw value without rejecting unknown values at boundary.
250. `apps/vitalserver-macos-runtime/Sources/RuntimeControlAPI/Boundary/RuntimeControlHTTPBoundary.swift`: runtime log source missing defaults to helperMessage.
251. `apps/vitalserver-macos-runtime/Sources/RuntimeControlAPI/Boundary/RuntimeControlHTTPBoundary.swift`: runtime log line limit missing defaults to 200.
252. `apps/vitalserver-macos-runtime/Sources/RuntimeControlAPI/Boundary/RuntimeControlHTTPBoundary.swift`: runtime log helperMessage missing defaults to empty string.
253. `apps/vitalserver-macos-runtime/Sources/RuntimeControlAPI/Boundary/RuntimeControlHTTPBoundary.swift`: decoded body failure collapses all decode details to generic invalidBody.
254. `apps/vitalserver-macos-runtime/Sources/RuntimeControlAPI/Testing/RuntimeTestKitAPIRouter.swift`: pause/resume/stop/delete accept optional body and nil sessionID.
255. `apps/vitalserver-macos-runtime/Sources/RuntimeControlAPI/Testing/RuntimeTestKitAPIRouter.swift`: optionalDecodedBody returns nil for empty body, making missing command target an accepted state.
256. `apps/vitalserver-macos-runtime/Sources/RuntimeControlAPI/Testing/RuntimeTestKitAPIRouter.swift`: all route errors become internalServerError/handlerFailed. bad request and handler failure are not separated.
257. `apps/vitalserver-macos-runtime/Sources/RuntimeControlAPI/Testing/RuntimeTestKitAPIRouter.swift`: error response body uses `try?` encoding and can become nil.
258. `apps/vitalserver-macos-runtime/Sources/MacHostRuntimeAdapter/RuntimeObservabilityReader.swift`: default current observation provider is live(paths). test/production provider ownership is implicit.
259. `apps/vitalserver-macos-runtime/Sources/MacHostRuntimeAdapter/RuntimeObservabilityReader.swift`: `loadVitalDBObservation()` returns only observation, losing snapshot state and readError.
260. `apps/vitalserver-macos-runtime/Sources/MacHostRuntimeAdapter/RuntimeObservabilityReader.swift`: current live observation takes precedence over projected observation. source freshness and projection consistency need explicit policy.
261. `apps/vitalserver-macos-runtime/Sources/MacHostRuntimeAdapter/RuntimeObservabilityReader.swift`: if projection load fails but current observation exists, state is still loaded with readError. partial failure semantics need explicit UI handling.
262. `apps/vitalserver-macos-runtime/Sources/MacHostRuntimeAdapter/RuntimeObservabilityReader.swift`: loadVitalDBRecorders catches observation load failure and continues with empty observations.
263. `apps/vitalserver-macos-runtime/Sources/MacHostRuntimeAdapter/RuntimeObservabilityReader.swift`: activity bucket load failure produces empty buckets and unavailable activity history.
264. `apps/vitalserver-macos-runtime/Sources/MacHostRuntimeAdapter/RuntimeObservabilityReader.swift`: relationship assignment load failure produces empty assignments with readError.
265. `apps/vitalserver-macos-runtime/Sources/MacHostRuntimeAdapter/RuntimeObservabilityReader.swift`: relationship event load failure produces empty events with readError.
266. `apps/vitalserver-macos-runtime/Sources/MacHostRuntimeAdapter/RuntimeObservabilityReader.swift`: guest runtime state missing is ignored before falling back to runtime status observation.
267. `apps/vitalserver-macos-runtime/Sources/MacHostRuntimeAdapter/RuntimeObservabilityReader.swift`: runtime status missing is ignored before returning unavailable.
268. `apps/vitalserver-macos-runtime/Sources/MacHostRuntimeAdapter/RuntimeObservabilityReader.swift`: bed assignment status raw value fallback is `.unknown`.
269. `apps/vitalserver-macos-runtime/Sources/RuntimeControl/RuntimeControlReadModels.swift`: RuntimeVitalRecorderActivityPoint decode defaults roomCount to `0`.
270. `apps/vitalserver-macos-runtime/Sources/RuntimeControl/RuntimeControlReadModels.swift`: RuntimeVitalRecorderActivityPoint decode defaults messagesPerSecond to `0`.
271. `apps/vitalserver-macos-runtime/Sources/RuntimeControl/RuntimeControlReadModels.swift`: RuntimeVitalRecorderActivityPoint decode defaults bytesPerSecond to `0`.
272. `apps/vitalserver-macos-runtime/Sources/RuntimeControl/RuntimeControlReadModels.swift`: activity buckets missing decodes to empty array.
273. `apps/vitalserver-macos-runtime/Sources/RuntimeControl/RuntimeControlReadModels.swift`: RuntimeVitalRecorderHistory missing activity history becomes unavailable without source-specific reason.
274. `apps/vitalserver-macos-runtime/Sources/RuntimeControl/RuntimeControlReadModels.swift`: vital recorder summary activeConnections defaults to `0` when audit proxy status is absent.
275. `apps/vitalserver-macos-runtime/Sources/RuntimeControl/RuntimeControlReadModels.swift`: unavailable vital recorder summary emits zero known/online/stale counts.
276. `apps/vitalserver-macos-runtime/Sources/RuntimeControl/RuntimeControlReadModels.swift`: duplicate recorder observations are collapsed by preferredRecorder. duplicate state can disappear unless anomaly policy preserves it.
277. `apps/vitalserver-macos-runtime/Sources/RuntimeControl/RuntimeControlReadModels.swift`: duplicate bed observations are collapsed by preferredBed.
278. `apps/vitalserver-macos-runtime/Sources/RuntimeControl/RuntimeControlReadModels.swift`: timestamp comparison uses lexical string comparison rather than parsed time.
279. `apps/vitalserver-macos-runtime/Sources/RuntimeControl/RuntimeControlReadModels.swift`: recorder builder uses observation timestamp when recorder lastSeenAt is missing.
280. `apps/vitalserver-macos-runtime/Sources/RuntimeControl/RuntimeControlReadModels.swift`: recorder builder preserves previous IP/version/bed when latest observation omits fields.
281. `apps/vitalserver-macos-runtime/Sources/RuntimeControl/RuntimeControlReadModels.swift`: missing latest recorder maps to offline.
282. `apps/vitalserver-macos-runtime/Sources/RuntimeControl/RuntimeControlReadModels.swift`: projected activity timeline missing becomes empty array.
283. `apps/vitalserver-macos-runtime/Sources/RuntimeControl/RuntimeControlReadModels.swift`: bed builder uses observation timestamp when bed lastSeenAt is missing.
284. `apps/vitalserver-macos-runtime/Sources/RuntimeControl/RuntimeControlReadModels.swift`: missing latest bed maps to offline.
285. `apps/vitalserver-macos-runtime/Sources/RuntimeControl/RuntimeControlReadModels.swift`: present but not online bed maps to stale without explicit stale owner field.
286. `apps/vitalserver-macos-runtime/Sources/Core/Health/RuntimeWatchdogRecoveryPolicy.swift`: unhealthy snapshot with empty failureReasons becomes "no failure reason reported".
287. `apps/vitalserver-macos-runtime/Sources/Core/Health/RuntimeWatchdogRecoveryPolicy.swift`: automatic recovery suppression only checks protected vmErrors, not other preservation-sensitive states.
288. `apps/vitalserver-macos-runtime/Sources/Core/Health/RuntimeWatchdogRecoveryPolicy.swift`: missing lifecycle means no deferral reason.
289. `apps/vitalserver-macos-runtime/Sources/Core/Health/RuntimeVMHealthPolicy.swift`: non-numeric guest HTTP status is treated as unsuccessful.
290. `apps/vitalserver-macos-runtime/Sources/Core/Health/RuntimeVMHealthPolicy.swift`: missing vmIP is interpreted as missingIPAddress error.
291. `apps/vitalserver-macos-runtime/Sources/Core/Health/RuntimeVMHealthPolicy.swift`: runtime state missing maps to starting or unreachable depending on vmIP.
292. `apps/vitalserver-macos-runtime/Sources/Core/Health/RuntimeVMHealthPolicy.swift`: guest bootstrap missing result yields no bootstrap failure.
293. `apps/vitalserver-macos-runtime/Sources/Core/Health/RuntimeHealthWaiter.swift`: pending required services take precedence over snapshot failure reasons.
294. `apps/vitalserver-macos-runtime/Sources/Core/Health/RuntimeHealthWaiter.swift`: timeout returns only last reasons. earlier distinct failure states can be lost.
295. `apps/vitalserver-macos-runtime/Sources/Core/Guest/GuestBootstrapEvaluator.swift`: missing bootstrap result returns nil failure reason.
296. `apps/vitalserver-macos-runtime/Sources/Core/Guest/GuestActivationEvaluator.swift`: missing activation result is treated as waiting for worker.
297. `apps/vitalserver-macos-runtime/Sources/Core/Guest/GuestShutdownEvaluator.swift`: missing shutdown result is treated as waiting for worker.
298. `apps/vitalserver-macos-runtime/Sources/Core/Guest/DatastoreRepairEvaluator.swift`: missing datastore repair result is treated as waiting for worker.
299. `apps/vitalserver-macos-runtime/Sources/Core/Application/RuntimeUpdatePreflightPolicy.swift`: missing installed/incoming rootfs size contributes `0` to required storage.
300. `apps/vitalserver-macos-runtime/Sources/HostInfrastructure/CompositeRuntimeEventRepository.swift`: SQLite append failure가 log만 남기고 primary event append를 실패시키지 않는다. secondary observability 손실이 운영상 조용히 남을 수 있다.

## Classification Pass 1

분류일: 2026-06-01

이 분류는 후보 설명 기준의 1차 triage이다. 코드 수정 전에 해당 파일의 실제 역할, 호출 경로, 테스트 의도를 다시 확인해야 한다. 다만 AGENTS.md 기준으로 어느 방향의 작업으로 분해할지는 아래 판정으로 시작한다.

| Class | Count | Candidate IDs | Meaning | First fix direction |
|---|---:|---|---|---|
| A. AGENTS.md 위반 가능성 높음 | 244 | 1-5, 8-10, 14-27, 31-49, 51-55, 57-87, 89-126, 129-132, 134-139, 141-147, 149-160, 162-170, 172-173, 175-182, 188, 190-192, 194-200, 209-215, 219-221, 226, 230, 232, 234-236, 238-239, 241-247, 249, 252-253, 256-265, 268-279, 281-300 | 상태 owner가 아닌 계층이 상태를 추론하거나, read/decode/permission/persistence 실패가 빈 값, `0`, `Unknown`, 성공 비슷한 결과로 축소될 수 있다. | typed result/contract로 분리한다. UI는 표시만 하고, Host/adapter/recovery 계층은 명시 상태만 소비하게 한다. |
| B. 명시 기본값으로 유지 가능성 있음 | 29 | 6-7, 11-13, 30, 184-187, 201-206, 222-225, 227-229, 231, 233, 237, 248, 250-251 | form preset, polling interval, documented config default, API limit 같은 값일 가능성이 있다. API command 경계에서는 fallback이 아니라 명시 contract default일 때만 허용된다. | default owner, scope, mode를 provider/API/config contract에 문서화하고 테스트한다. dev-only default는 production path에서 분리한다. |
| C. 표시 전용 fallback로 유지 가능 | 18 | 28-29, 50, 56, 133, 140, 148, 161, 171, 174, 183, 189, 193, 207-208, 216-218 | React key, selection 초기값, display label, formatting fallback처럼 domain state를 만들지 않는 경우일 수 있다. | upstream 상태가 explicit인지 확인한다. fallback 이름을 display policy로 한정하고 decision/input model에는 넣지 않는다. |
| D. 삭제 또는 경계 재설계 후보 | 9 | 88, 127-128, 240, 254-255, 266-267, 280 | default password, optional provider, implicit unsupported route, optional command body, old observation fallback처럼 unreleased compatibility 또는 책임 경계 우회일 가능성이 높다. | 유지 사유가 없으면 삭제한다. 필요한 경우 명시 migration 또는 explicit unsupported/error contract로 바꾼다. |

## Priority Buckets

1. P0: destructive/recovery/update decision에 영향을 주는 A/D 항목
   - 62-83, 88-90, 103-105, 240, 254-255, 266-267, 286-299
2. P1: observability/read model에서 실패를 빈 값으로 만드는 A 항목
   - 91-100, 113-122, 165-183, 241-247, 258-265, 269-285, 300
3. P1: PWA contract/schema와 page state가 provider failure를 숨기는 A 항목
   - 1-5, 8-10, 14-27, 31-47, 131-164, 188, 190-200, 209-221, 226, 230, 232, 234-239
4. P2: Swift presentation/display policy가 read model을 재구성하는 A/C 항목
   - 48-61, 62-70
5. P2: 명시 default로 남길 수 있으나 계약화가 필요한 B 항목
   - 6-7, 11-13, 30, 184-187, 201-206, 222-225, 227-229, 231, 233, 237, 248, 250-251

## Triage Direction

1. High risk first:
   - Recovery/restart decisions
   - Runtime health/readiness
   - Update flow
   - Observability storage/read failure
2. Then UI state:
   - PWA and Swift UI must render explicit read result states, not synthesize domain state.
3. Then provider contracts:
   - Response schema optional fields should be reduced to explicit discriminated states.
   - Where optional is valid, document why it is a domain value, not a fallback.
4. Then low-risk display text:
   - `Unknown`, `not reported`, `-` can remain only when backed by explicit missing/notReported states.

## Fix Principles

- Replace `T?`, `[]`, `0`, and empty string fallback with typed read results where the value crosses a layer boundary.
- Let provider contracts represent:
  - available value
  - missing provider state
  - stale provider state
  - permission/read failure
  - decode/contract failure
  - unsupported feature
  - observed zero/empty value
- Keep UI as formatter only. It may choose labels, but it must not create runtime state.
- Recovery planner must consume explicit lifecycle/health contracts, not infer state from probes alone.
- If a fallback is retained for display only, name it as display fallback and keep it out of domain/read models.
- Avoid compatibility branches for unreleased behavior unless a migration is explicitly defined.

## Prevention Checklist

- New runtime contracts must include tests for missing, invalid, failed, and zero/empty states separately.
- Schema tests must fail when required provider-owned state is omitted.
- UI tests must verify that read failures are visible and not rendered as empty/zero states.
- Recovery planner tests must assert that missing explicit state does not trigger destructive action.
- Observability adapters must surface read/decode/persistence issues through result types.

## Next Steps

- Validate the classification against source code before editing:
  - A: confirm owner boundary and replace fallback with explicit result states.
  - B: decide and document the real default owner.
  - C: keep only if it remains display-only after upstream state is explicit.
  - D: delete unless a migration or explicit unsupported contract is required.
- Split fixes into focused TS items by layer and risk.
- Start with recovery planner, runtime status reader, observability repositories, and PWA contract schemas.
