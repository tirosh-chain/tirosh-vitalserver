package guestruntimedomain

type RecorderObservabilitySummaryPage struct {
	SchemaVersion string                         `json:"schemaVersion"`
	Items         []RecorderObservabilitySummary `json:"items"`
	NextCursor    *string                        `json:"nextCursor,omitempty"`
}
