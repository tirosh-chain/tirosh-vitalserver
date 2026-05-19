# macOS VitalServer Proxy

macOS container runtime port forwarding can rewrite the client address before
the request reaches the VitalServer container. The host proxy must run outside
Docker so it can capture the VRecorder source IP and forward it to VitalServer
with trusted headers.

## Backend Environment

Use a loopback-only Docker backend and enable proxy trust in VitalServer.

```env
VITALSERVER_PROXY_PORT=80
VITALSERVER_BIND_HOST=127.0.0.1
VITALSERVER_HTTP_PORT=18080
VITALSERVER_TRUST_PROXY=1
VITALSERVER_PUBLIC_HOST=
VITALSERVER_PUBLIC_PORT=
```

External VRecorder devices and browsers should connect to the macOS host proxy,
not to the Docker backend port.

## Render nginx Config

```sh
VITALSERVER_PROXY_PORT=80 VITALSERVER_HTTP_PORT=18080 make proxy-config \
  > /Library/Application\ Support/TiroshVitalServer/nginx/vitalserver.conf
```

The generated config overwrites client-supplied forwarding headers with
nginx's `$remote_addr` at the macOS host trust boundary.

## Local PoC with Homebrew nginx

For local verification, install nginx with Homebrew and run the normal stack.
`make up` starts Docker Compose with a loopback-only backend and starts the
host nginx proxy with the repository-managed temporary prefix.

```sh
brew install nginx

make up
make proxy-status
make down
```

The default proxy port is 80, so nginx may ask for administrator privileges.
The local PoC writes the rendered config to `.tmp/macos-nginx/vitalserver.conf`.
It does not install a LaunchDaemon and does not modify the Homebrew service.

The proxy targets are still useful when you want to inspect or restart only the
nginx edge:

```sh
make proxy-start
make proxy-status
make proxy-reload
make proxy-stop
```

## Render launchd Plist

```sh
make proxy-plist \
  > /Library/LaunchDaemons/com.tirosh.vitalserver-proxy.plist
```

The installer should provide the nginx binary, render both templates, load the
LaunchDaemon, and start Docker Compose with the backend environment above.
