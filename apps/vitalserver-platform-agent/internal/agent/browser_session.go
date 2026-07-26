package agent

import (
	"crypto/rand"
	"encoding/base64"
	"fmt"
	"net"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"sync"
	"time"
)

const (
	browserSessionBootstrapPath = "/platform/browser-session"
	browserSessionCookieName    = "vitalserver_platform_session"
	browserSessionLifetime      = 8 * time.Hour
)

// browserSessionController owns only short-lived HTTP authentication state for
// the local PWA. It is deliberately separate from the installed API token:
// browser assets must never contain that long-lived owner secret.
type browserSessionController struct {
	origin string
	now    func() time.Time

	mutation sync.Mutex
	sessions map[string]time.Time
}

func newBrowserSessionController(listenAddress string, now func() time.Time) (*browserSessionController, error) {
	origin, err := loopbackOrigin(listenAddress)
	if err != nil {
		return nil, err
	}
	return &browserSessionController{
		origin:   origin,
		now:      now,
		sessions: map[string]time.Time{},
	}, nil
}

func loopbackOrigin(listenAddress string) (string, error) {
	host, port, err := net.SplitHostPort(listenAddress)
	if err != nil {
		return "", fmt.Errorf("platform agent listenAddress must be host:port: %w", err)
	}
	if host == "" || port == "" {
		return "", fmt.Errorf("platform agent listenAddress must include a host and port: %q", listenAddress)
	}
	portNumber, err := strconv.Atoi(port)
	if err != nil || portNumber < 1 || portNumber > 65535 {
		return "", fmt.Errorf("platform agent listenAddress must use a port between 1 and 65535: %q", listenAddress)
	}
	ip := net.ParseIP(host)
	if ip == nil || !ip.IsLoopback() {
		return "", fmt.Errorf("platform agent listenAddress must use a numeric loopback address: %q", listenAddress)
	}
	return (&url.URL{Scheme: "http", Host: net.JoinHostPort(host, port)}).String(), nil
}

func (c *browserSessionController) issue(request *http.Request) (*http.Cookie, error) {
	if !c.matchesOrigin(request) {
		return nil, errBrowserSessionOrigin
	}
	token, err := randomBrowserSessionToken()
	if err != nil {
		return nil, err
	}
	now := c.now()
	c.mutation.Lock()
	c.removeExpiredLocked(now)
	c.sessions[token] = now.Add(browserSessionLifetime)
	c.mutation.Unlock()
	return &http.Cookie{
		Name:     browserSessionCookieName,
		Value:    token,
		Path:     "/",
		HttpOnly: true,
		SameSite: http.SameSiteStrictMode,
		MaxAge:   int(browserSessionLifetime.Seconds()),
	}, nil
}

func (c *browserSessionController) allows(request *http.Request) bool {
	cookie, err := request.Cookie(browserSessionCookieName)
	if err != nil || cookie.Value == "" {
		return false
	}
	now := c.now()
	c.mutation.Lock()
	deferred, exists := c.sessions[cookie.Value]
	c.removeExpiredLocked(now)
	c.mutation.Unlock()
	if !exists || !deferred.After(now) {
		return false
	}
	return !browserSessionUnsafeMethod(request.Method) || c.matchesOrigin(request)
}

func (c *browserSessionController) matchesOrigin(request *http.Request) bool {
	return canonicalOrigin(request.Header.Get("Origin")) == c.origin
}

func (c *browserSessionController) removeExpiredLocked(now time.Time) {
	for token, expiresAt := range c.sessions {
		if !expiresAt.After(now) {
			delete(c.sessions, token)
		}
	}
}

func browserSessionUnsafeMethod(method string) bool {
	switch method {
	case http.MethodPost, http.MethodPut, http.MethodPatch, http.MethodDelete:
		return true
	default:
		return false
	}
}

func canonicalOrigin(value string) string {
	parsed, err := url.Parse(strings.TrimSpace(value))
	if err != nil || parsed.Scheme != "http" || parsed.Host == "" || parsed.User != nil ||
		parsed.Path != "" || parsed.RawQuery != "" || parsed.Fragment != "" {
		return ""
	}
	return (&url.URL{Scheme: parsed.Scheme, Host: strings.ToLower(parsed.Host)}).String()
}

func randomBrowserSessionToken() (string, error) {
	bytes := make([]byte, 32)
	if _, err := rand.Read(bytes); err != nil {
		return "", fmt.Errorf("local browser session token generation failed: %w", err)
	}
	return base64.RawURLEncoding.EncodeToString(bytes), nil
}

var errBrowserSessionOrigin = fmt.Errorf("request origin does not match the local Platform Agent origin")
