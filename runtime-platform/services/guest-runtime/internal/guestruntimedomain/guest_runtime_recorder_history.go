package guestruntimedomain

type RecorderObservationTimelinePage struct {
	SchemaVersion string               `json:"schemaVersion"`
	RecorderID    string               `json:"recorderId"`
	Items         []CatalogObservation `json:"items"`
	NextCursor    *string              `json:"nextCursor,omitempty"`
}

type RecorderReportedIncident struct {
	SchemaVersion        string            `json:"schemaVersion"`
	ID                   string            `json:"id"`
	RecorderID           string            `json:"recorderId"`
	ObservationReference ResourceReference `json:"observationReference"`
	OccurredAt           string            `json:"occurredAt"`
	ReceivedAt           string            `json:"receivedAt"`
	TimeIssue            *Issue            `json:"timeIssue,omitempty"`
	RuntimeIssue         *Issue            `json:"runtimeIssue,omitempty"`
}

type RecorderIncidentPage struct {
	SchemaVersion string                     `json:"schemaVersion"`
	RecorderID    string                     `json:"recorderId"`
	Items         []RecorderReportedIncident `json:"items"`
	NextCursor    *string                    `json:"nextCursor,omitempty"`
}

func ProjectRecorderReportedIncident(observation CatalogObservation) (RecorderReportedIncident, bool) {
	if observation.Envelope.Time.Issue == nil && observation.Envelope.Runtime.Issue == nil {
		return RecorderReportedIncident{}, false
	}
	return RecorderReportedIncident{
		SchemaVersion: SchemaVersion,
		ID:            observation.ID + "-reported-incident",
		RecorderID:    observation.Envelope.RecorderID,
		ObservationReference: ResourceReference{
			ResourceType: CatalogObservationResourceType,
			ResourceID:   observation.ID,
		},
		OccurredAt:   observation.Envelope.OccurredAt,
		ReceivedAt:   observation.ReceivedAt,
		TimeIssue:    observation.Envelope.Time.Issue,
		RuntimeIssue: observation.Envelope.Runtime.Issue,
	}, true
}
