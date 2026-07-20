# Linux KVM/libvirt/systemd external Guest / external VitalServer reference

This profile names a Linux Host that observes and controls an
**externally provisioned** KVM/libvirt Guest. It has no authority to create,
replace, or delete that Guest. The Guest Runtime Control and Recorder Gateway
endpoints (`192.0.2.10`) are deliberately unusable documentation addresses;
the deployment administrator must replace them before operation.

The reference selects UID `0` for the local Unix-socket administration
contract. That is an explicit packaging boundary, not a claim that the
desktop Console is usable by a standard Linux user. A production profile must
name the intended operator UID and prove its socket authorization as part of
C24 clean-Host evidence.

Time and telemetry intentionally report `outcome-unknown`. A clinical
deployment must select reachable NTP and OTLP dependencies (or explicit
unavailable policies); this reference does not invent public defaults.
