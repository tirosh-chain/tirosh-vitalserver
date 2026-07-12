# Docker multi-platform export omitted Guest blobs

> ID: TS-117
> Category: Packaging / Guest bootstrap / Docker image bundle
> Owner: devtools Docker image bundle compiler
> Status: resolved

## Symptoms

`make dist/dmg/dev` can reach the golden rootfs `docker-image-load` stage and
then fail even though the image bundle passes gzip validation:

```text
stage=docker-image-load
docker load -i /mnt/tirosh/deploy/docker-images/vitalserver-images.tar.gz
open .../blobs/sha256/<digest>: no such file or directory
```

The partial manifest can show images loaded before the missing blob. In the
observed case `swaggerapi/swagger-ui:v5.17.14` was the first image that Docker
could not finish loading.

## Cause

The Host compiler used an unqualified `docker save` after platform-specific
pulls. A multi-platform Docker image store can retain an OCI index while only
exporting part of the selected Guest platform material. The resulting gzip tar
is readable, but its legacy `manifest.json` and OCI descriptors can refer to a
config or layer blob that is not in the archive.

This is Host compile material corruption. It is not a Guest Docker data-root,
containerd, filesystem-space, or Compose failure.

## Fix Direction

Export with the configured Guest platform explicitly:

```text
docker image save --platform linux/arm64 <configured images>
```

Immediately verify the produced archive in the compiler: every configured tag
must be present; every legacy Config/Layer reference and OCI descriptor must
exist; OCI descriptor sizes and SHA-256 values must match; and every OCI
platform descriptor, including descriptors inside nested indexes, must match
the configured Guest platform. A missing
platform export or unsupported Docker CLI is a compile failure with the bundle,
image, and platform in its evidence.

## Prevention

Do not treat gzip readability, `docker pull`, or a later Guest `docker load`
failure as image-bundle proof. Platform selection and archive closure belong to
the Docker image bundle compiler. The rootfs smoke keeps `docker load` as the
final Guest consumer proof, but must not be the first place that discovers a
Host-produced dangling archive.

## Related Cases

- `TS-069`: golden rootfs proof must reject failed Docker image load.
- `TS-088`: Compose image/source declarations must match the Guest compile
  material.
- `TS-111`: image architecture must match the target runtime.

## Follow-up

- 2026-07-12: a gzip-valid archive referenced a missing Swagger UI arm64
  config/layer closure. Compile now uses platform-selective export and verifies
  archive closure before Guest boot.
