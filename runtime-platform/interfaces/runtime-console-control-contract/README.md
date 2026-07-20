# Runtime Console control contract

The contract module maps a deliberately small, named set of Runtime Console
requests to the already-published Host Agent facade. It is not a replacement
for `runtime-platform/contracts/` and it does not introduce a Console-owned
domain model.

It preserves three rules in code:

- renderer and desktop IPC cannot request arbitrary paths;
- an operator supplies `requestId`; no interface generates it;
- Host Agent remains the authority that accepts/rejects C9 lifecycle commands.
