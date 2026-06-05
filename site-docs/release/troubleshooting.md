# Troubleshooting

이 문서는 Vital Server Helper 현장 장애 대응 원칙을 설명합니다.

장애 대응 문서는 항상 증상, 원인, 확인 방법, 조치 방향, 예방 원칙을 함께 적습니다.

## 기본 원칙

- 상태를 추측하지 않습니다.
- missing, invalid, failed, stale, empty를 구분합니다.
- 권한 실패와 빈 결과를 섞지 않습니다.
- decode 실패와 파일 없음은 다른 상태로 기록합니다.
- cloud 모드 장애는 병원 내 기본 모드 장애와 분리합니다.

## 공통 증상

| 증상 | 먼저 확인할 것 |
|---|---|
| VitalServer URL 접근 불가 | Status, proxy 상태, network 설정 |
| VRecorder 미연결 | VRecorder IP, 병원 내부망 연결, 최근 데이터 전송 시각 |
| `.vital` 파일 없음 | 저장 directory, 권한, 실제 업로드 여부 |
| `.vital` sanity check 실패 | 파일명, 파일 크기, decode/read 실패 여부 |
| Health Check stale | 마지막 관측 시각, runtime 상태, observer 상태 |
| update 실패 | bundle 검증 결과, 적용 로그, rollback 여부 |

## 장애 기록 형식

```text
Symptom:
Cause:
How to check:
Fix direction:
Prevention:
```

현장 장애가 반복되면 dev troubleshooting 문서에 내부 원인과 예방 원칙을 추가합니다.
