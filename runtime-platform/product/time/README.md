# Time profiles

`enterprise-ntp.v1.json` is the product declaration used by C18 examples. It names a source identity; it does not discover an operating-system NTP daemon, infer synchronization from a timestamp, or contain an address/credential.

Each Host or Guest deployment must bind that source identity to a node-local, certified `TimeAuthorityProvider` adapter. If the adapter is not configured, cannot read its source, returns invalid quality evidence, or has an unknown effect outcome, the Time Authority reports `unsupported`, `failed`, or retains the durable running operation as applicable. It never reports `synchronized` without all required evidence.
