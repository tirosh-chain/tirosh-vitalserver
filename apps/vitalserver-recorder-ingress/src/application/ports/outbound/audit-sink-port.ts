export type AuditSinkPort = {
  write(event: unknown): void;
};
