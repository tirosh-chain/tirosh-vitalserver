# Scope and GitHub Issues

이 문서는 Vital Server Helper 공개 문서가 다루는 범위와 GitHub issue 기준을 설명합니다.

## Documentation Scope

| 범위 | 설명 |
|---|---|
| 설치 전 검토 | 병원 내부망, Mac appliance, 저장 위치, 운영자 접근 경로 확인 |
| 현장 설치 흐름 | installer 실행, 초기 설정, Health Check 확인 |
| 운영 확인 | Status, Logs, Update, Health Check 결과 해석 |
| 장애 대응 원칙 | missing, invalid, failed, stale, empty 상태 구분 |
| 업데이트 원칙 | offline update bundle 검증, 적용, rollback 결과 확인 |

이 문서는 상세한 병원별 구축 제안서나 운영 계약서를 대체하지 않습니다.

## Good GitHub Issues

아래 항목은 GitHub repository issue로 다루기 적합합니다.

- 재현 가능한 코드 문제
- 재현 가능한 testkit, observer, PWA, Runtime Control API 문제
- 문서 오류 또는 command 불일치
- 범위가 작은 변경 제안
- release artifact 검증 실패 보고

GitHub Issues: <https://github.com/tirosh-chain/tirosh-vitalserver/issues>

## Not For Public GitHub Issues

아래 항목은 공개 issue에 올리지 않습니다.

- 환자 정보, 병원 내부 IP, 인증 정보, 비밀번호, token, 개인식별정보가 포함된 내용
- 병원별 보안 정책 협의
- 현장 설치 일정, 장비 반입, 네트워크 변경 승인
- 의료 행위 또는 임상 판단에 관한 요청

## Non-Goals

Vital Server Helper는 의료 행위나 임상 판단을 자동화하지 않습니다. Health Check는
운영 상태와 데이터 수집 상태를 확인하기 위한 기능이며, 임상적 진단 또는 치료
판단의 근거로 사용하지 않습니다.

Vital Server 자체 기능 변경, Vital Recorder 자체 기능 변경, 의료기기
연결의 임상 검증은 이 프로젝트의 기본 범위가 아닙니다.
