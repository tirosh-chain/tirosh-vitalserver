# Deployment Modes

Vital Server Helper는 병원 내 기본 모드와 병원 외 cloud 선택 모드를 구분합니다.

기본 모드는 병원 내부망 운영입니다. cloud 연계는 병원이 outbound 연결을 허용하는
경우에만 추가로 지원합니다.

## 병원 내 기본 모드

병원 내 기본 모드는 Vital Server Helper 장비가 병원 내부망에 설치되고,
VRecorder와 운영자가 같은 내부망에서 접근하는 방식입니다.

```text
VRecorder / Browser
  -> 병원 내부망
      -> Vital Server Helper
          -> VitalServer
          -> Health Check
```

특징:

- 외부 outbound 없이 운영 가능
- 병원 내부망 정책 안에서 설치와 운영 가능
- VRecorder 연결과 `.vital` 저장 데이터 확인 가능
- Health Check 결과는 병원 내부 운영자가 확인

## Cloud 선택 모드

Cloud 선택 모드는 병원이 outbound 연결을 허용하는 경우에만 지원합니다.

```text
Vital Server Helper
  -> 병원 outbound 허용 구간
      -> cloud service
```

이 모드는 아래 전제가 필요합니다.

| 전제 | 설명 |
|---|---|
| outbound 허용 | 병원 보안 정책에서 외부 연결을 명시적으로 허용 |
| 데이터 범위 합의 | 어떤 상태 또는 데이터를 외부로 보낼지 사전 합의 |
| 보안 정책 확인 | 인증, 암호화, 접근 제어, audit 기준 확인 |
| 장애 대응 기준 | 연결 실패, 전송 실패, 지연 상태를 명시적으로 표시 |

cloud 선택 모드는 병원 내 기본 모드를 대체하지 않습니다. 병원 내부망 운영을 기본으로
두고, 허용된 병원에만 추가합니다.
