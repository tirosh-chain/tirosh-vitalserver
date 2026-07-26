// Package vitalserverindexedlibrary adapts the documented VitalServer .vital
// library protocol to Archive Export. It owns HTTP exchange only: Archive
// Export retains manifest and operation state, and the caller owns selection
// and secure delivery of this adapter's explicit configuration.
package vitalserverindexedlibrary

import (
	"bytes"
	"compress/gzip"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
	"net/url"
	"strings"
	"time"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimeapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

const maximumVitalServerLibraryResponseBytes int64 = 4 << 20

// VitalServerIndexedLibraryCredentials are supplied only to this outbound
// adapter. They must come from a secret owner; callers must never persist or
// return them in a public contract.
type VitalServerIndexedLibraryCredentials struct {
	UserID   string
	Password string
}

// VitalServerIndexedLibraryHTTPArchiveExportProviderConfiguration is one
// explicit VitalServer indexed-library target. The endpoint is a base origin,
// not a discovery URL and not a source for topology inference.
type VitalServerIndexedLibraryHTTPArchiveExportProviderConfiguration struct {
	Reference      guestruntimedomain.ArchiveProviderReference
	Endpoint       string
	Credentials    VitalServerIndexedLibraryCredentials
	RequestTimeout time.Duration
}

// VitalServerIndexedLibraryHTTPArchiveExportProvider sends a formed .vital
// object to VitalServer's upload endpoint, then separately proves the owner
// indexed its deterministic filename. A transport error is intentionally
// returned as an error because the effect outcome is unknown; an HTTP result
// is returned as a known succeeded or failed ExportStep.
type VitalServerIndexedLibraryHTTPArchiveExportProvider struct {
	reference   guestruntimedomain.ArchiveProviderReference
	endpoint    *url.URL
	credentials VitalServerIndexedLibraryCredentials
	client      *http.Client
}

func NewVitalServerIndexedLibraryHTTPArchiveExportProvider(configuration VitalServerIndexedLibraryHTTPArchiveExportProviderConfiguration) (*VitalServerIndexedLibraryHTTPArchiveExportProvider, error) {
	if !guestruntimedomain.ValidIdentifier(configuration.Reference.Kind) || !guestruntimedomain.ValidIdentifier(configuration.Reference.ID) || configuration.Reference.CapabilityRevision < 1 {
		return nil, fmt.Errorf("VitalServer indexed-library Archive provider reference must be explicit and valid")
	}
	if configuration.Credentials.UserID == "" || configuration.Credentials.Password == "" {
		return nil, fmt.Errorf("VitalServer indexed-library credentials must be supplied explicitly")
	}
	if configuration.RequestTimeout <= 0 {
		return nil, fmt.Errorf("VitalServer indexed-library request timeout must be positive")
	}
	endpoint, err := parseVitalServerIndexedLibraryEndpoint(configuration.Endpoint)
	if err != nil {
		return nil, err
	}
	transport := http.DefaultTransport.(*http.Transport).Clone()
	// C46 supplies the complete upstream origin. Inheriting HTTP_PROXY would
	// silently select a Host/Guest environment route outside that contract.
	transport.Proxy = nil
	return &VitalServerIndexedLibraryHTTPArchiveExportProvider{
		reference:   configuration.Reference,
		endpoint:    endpoint,
		credentials: configuration.Credentials,
		client: &http.Client{
			Timeout:   configuration.RequestTimeout,
			Transport: transport,
			CheckRedirect: func(*http.Request, []*http.Request) error {
				return fmt.Errorf("VitalServer indexed-library redirects are not allowed")
			},
		},
	}, nil
}

func (provider *VitalServerIndexedLibraryHTTPArchiveExportProvider) ArchiveExportProviderReference() guestruntimedomain.ArchiveProviderReference {
	return provider.reference
}

func (provider *VitalServerIndexedLibraryHTTPArchiveExportProvider) UploadArtifactExportPayload(ctx context.Context, manifest guestruntimedomain.ArtifactManifest, payload []byte, completedAt string) (guestruntimedomain.ExportStep, error) {
	if err := validateVitalArtifactPayload(manifest, payload); err != nil {
		return guestruntimedomain.ExportStep{}, err
	}
	requestBody, contentType, writeCompleted := vitalArtifactMultipartStream(manifest.Artifact.ArtifactID+".vital", payload)
	response, err := provider.request(ctx, http.MethodPost, "/upload", contentType, requestBody)
	if err != nil {
		_ = requestBody.Close()
		<-writeCompleted
		return guestruntimedomain.ExportStep{}, err
	}
	if writeError := <-writeCompleted; writeError != nil {
		_ = response.Body.Close()
		return guestruntimedomain.ExportStep{}, fmt.Errorf("VitalServer indexed-library upload outcome is unknown")
	}
	body, err := readBoundedResponseBody(response.Body)
	if err != nil {
		return guestruntimedomain.ExportStep{}, err
	}
	if response.StatusCode < http.StatusOK || response.StatusCode >= http.StatusMultipleChoices || strings.TrimSpace(string(body)) != "success" {
		retryable := retryableVitalServerStatus(response.StatusCode)
		return guestruntimedomain.FailedExportStep(completedAt, guestruntimedomain.Issue{
			Code:       "vitalserver-indexed-library-upload-rejected",
			Message:    "VitalServer did not accept the .vital archive upload",
			Retryable:  &retryable,
			Dependency: provider.reference.ID,
		}), nil
	}
	return guestruntimedomain.SucceededExportStep(vitalServerUploadReceiptID(manifest), completedAt), nil
}

func (provider *VitalServerIndexedLibraryHTTPArchiveExportProvider) VerifyUploadedArtifactIndex(ctx context.Context, manifest guestruntimedomain.ArtifactManifest, upload guestruntimedomain.ExportStep, completedAt string) (guestruntimedomain.ExportStep, error) {
	if provider == nil || provider.endpoint == nil || provider.client == nil {
		return guestruntimedomain.ExportStep{}, fmt.Errorf("VitalServer indexed-library Archive provider is not configured")
	}
	if !validVitalArtifactManifestIdentity(manifest) {
		return guestruntimedomain.ExportStep{}, fmt.Errorf("VitalServer index verification requires one valid .vital artifact manifest")
	}
	if upload.State != "succeeded" || upload.ReceiptID != vitalServerUploadReceiptID(manifest) {
		return guestruntimedomain.ExportStep{}, fmt.Errorf("VitalServer index verification requires this provider's succeeded upload receipt")
	}
	token, loginStep, err := provider.login(ctx, completedAt)
	if err != nil || loginStep != nil {
		if loginStep != nil {
			return *loginStep, nil
		}
		return guestruntimedomain.ExportStep{}, err
	}
	indexed, listStep, err := provider.listIndexedFileNames(ctx, token, completedAt)
	if err != nil || listStep != nil {
		if listStep != nil {
			return *listStep, nil
		}
		return guestruntimedomain.ExportStep{}, err
	}
	if !indexed[manifest.Artifact.ArtifactID+".vital"] {
		retryable := true
		return guestruntimedomain.FailedExportStep(completedAt, guestruntimedomain.Issue{
			Code:       "vitalserver-indexed-library-artifact-not-indexed",
			Message:    "VitalServer accepted the .vital upload but has not indexed the artifact",
			Retryable:  &retryable,
			Dependency: provider.reference.ID,
		}), nil
	}
	return guestruntimedomain.SucceededExportStep(vitalServerIndexReceiptID(manifest), completedAt), nil
}

func (provider *VitalServerIndexedLibraryHTTPArchiveExportProvider) login(ctx context.Context, completedAt string) (string, *guestruntimedomain.ExportStep, error) {
	form := url.Values{"id": {provider.credentials.UserID}, "pw": {provider.credentials.Password}}
	response, err := provider.request(ctx, http.MethodPost, "/api/login", "application/x-www-form-urlencoded", strings.NewReader(form.Encode()))
	if err != nil {
		return "", nil, err
	}
	body, err := readBoundedResponseBody(response.Body)
	if err != nil {
		return "", nil, err
	}
	if response.StatusCode != http.StatusOK {
		retryable := retryableVitalServerStatus(response.StatusCode)
		step := guestruntimedomain.FailedExportStep(completedAt, guestruntimedomain.Issue{
			Code:       "vitalserver-indexed-library-authentication-failed",
			Message:    "VitalServer indexed-library authentication was not accepted",
			Retryable:  &retryable,
			Dependency: provider.reference.ID,
		})
		return "", &step, nil
	}
	var document struct {
		Succeeded   bool   `json:"res"`
		AccessToken string `json:"access_token"`
	}
	if err := decodeOneJSONDocument(body, &document); err != nil || !document.Succeeded || document.AccessToken == "" {
		retryable := false
		step := guestruntimedomain.FailedExportStep(completedAt, guestruntimedomain.Issue{
			Code:       "vitalserver-indexed-library-authentication-response-invalid",
			Message:    "VitalServer indexed-library authentication response is invalid",
			Retryable:  &retryable,
			Dependency: provider.reference.ID,
		})
		return "", &step, nil
	}
	return document.AccessToken, nil, nil
}

func (provider *VitalServerIndexedLibraryHTTPArchiveExportProvider) listIndexedFileNames(ctx context.Context, token string, completedAt string) (map[string]bool, *guestruntimedomain.ExportStep, error) {
	query := url.Values{"access_token": {token}, "unixtimestamp": {"1"}}
	response, err := provider.request(ctx, http.MethodGet, "/api/filelist?"+query.Encode(), "", nil)
	if err != nil {
		return nil, nil, err
	}
	body, err := readBoundedResponseBody(response.Body)
	if err != nil {
		return nil, nil, err
	}
	if response.StatusCode == http.StatusNotFound && isVitalServerEmptyFileList(body) {
		return map[string]bool{}, nil, nil
	}
	if response.StatusCode != http.StatusOK {
		retryable := retryableVitalServerStatus(response.StatusCode)
		step := guestruntimedomain.FailedExportStep(completedAt, guestruntimedomain.Issue{
			Code:       "vitalserver-indexed-library-index-read-failed",
			Message:    "VitalServer indexed-library index read was not accepted",
			Retryable:  &retryable,
			Dependency: provider.reference.ID,
		})
		return nil, &step, nil
	}
	reader, err := gzip.NewReader(bytes.NewReader(body))
	if err != nil {
		return nil, invalidVitalServerIndexStep(provider.reference.ID, completedAt), nil
	}
	decoded, readError := io.ReadAll(io.LimitReader(reader, maximumVitalServerLibraryResponseBytes+1))
	closeError := reader.Close()
	if readError != nil || closeError != nil || int64(len(decoded)) > maximumVitalServerLibraryResponseBytes {
		return nil, invalidVitalServerIndexStep(provider.reference.ID, completedAt), nil
	}
	var entries []struct {
		FileName string `json:"filename"`
	}
	if err := decodeOneJSONDocument(decoded, &entries); err != nil {
		return nil, invalidVitalServerIndexStep(provider.reference.ID, completedAt), nil
	}
	indexed := make(map[string]bool, len(entries))
	for _, entry := range entries {
		if entry.FileName == "" {
			return nil, invalidVitalServerIndexStep(provider.reference.ID, completedAt), nil
		}
		indexed[entry.FileName] = true
	}
	return indexed, nil, nil
}

func (provider *VitalServerIndexedLibraryHTTPArchiveExportProvider) request(ctx context.Context, method string, path string, contentType string, body io.Reader) (*http.Response, error) {
	if provider == nil || provider.endpoint == nil || provider.client == nil {
		return nil, fmt.Errorf("VitalServer indexed-library Archive provider is not configured")
	}
	target := *provider.endpoint
	pathAndQuery, err := url.Parse(path)
	if err != nil || pathAndQuery.IsAbs() || pathAndQuery.Host != "" {
		return nil, fmt.Errorf("VitalServer indexed-library request path is invalid")
	}
	target.Path = pathAndQuery.Path
	target.RawQuery = pathAndQuery.RawQuery
	request, err := http.NewRequestWithContext(ctx, method, target.String(), body)
	if err != nil {
		return nil, fmt.Errorf("construct VitalServer indexed-library request: %w", err)
	}
	if contentType != "" {
		request.Header.Set("Content-Type", contentType)
	}
	response, err := provider.client.Do(request)
	if err != nil {
		return nil, fmt.Errorf("VitalServer indexed-library request outcome is unknown")
	}
	return response, nil
}

func parseVitalServerIndexedLibraryEndpoint(value string) (*url.URL, error) {
	endpoint, err := url.Parse(value)
	if err != nil {
		return nil, fmt.Errorf("VitalServer indexed-library endpoint is invalid")
	}
	if (endpoint.Scheme != "http" && endpoint.Scheme != "https") || endpoint.Host == "" || endpoint.User != nil || endpoint.RawQuery != "" || endpoint.Fragment != "" || (endpoint.Path != "" && endpoint.Path != "/") {
		return nil, fmt.Errorf("VitalServer indexed-library endpoint must be an explicit http or https origin")
	}
	endpoint.Path = ""
	return endpoint, nil
}

func validateVitalArtifactPayload(manifest guestruntimedomain.ArtifactManifest, payload []byte) error {
	if !validVitalArtifactManifestIdentity(manifest) || manifest.Artifact.ByteSize != len(payload) || len(payload) == 0 {
		return fmt.Errorf("VitalServer indexed-library upload requires one complete .vital artifact manifest and payload")
	}
	digest := sha256.Sum256(payload)
	if manifest.Artifact.Digest != hex.EncodeToString(digest[:]) {
		return fmt.Errorf("VitalServer indexed-library upload payload does not match its artifact digest")
	}
	return nil
}

func validVitalArtifactManifestIdentity(manifest guestruntimedomain.ArtifactManifest) bool {
	return guestruntimedomain.ValidIdentifier(manifest.Artifact.ArtifactID) && manifest.Artifact.MediaType == "application/x-vital" && len(manifest.Artifact.Digest) == sha256.Size*2
}

func vitalArtifactMultipartStream(filename string, payload []byte) (*io.PipeReader, string, <-chan error) {
	reader, writer := io.Pipe()
	multipartWriter := multipart.NewWriter(writer)
	completed := make(chan error, 1)
	go func() {
		part, err := multipartWriter.CreateFormFile("vitalfile", filename)
		if err == nil {
			_, err = part.Write(payload)
		}
		if closeError := multipartWriter.Close(); err == nil {
			err = closeError
		}
		if err != nil {
			_ = writer.CloseWithError(err)
		} else {
			_ = writer.Close()
		}
		completed <- err
	}()
	return reader, multipartWriter.FormDataContentType(), completed
}

func readBoundedResponseBody(body io.ReadCloser) ([]byte, error) {
	defer body.Close()
	result, err := io.ReadAll(io.LimitReader(body, maximumVitalServerLibraryResponseBytes+1))
	if err != nil || int64(len(result)) > maximumVitalServerLibraryResponseBytes {
		return nil, fmt.Errorf("VitalServer indexed-library response outcome is unknown")
	}
	return result, nil
}

func decodeOneJSONDocument(source []byte, target any) error {
	decoder := json.NewDecoder(bytes.NewReader(source))
	if err := decoder.Decode(target); err != nil {
		return err
	}
	if err := decoder.Decode(&struct{}{}); err != io.EOF {
		return fmt.Errorf("trailing JSON value")
	}
	return nil
}

func isVitalServerEmptyFileList(body []byte) bool {
	var document struct {
		Message string `json:"message"`
	}
	return decodeOneJSONDocument(body, &document) == nil && document.Message == "No result found"
}

func invalidVitalServerIndexStep(providerID string, completedAt string) *guestruntimedomain.ExportStep {
	retryable := false
	step := guestruntimedomain.FailedExportStep(completedAt, guestruntimedomain.Issue{
		Code:       "vitalserver-indexed-library-index-response-invalid",
		Message:    "VitalServer indexed-library index response is invalid",
		Retryable:  &retryable,
		Dependency: providerID,
	})
	return &step
}

func retryableVitalServerStatus(status int) bool {
	return status == http.StatusRequestTimeout || status == http.StatusTooManyRequests || status >= http.StatusInternalServerError
}

func vitalServerUploadReceiptID(manifest guestruntimedomain.ArtifactManifest) string {
	return "vitalserver-upload-" + vitalServerArtifactReceiptSuffix(manifest)
}

func vitalServerIndexReceiptID(manifest guestruntimedomain.ArtifactManifest) string {
	return "vitalserver-index-" + vitalServerArtifactReceiptSuffix(manifest)
}

func vitalServerArtifactReceiptSuffix(manifest guestruntimedomain.ArtifactManifest) string {
	digest := sha256.Sum256([]byte(manifest.Artifact.ArtifactID + "\x00" + manifest.Artifact.Digest))
	return hex.EncodeToString(digest[:16])
}

var _ guestruntimeapplication.GuestRuntimeArchiveExportProvider = (*VitalServerIndexedLibraryHTTPArchiveExportProvider)(nil)
