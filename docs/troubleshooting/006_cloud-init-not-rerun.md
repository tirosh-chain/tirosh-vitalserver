# 006 cloud-init이 bootstrap을 다시 실행하지 않음

> ID: TS-006  
> Category: Guest bootstrap  
> Owner: macOS runtime  
> Status: active

증상:

`seed.iso`를 다시 만들어도 `/mnt/tirosh/deploy/bootstrap.sh`가 실행되지 않습니다.

원인:

cloud-init은 `instance-id`를 기준으로 이미 처리한 instance인지 판단합니다. 같은 instance-id를 재사용하면 초기화 스크립트를 다시 실행하지 않을 수 있습니다.

조치:

`make devtools/cloud-init`은 기본적으로 새 instance-id를 생성합니다. 수동으로 지정하려면:

```sh
uv run --project packages/vitalserver-devtools vitalserver-devtools \
  --config config/vm-build.toml \
  cloud-init \
  --runtime-dir ~/.tirosh/vitalserver-vm/runtime \
  --instance-id tirosh-site-a-001
```

## Follow-up

- 관련 issue/PR, 재현 로그, 수정 버전, 운영 판단이 생기면 이 섹션에 추가합니다.
