# Product Lab session collection and recorder controls missing

## Metadata

- ID: TS-125
- Category: Product Lab / Runtime Control PWA / macOS Helper UI
- Owner: Product Lab session contract and Runtime Control presentation
- Status: resolved

## Symptom

A scenario session can be created and started from the Lab tab, but refreshing or reopening the screen does not show the running session. Only whole-session Create/Start/Stop controls are visible, so an operator cannot stop or restart one Vital Recorder inside that session.

## Cause

The product boundary exposed create and single-session reads but did not expose a persisted session collection. Clients therefore retained only the session returned by their own command. Recorder state existed in the Lab read model, but no command contract validated and controlled one recorder inside an explicitly running session.

## Fix

- Product Lab owns `GET /lab/sessions` and returns its persisted session collection.
- Guest Control and Runtime Control expose `GET /runtime/lab/sessions` without converting dependency failure into an empty list.
- Recorder Start/Stop routes validate that the session is running and that the recorder explicitly belongs to that session.
- SwiftUI and PWA separate new-session input, persisted Sessions, selected-session control, and selected-session recorder control.
- Windows and Linux Platform Agents forward the same Runtime Control routes; Linux Native does not invent Guest-specific UI state.

## Prevention

- A created resource that must survive refresh needs an owner-provided collection/read contract; client memory is not state ownership.
- Session-to-recorder ownership comes from `recorder.sessionId`, never from a shared prefix or display label.
- Failed, unavailable, empty, stopped, and running session states stay distinct in API and UI tests.
- Cross-platform UI uses `Platform services`, `Runtime product services`, and `Access endpoints`; provider-specific Host/Guest detail remains subordinate to those owner-neutral groups.
