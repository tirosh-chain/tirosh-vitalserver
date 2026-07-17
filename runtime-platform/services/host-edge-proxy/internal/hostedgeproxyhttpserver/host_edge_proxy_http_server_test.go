package hostedgeproxyhttpserver

import (
	"bufio"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-edge-proxy/internal/hostedgeproxydomain"
)

type proxiedRequest struct {
	Path         string
	Query        string
	Host         string
	Forwarded    string
	ForwardedFor string
	RealIP       string
	ClientIP     string
	Body         string
}

func TestHostEdgeProxyForwardsOnlyConfiguredRouteAndReplacesClientIdentity(t *testing.T) {
	requests := make(chan proxiedRequest, 1)
	upstream := httptest.NewServer(http.HandlerFunc(func(response http.ResponseWriter, request *http.Request) {
		body, _ := io.ReadAll(request.Body)
		requests <- proxiedRequest{
			Path: request.URL.Path, Query: request.URL.RawQuery, Host: request.Host,
			Forwarded: request.Header.Get("Forwarded"), ForwardedFor: request.Header.Get("X-Forwarded-For"),
			RealIP: request.Header.Get("X-Real-IP"), ClientIP: request.Header.Get("X-Client-IP"), Body: string(body),
		}
		response.WriteHeader(http.StatusNoContent)
	}))
	defer upstream.Close()

	handler := newTestHostEdgeProxyHandler(t, "/socket.io/", upstream.URL, 1024, "preserve-client-host")
	proxy := httptest.NewServer(handler)
	defer proxy.Close()
	request, err := http.NewRequest(http.MethodPost, proxy.URL+"/socket.io/?EIO=3", strings.NewReader("packet"))
	if err != nil {
		t.Fatal(err)
	}
	request.Host = "recorder-facing.example.test"
	request.Header.Set("Forwarded", "for=spoofed")
	request.Header.Set("X-Forwarded-For", "spoofed")
	request.Header.Set("X-Real-IP", "spoofed")
	request.Header.Set("X-Client-IP", "spoofed")
	response, err := http.DefaultClient.Do(request)
	if err != nil {
		t.Fatal(err)
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusNoContent {
		t.Fatalf("proxy status = %d", response.StatusCode)
	}
	proxied := <-requests
	if proxied.Path != "/socket.io/" || proxied.Query != "EIO=3" || proxied.Body != "packet" {
		t.Fatalf("proxied request = %#v", proxied)
	}
	if proxied.Host != "recorder-facing.example.test" {
		t.Fatalf("preserved request host = %q", proxied.Host)
	}
	if proxied.ForwardedFor == "spoofed" || proxied.RealIP != proxied.ForwardedFor || proxied.ClientIP != proxied.ForwardedFor || !strings.Contains(proxied.Forwarded, proxied.ForwardedFor) {
		t.Fatalf("client identity boundary = %#v", proxied)
	}
}

func TestHostEdgeProxyReadinessAndUnconfiguredRouteDoNotContactUpstream(t *testing.T) {
	upstream := httptest.NewServer(http.HandlerFunc(func(_ http.ResponseWriter, _ *http.Request) {
		t.Fatal("upstream must not receive readiness or unconfigured route")
	}))
	defer upstream.Close()
	handler := newTestHostEdgeProxyHandler(t, "/socket.io/", upstream.URL, 1024, "target-host")
	proxy := httptest.NewServer(handler)
	defer proxy.Close()

	readiness, err := http.Get(proxy.URL + "/ready")
	if err != nil {
		t.Fatal(err)
	}
	readiness.Body.Close()
	if readiness.StatusCode != http.StatusNoContent {
		t.Fatalf("readiness status = %d", readiness.StatusCode)
	}
	unconfigured, err := http.Get(proxy.URL + "/browser")
	if err != nil {
		t.Fatal(err)
	}
	unconfigured.Body.Close()
	if unconfigured.StatusCode != http.StatusNotFound {
		t.Fatalf("unconfigured route status = %d", unconfigured.StatusCode)
	}
}

func TestHostEdgeProxyRejectsKnownOversizeRequestBeforeUpstream(t *testing.T) {
	upstream := httptest.NewServer(http.HandlerFunc(func(_ http.ResponseWriter, _ *http.Request) {
		t.Fatal("upstream must not receive oversize request")
	}))
	defer upstream.Close()
	handler := newTestHostEdgeProxyHandler(t, "/socket.io/", upstream.URL, 3, "target-host")
	proxy := httptest.NewServer(handler)
	defer proxy.Close()
	response, err := http.Post(proxy.URL+"/socket.io/", "application/octet-stream", strings.NewReader("four"))
	if err != nil {
		t.Fatal(err)
	}
	response.Body.Close()
	if response.StatusCode != http.StatusRequestEntityTooLarge {
		t.Fatalf("oversize status = %d", response.StatusCode)
	}
}

func TestHostEdgeProxyForwardsWebSocketUpgradeThroughConfiguredRoute(t *testing.T) {
	upstreamRequests := make(chan proxiedRequest, 1)
	upstream := httptest.NewServer(http.HandlerFunc(func(response http.ResponseWriter, request *http.Request) {
		if request.Header.Get("Upgrade") != "websocket" {
			http.Error(response, "expected websocket upgrade", http.StatusBadRequest)
			return
		}
		upstreamRequests <- proxiedRequest{Path: request.URL.Path, ForwardedFor: request.Header.Get("X-Forwarded-For"), RealIP: request.Header.Get("X-Real-IP")}
		hijacker, ok := response.(http.Hijacker)
		if !ok {
			http.Error(response, "upstream cannot upgrade", http.StatusInternalServerError)
			return
		}
		connection, writer, err := hijacker.Hijack()
		if err != nil {
			t.Error(err)
			return
		}
		defer connection.Close()
		if _, err := writer.WriteString("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n"); err != nil {
			t.Error(err)
			return
		}
		if err := writer.Flush(); err != nil {
			t.Error(err)
		}
	}))
	defer upstream.Close()
	handler := newTestHostEdgeProxyHandler(t, "/socket.io/", upstream.URL, 1024, "target-host")
	proxy := httptest.NewServer(handler)
	defer proxy.Close()
	proxyURL, err := url.Parse(proxy.URL)
	if err != nil {
		t.Fatal(err)
	}
	connection, err := net.Dial("tcp", proxyURL.Host)
	if err != nil {
		t.Fatal(err)
	}
	defer connection.Close()
	if _, err := fmt.Fprintf(connection, "GET /socket.io/?EIO=3&transport=websocket HTTP/1.1\r\nHost: recorder-facing.example.test\r\nConnection: Upgrade\r\nUpgrade: websocket\r\nX-Forwarded-For: spoofed\r\n\r\n"); err != nil {
		t.Fatal(err)
	}
	response, err := http.ReadResponse(bufio.NewReader(connection), &http.Request{Method: http.MethodGet})
	if err != nil {
		t.Fatal(err)
	}
	response.Body.Close()
	if response.StatusCode != http.StatusSwitchingProtocols {
		t.Fatalf("websocket upgrade status = %d", response.StatusCode)
	}
	upstreamRequest := <-upstreamRequests
	if upstreamRequest.Path != "/socket.io/" || upstreamRequest.ForwardedFor == "spoofed" || upstreamRequest.ForwardedFor != upstreamRequest.RealIP {
		t.Fatalf("upstream websocket request = %#v", upstreamRequest)
	}
}

func newTestHostEdgeProxyHandler(t *testing.T, routePrefix string, upstreamURL string, maximumRequestBodyBytes int64, requestHostHeaderPolicy string) http.Handler {
	t.Helper()
	target, err := url.Parse(upstreamURL)
	if err != nil {
		t.Fatal(err)
	}
	host, portText, err := net.SplitHostPort(target.Host)
	if err != nil {
		t.Fatal(err)
	}
	port, err := net.LookupPort("tcp", portText)
	if err != nil {
		t.Fatal(err)
	}
	handler, err := NewHostEdgeProxyHTTPHandler(hostedgeproxydomain.HostEdgeProxyDeploymentConfiguration{
		SchemaVersion: hostedgeproxydomain.HostEdgeProxyDeploymentConfigurationSchemaVersion, ProxyID: "test-edge", Listener: hostedgeproxydomain.HostEdgeProxyListener{Protocol: "http", BindHost: "127.0.0.1", Port: 8088},
		ReadinessPath: "/ready", ClientIdentityHeaderPolicy: "replace-with-remote-address",
		Routes: []hostedgeproxydomain.HostEdgeProxyRoute{{
			ID: "configured-route", RequestPathPrefix: routePrefix, Target: hostedgeproxydomain.HostEdgeProxyHTTPUpstream{Scheme: target.Scheme, Host: host, Port: port},
			ForwardingProtocol: "http-and-websocket", RequestHostHeaderPolicy: requestHostHeaderPolicy, MaximumRequestBodyBytes: maximumRequestBodyBytes, UpstreamResponseHeaderTimeoutMilliseconds: 1000,
		}},
	})
	if err != nil {
		t.Fatal(err)
	}
	return handler
}
