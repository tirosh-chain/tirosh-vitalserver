// Synchronization protects one Recorder Gateway writer process across both
// ingress admission/delivery replay and cold-path capture finalization. It
// does not own domain state; durable facts remain in the
// RecorderGatewayIngressDurableStateStore boundary.
export class RecorderGatewayIngressDurableStateOperationMutex {
  private tail: Promise<void> = Promise.resolve();

  public async runExclusiveRecorderGatewayIngressDurableStateOperation<T>(operation: () => Promise<T>): Promise<T> {
    let release: (() => void) | undefined;
    const current = this.tail;
    this.tail = new Promise<void>((resolve) => {
      release = resolve;
    });
    await current;
    try {
      return await operation();
    } finally {
      release?.();
    }
  }
}
