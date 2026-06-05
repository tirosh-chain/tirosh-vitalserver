# Vital Server Helper

Vital Server Helper는 병원 내부망에서 VitalServer를 장기간 운영하고, VRecorder
연결 상태와 저장 데이터 상태를 확인하기 위한 현장 appliance 서비스입니다.

이 문서군은 K-MFDB 구축을 위한 Vital Server Helper 공개/배포 설명을 다룹니다.
내부 구현 세부 사항보다 병원 현장에서 무엇을 제공하고 어떻게 운영하는지에
초점을 둡니다.

## 제공 범위

Vital Server Helper는 아래 기능을 제공합니다.

| 범위 | 설명 |
|---|---|
| VitalServer 운영 | 병원 내부망에서 VitalServer service를 장기간 실행 |
| Health Check | VR/VRecorder 동작 유무와 `.vital` 저장 데이터 sanity check 확인 |
| 운영 상태 확인 | 서비스 상태, 로그, update 상태, 장애 징후 확인 |
| 병원 내 기본 모드 | 외부 outbound 없이 병원 내부망에서 운영 |
| Cloud 선택 모드 | 병원이 outbound를 허용하는 경우에만 외부 cloud 연계 추가 지원 |

## 지원 모드

기본 지원 모드는 병원 내부망 운영입니다. Vital Server Helper 장비는 병원 내부망에
위치하고, VRecorder와 운영자는 병원 내부 네트워크에서 접근합니다.

병원이 outbound 연결을 허용하는 경우에는 cloud 연계 모드를 추가로 지원할 수
있습니다. 이 모드는 병원 보안 정책, 개인정보 처리 기준, 네트워크 정책을 별도로
확인한 뒤 적용합니다.

## 다음 문서

| 목적 | 문서 |
|---|---|
| 연구/배포 배경 이해 | [Research Background](background.md) |
| Mac 하드웨어 기반 appliance 선택 이유 | [Why Mac Hardware](mac-hardware-appliance.md) |
| Health Check 서비스 이해 | [Vital Server Helper Health Check](health-check-service.md) |
| 병원 내/외 사용 모드 비교 | [Deployment Modes](deployment-modes.md) |
| 설치 흐름 확인 | [Installation](installation.md) |
| 운영 흐름 확인 | [Operation](operation.md) |
| 장애 대응 흐름 확인 | [Troubleshooting](troubleshooting.md) |
