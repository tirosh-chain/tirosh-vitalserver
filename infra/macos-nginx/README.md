# macOS VitalServer Proxy

macOS container runtime port forwarding can rewrite the client address before
the request reaches the VitalServer container. The host proxy must run outside
Docker so it can capture the VRecorder source IP and forward it to VitalServer
with trusted headers.

## Backend Environment

Use a loopback-only Docker backend and enable proxy trust in VitalServer.

```env
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

For local verification, install nginx with Homebrew and run it with the
repository-managed temporary prefix.

```sh
brew install nginx

VITALSERVER_PROXY_PORT=8080 \
VITALSERVER_HTTP_PORT=18080 \
make proxy-start
```

The local PoC writes the rendered config to `.tmp/macos-nginx/vitalserver.conf`.
It does not install a LaunchDaemon and does not modify the Homebrew service.

Useful commands:

```sh
make proxy-status
make proxy-reload
make proxy-stop
```

Run the Docker backend on loopback while testing the proxy.

```sh
VITALSERVER_BIND_HOST=127.0.0.1 \
VITALSERVER_HTTP_PORT=18080 \
VITALSERVER_TRUST_PROXY=1 \
make up
```

## Render launchd Plist

```sh
make proxy-plist \
  > /Library/LaunchDaemons/com.tirosh.vitalserver-proxy.plist
```

The installer should provide the nginx binary, render both templates, load the
LaunchDaemon, and start Docker Compose with the backend environment above.
