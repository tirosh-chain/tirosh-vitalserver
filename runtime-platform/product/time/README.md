# Time profiles

`enterprise-ntp.v1.json` is the product declaration used by C18 examples. It names a source identity; it does not discover an operating-system NTP daemon, infer synchronization from a timestamp, or contain an address/credential.

Each Host or Guest deployment must bind that source identity to a node-local,
certified `TimeAuthorityProvider` adapter. If the adapter is not configured,
cannot read its source, returns invalid quality evidence, or has an unknown
effect outcome, the Time Authority reports `unsupported`, `failed`, or retains
the durable running operation as applicable. It never reports `synchronized`
without all required evidence.

The Host now offers a cross-platform `ntp-udp-quality-probe` deployment
adapter. It requires an exact `host:port`, source profile and ID, request
timeout, and maximum offset/uncertainty thresholds. It sends an NTP request
directly and records a measured sample only when the server response and
thresholds are valid. It does not claim to discipline the operating-system
clock; configuring a separate OS time service remains an explicit deployment
responsibility.

The Linux Guest product uses the explicit `chrony-tracking` adapter. In a
production C37/C39 composition, C37 names `ntpServerHost`, `ntpServerPort`,
the absolute `chronyExecutablePath`, and a request timeout; C39 separately
selects the exact `apt`/`chrony`/`chrony.service` first-boot effect and target
configuration path. C40 verifies the generated Chrony configuration as a
named payload, installs Chrony, writes only that configuration, enables and
restarts the declared service, then starts the Guest Product.

`apt-get update` or Chrony installation failure stops Guest cloud-init. It is
not converted into a pre-existing image daemon, an unspecified time source, or
a successful Guest Product start. A release using the checked-in `.example`
source is a provenance reference only; a real deployment must provide its own
C37/C39 input with an operator-approved NTP endpoint before it can be used as
operational evidence.

The adapter invokes `chronyc tracking -n` and only reports `synchronized`
after it reads a normal leap status, stratum, last offset, root dispersion,
and UTC reference time. Malformed output is a typed failed observation and a
non-normal leap status is an unsynchronized observation. The Host needs its
own explicit cross-platform adapter because Host operating-system time-service
ownership differs across macOS, Windows, and Linux.
