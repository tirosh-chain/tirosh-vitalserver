# macOS Virtualization + bundled VitalServer reference deployment

This is the explicit macOS arm64 reference composition for a Guest-owned
bundled VitalServer/Redis image set:

```text
macOS Host → macOS Virtualization provider → Guest Product → C64 bundled image-set manager
```

The directory owns only Host deployment inputs. Its C32 configuration adds the
dedicated C64 Host-loopback-to-virtio control bridge on port `18445`; C33,
C36, C52 bootstrap, C56 update handoff, and C58 trust-store configuration stay
Host-owned exactly as in the external reference profile.

The matching Guest Product inputs are intentionally named by role rather than
copied here:

- `product/guest-product/guest-product-process-deployment-bundled-vitalserver.v1.json` (C37);
- `product/guest-product/guest-product-bootstrap-configuration-bundled-vitalserver.v1.json` (C39);
- `product/guest-product/guest-product-vitalserver-topology-deployment-bundled.v1.json` (C44); and
- `product/guest-product/guest-bundled-upstream-image-set-manager-configuration.v1.json` (C64).

Those documents deliberately carry no C46 external delivery configuration.
After first boot, C64 owns an explicit `unprovisioned` image-set selection.
An operator or a signed product update must submit one verified image-set
archive through C55 → C66 → C64 before the local VitalServer endpoints can be
observed as available. The profile is therefore package-composition provenance,
not proof that a container started, a credential was provisioned, packets were
accepted, or `.vital` files were indexed.
