# Host Service Runner

`host-service-runner` is the narrow process adapter that makes one explicit
Host executable consumable by an operating-system service manager. It owns
neither C48 installation state nor Host/Guest business state.

The runner receives one absolute `--service-definition` path. That JSON file
is an immutable C48-declared service-definition payload and names exactly one
role, service name, executable path, and argument array. The runner rejects
unknown fields, symbolic files, relative command paths, recursive use of
itself, and malformed arguments. It never searches a release directory,
derives a command from the service name, invokes a shell, retries a failed
child, or changes SCM/systemd/launchd registration.

On Windows the runner enters the exact named SCM service and maps Stop/Shutdown
to cancellation of that one child process. C50 owns SCM registration and C54
owns removal. On macOS/Linux the same adapter simply runs the declared child
until the OS service manager sends a terminating signal.
