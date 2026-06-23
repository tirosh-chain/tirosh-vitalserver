export type SocketIoAuditContext = Record<string, any>;
export type SocketIoAuditOptions = Record<string, any>;

export type SocketIoAuditPort = {
  inspect(payload: unknown, direction: string, context: SocketIoAuditContext, options?: SocketIoAuditOptions): void;
  inspectBinary(payload: unknown, direction: string, context: SocketIoAuditContext, options?: SocketIoAuditOptions): void;
};
