export type AuditFields = Record<string, unknown>;

export type AuditRecorderPort = {
  record(eventType: string, fields: AuditFields): void;
};
