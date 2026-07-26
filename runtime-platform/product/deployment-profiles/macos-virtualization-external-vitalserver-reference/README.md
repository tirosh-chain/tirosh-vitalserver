# macOS Virtualization + external VitalServer reference deployment

This is the explicit reference deployment for a macOS arm64 Host using the
`macos-virtualization` provider, a Guest Product, and an externally owned
VitalServer. Its name is deliberately a complete sentence fragment:

```text
macOS Host → macOS Virtualization provider → Guest Product → external VitalServer
```

It supplies the three Host-side desired documents that must agree before a
macOS package can be assembled:

| Source document | Owner and consumer | Meaning |
| --- | --- | --- |
| `macos-virtual-machine-configuration.v1.json` | deployment author → macOS Virtual Machine Supervisor | Guest boot assets, immutable-to-writable root-disk provisioning, Host-local virtio bridges, storage attachments, and NAT intent |
| `host-agent-deployment-configuration.v1.json` | deployment author → Host Agent | Host Agent control/state paths, selected provider executable/configuration, Guest Runtime control endpoint, and explicitly reported time/telemetry/update modes |
| `host-edge-proxy-deployment-configuration.v1.json` | deployment author → Host Edge Proxy | public Recorder Gateway HTTP/WebSocket listener, route, body bound, timeout, and client-identity replacement policy |
| `operator-interface-bootstrap-configuration.v1.json` | Host installation configuration → packaged Runtime Console launcher | exact C52 descriptor path supplied as an explicit desktop process argument; not C33, an HTTP endpoint, or authorization policy |

The profile composes the shared Guest Product C37/C38/C39/C44 documents and
the reference C46 external VitalServer delivery/observation configuration. It does not
duplicate those documents: Guest-local process, bootstrap, topology, and
external-endpoint responsibilities stay with their respective owners.

`reference` is a release-build boundary, not a hidden default. Its C46 file
uses an `.example` address and is useful only to prove that C41/C35/PKG
composition preserves explicit provenance. It must not be cited as C24
clean-Host, connection, packet-delivery, or clinical-operation evidence. A
real deployment replaces the C46 source through an explicit deployment
declaration whose topology and provider references agree with C44; it must
not overwrite this source or infer a packet, archive, or observation endpoint
from the Host network. The reference's exact HTTP observation path/status
contract exists only to prove C46 provenance; it is not a production health
claim about the `.example` host.

The C35 bootstrap composer strictly decodes the complete current C46 shape
before it permits the Guest bootstrap volume to be made. Packet delivery,
observation, indexed-library archive, credential reference, and timeout
fields are therefore one explicit delivery declaration; none can be omitted,
derived from another endpoint, or silently discarded on the way to the Guest.
The final C40 volume then carries the exact C46 source byte at the C39 declared
destination. This verifies delivery provenance only; it does not read a
credential, contact the external system, or claim that any external capability
is available.
