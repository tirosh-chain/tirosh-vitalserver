#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
bundle_path="${VM_DOCKER_IMAGE_BUNDLE:-${repo_root}/.tmp/vitalserver-vm-pkg/docker-images/vitalserver-images.tar.gz}"
platform="${VM_DOCKER_IMAGE_PLATFORM:-linux/amd64}"

images=(
  "vitalserver:2.3.4"
  "redis:3.2.12-alpine"
  "rediscommander/redis-commander:latest"
  "swaggerapi/swagger-ui:v5.17.14"
)

mkdir -p "$(dirname "${bundle_path}")"

printf "Preparing Docker image bundle\n"
printf "VitalServer image platform: %s\n" "${platform}"
printf "Bundle: %s\n" "${bundle_path}"

docker pull redis:3.2.12-alpine
docker pull rediscommander/redis-commander:latest
docker pull swaggerapi/swagger-ui:v5.17.14

docker buildx build \
  --platform "${platform}" \
  --load \
  -t vitalserver:2.3.4 \
  -f "${repo_root}/apps/vitalserver/docker/Dockerfile" \
  "${repo_root}"

tmp_bundle="${bundle_path}.tmp"
docker save "${images[@]}" | gzip -c >"${tmp_bundle}"
mv "${tmp_bundle}" "${bundle_path}"

printf "Docker image bundle is ready: %s\n" "${bundle_path}"
