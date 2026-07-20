# Guest Product Release Manager

This service owns the Guest Product release lifecycle below the Guest-owned
release root. It is the only component that may stage an immutable release,
atomically retarget `/opt/vitalserver/current`, or roll that link back after a
failed post-restart readiness check.

Its C59 API binds only to the configured Guest loopback address. It accepts a
strict update command plus a streamed `tar.gz` release artifact, verifies the
declared size and SHA-256 while staging, rejects unsafe archive paths and
links, restarts the separately supervised Guest Product systemd unit, and
persists the resulting operation under its declared state directory. The
manager must remain a distinct systemd service: it cannot be a child of the
Guest Product service that it is allowed to restart.

The manager does not own Guest Runtime, Recorder ingress, archive, telemetry,
or Host update state. It preserves their state directories during activation.
The manager exposes its C59 contract on two declared Guest-only transports:
loopback TCP for local health and diagnostics, and an AF_VSOCK listener for
Host delivery. C32 owns the matching Host-loopback-to-AF_VSOCK bridge. This is
not a Guest Runtime route: restarting the Guest Product must not terminate the
release operation that requested that restart, and C59 is never a public
endpoint.
