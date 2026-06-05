# 007 nginx가 `502 Bad Gateway`를 반환

> ID: TS-007  
> Category: Runtime health  
> Owner: macOS runtime  
> Status: active

증상:

```sh
curl -I http://<vm-ip>/
```

결과가 `502 Bad Gateway`입니다.

원인:

VM 내부 Compose edge nginx는 `app:80`의 VitalServer container로 proxy합니다. app container가 아직 healthy가 아니거나 HTTP worker가 뜨지 않으면 502가 납니다.

확인:

```sh
ssh ubuntu@<vm-ip> 'sudo docker ps'
ssh ubuntu@<vm-ip> 'sudo docker logs --tail 120 vitalserver-app-1'
ssh ubuntu@<vm-ip> 'sudo docker compose --project-name vitalserver -f /mnt/tirosh/deploy/compose.yaml ps'
ssh ubuntu@<vm-ip> 'curl -I http://127.0.0.1/'
```

이번 PoC에서는 `VITALSERVER_MIN_CPUS=6` 때문에 upstream VitalServer가 worker를 0개만 만들었습니다.

```js
numCPUs = os.cpus().length - 6
```

## Follow-up

- 관련 issue/PR, 재현 로그, 수정 버전, 운영 판단이 생기면 이 섹션에 추가합니다.
