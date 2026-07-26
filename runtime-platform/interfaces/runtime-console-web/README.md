# Runtime Console web renderer

This React bundle renders owner-supplied JSON documents and offers named Host,
Guest lifecycle, Lab, manual Archive Export, topology, time, telemetry, and
update requests. It has no direct HTTP client: `window` receives only the
`RuntimeConsoleControlTransport` bridge provided by a host shell.

Manual Archive Export is available only when the latest Guest recorder read
identifies a stopped `no-export` virtual recorder with its finalization
receipt, and the Archive owner separately publishes its provider reference.
The renderer forwards those exact facts; it does not derive an export source
or provider from a recorder name, URL, file path, or secret.

The renderer's content-security policy sets `connect-src 'none'`. Browser/PWA
delivery can be added only when an explicitly authenticated Host access
transport exists; it must not change this renderer into a Host filesystem or
process client.
