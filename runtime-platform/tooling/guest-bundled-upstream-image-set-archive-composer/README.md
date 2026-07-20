# Guest bundled Upstream Image-set archive composer

This release-process tool creates the fixed C64 image-set archive consumed by
the Guest-owned Bundled Upstream Image-set Manager. It accepts an explicit
local Compose file and explicit OCI/Docker image archive source paths, writes a
new deterministic `tar+gzip` archive, and reports its byte identity for the
C66/C55 invocation.

It does not inspect a Docker daemon, choose images from a build cache, connect
to a Guest, or change the active image-set. C64 alone validates, stages,
loads, and starts the image-set within the Guest.

Example composition:

```json
{
  "schemaVersion": "v1",
  "imageSetId": "bundled-upstream-030",
  "composeFileSourcePath": "/release/bundled-upstream/compose.yaml",
  "imageArchiveSources": [
    {
      "archivePath": "images/vitalserver.tar",
      "sourcePath": "/release/bundled-upstream/images/vitalserver.tar"
    }
  ]
}
```

```sh
guest-bundled-upstream-image-set-archive-composer \
  --composition /release/bundled-upstream/image-set-030.composition.json \
  --output-archive /release/bundled-upstream-030.tar.gz
```
