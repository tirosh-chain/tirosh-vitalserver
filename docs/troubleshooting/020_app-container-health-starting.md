# 020 app container가 오래 `health: starting` 상태

> ID: TS-020  
> Category: Guest containers  
> Owner: macOS runtime  
> Status: active

증상:

```text
vitalserver-app-1   Up ... (health: starting)
```

원인:

Apple Silicon Linux guest에서는 container image도 `linux/arm64`로 맞춥니다. 첫 build/pull 직후에는 Docker image load, Redis healthcheck, VitalServer worker boot 때문에 시작이 느릴 수 있습니다.

확인:

```sh
ssh ubuntu@<vm-ip> 'sudo docker inspect -f "{{json .State.Health}}" vitalserver-app-1'
ssh ubuntu@<vm-ip> 'sudo docker logs --tail 120 vitalserver-app-1'
```

worker가 `listening` 상태까지 갔는지 확인합니다.

## Follow-up

- 관련 issue/PR, 재현 로그, 수정 버전, 운영 판단이 생기면 이 섹션에 추가합니다.
