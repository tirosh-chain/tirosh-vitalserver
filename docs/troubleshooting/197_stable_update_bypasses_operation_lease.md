# TS-197: Stable update bypasses the Host operation lease

## Symptom

A stable bootstrap update can run while another destructive Host operation is
admitted, and the operation status does not identify the stable update owner.

## Cause

The legacy apply workflow acquired the Host-owned SQLite operation lease, while
the new bootstrap workflow only persisted its update journal.

## Fix direction

Acquire the Host operation lease as `apply-update-bootstrap` before update
materialization. Heartbeat it before and after the next-updater handoff, and
release it on both success and failure. A lease release failure remains distinct
from the update result.

## Prevention

Every destructive Host workflow must enter through the same explicit operation
admission boundary. A workflow-specific journal records durable progress; it
does not replace the cross-workflow exclusion lease.
