import type { SendDataContext } from "../../../domain/send-data-spool-types";

export type SocketIoPendingBinaryEvent = {
  event: string;
};

export type SocketIoLastCommand = {
  job?: string;
  target_vrcode?: string;
};

export type SocketIoAuditContext = SendDataContext & {
  pending_binary_event?: SocketIoPendingBinaryEvent | null;
  last_command?: SocketIoLastCommand | null;
  metrics_vrcode?: string | null;
};

export type SocketIoAuditOptions = {
  truncated?: boolean;
};

export type SocketIoAuditPort = {
  inspect(payload: unknown, direction: string, context: SocketIoAuditContext, options?: SocketIoAuditOptions): void;
  inspectBinary(payload: unknown, direction: string, context: SocketIoAuditContext, options?: SocketIoAuditOptions): void;
};
