import type {
  RecorderVitalUploadArchivePublisher,
  RecorderVitalUploadClock,
  RecorderVitalUploadMultipartSource,
  RecorderVitalUploadSpool,
} from "./recorder-gateway-vital-upload-application-ports.js";
import {
  beginRecorderVitalUploadDispatch,
  completeRecorderVitalUploadDispatch,
  type RecorderVitalUploadDispatch,
  type RecorderVitalUploadPublishOutcome,
  type RecorderVitalUploadSourceReceipt,
} from "../recordergatewaydomain/recorder-gateway-vital-upload-contracts.js";
import {
  recorderGatewaySchemaVersion,
  type RecorderGatewayIssue,
} from "../recordergatewaydomain/recorder-gateway-ingress-and-cold-path-contracts.js";

export interface RecorderVitalUploadRequestResult {
  sourceReceipt: RecorderVitalUploadSourceReceipt;
  dispatch: RecorderVitalUploadDispatch;
}

export interface RecorderVitalUploadRecoveryRunResult {
  schemaVersion: typeof recorderGatewaySchemaVersion;
  state: "completed" | "incomplete" | "failed";
  attempted: number;
  completed: number;
  observedAt: string;
  issue?: RecorderGatewayIssue;
}

export class RecorderGatewayVitalUploadApplicationService {
  public constructor(
    private readonly spool: RecorderVitalUploadSpool,
    private readonly archivePublisher: RecorderVitalUploadArchivePublisher,
    private readonly clock: RecorderVitalUploadClock,
  ) {
    if (spool === undefined || archivePublisher === undefined || clock === undefined) {
      throw new TypeError("Recorder Vital upload service dependencies are required");
    }
  }

  public async initializeRecorderVitalUpload(): Promise<void> {
    await this.spool.initializeRecorderVitalUploadSpool();
  }

  public async admitAndDispatchRecorderVitalUpload(
    source: RecorderVitalUploadMultipartSource,
  ): Promise<RecorderVitalUploadRequestResult> {
    const sourceReceipt = await this.spool.admitRecorderVitalUpload(source);
    const dispatch = await this.dispatchRecorderVitalUpload(sourceReceipt.id);
    return { sourceReceipt, dispatch };
  }

  public async dispatchRecorderVitalUpload(
    sourceReceiptId: string,
  ): Promise<RecorderVitalUploadDispatch> {
    const source = await this.spool.readRecorderVitalUploadSourceReceipt(sourceReceiptId);
    const current = await this.spool.readRecorderVitalUploadDispatch(sourceReceiptId);
    if (
      current.state === "archive-admitted"
      || current.state === "quarantined"
      || current.state === "rejected"
    ) {
      return current;
    }
    const dispatching = beginRecorderVitalUploadDispatch(current, this.clock.now());
    await this.spool.commitRecorderVitalUploadDispatch(current.revision, dispatching);
    let outcome: RecorderVitalUploadPublishOutcome;
    try {
      const content = await this.spool.openRecorderVitalUploadContent(sourceReceiptId);
      outcome = await this.archivePublisher.publishRecorderVitalUpload(
        source,
        dispatching.requestId,
        content,
      );
    } catch {
      outcome = {
        state: "unknown",
        issue: {
          code: "archive-source-publish-outcome-unknown",
          message: "Recorder Gateway could not determine the Guest Archive source admission outcome",
          retryable: true,
          dependency: "guest-runtime-archive-source-admission",
        },
      };
    }
    const completed = completeRecorderVitalUploadDispatch(
      dispatching,
      outcome,
      this.clock.now(),
    );
    await this.spool.commitRecorderVitalUploadDispatch(dispatching.revision, completed);
    return completed;
  }

  public async readRecorderVitalUploadDispatch(
    sourceReceiptId: string,
  ): Promise<RecorderVitalUploadDispatch> {
    return this.spool.readRecorderVitalUploadDispatch(sourceReceiptId);
  }

  public async recoverRecorderVitalUploads(
    limit: number,
  ): Promise<RecorderVitalUploadRecoveryRunResult> {
    const observedAt = this.clock.now();
    let recoverable: RecorderVitalUploadDispatch[];
    try {
      recoverable = await this.spool.listRecoverableRecorderVitalUploadDispatches(limit);
    } catch {
      return {
        schemaVersion: recorderGatewaySchemaVersion,
        state: "failed",
        attempted: 0,
        completed: 0,
        observedAt,
        issue: {
          code: "recorder-vital-upload-recovery-read-failed",
          message: "Recorder Gateway could not read durable Vital upload dispatch state",
          retryable: true,
          dependency: "recorder-vital-upload-spool",
        },
      };
    }
    let completed = 0;
    for (const dispatch of recoverable) {
      try {
        const result = await this.dispatchRecorderVitalUpload(dispatch.sourceReceiptId);
        if (
          result.state === "archive-admitted"
          || result.state === "quarantined"
          || result.state === "rejected"
        ) {
          completed += 1;
        }
      } catch {
        return {
          schemaVersion: recorderGatewaySchemaVersion,
          state: "failed",
          attempted: completed + 1,
          completed,
          observedAt: this.clock.now(),
          issue: {
            code: "recorder-vital-upload-recovery-dispatch-failed",
            message: "Recorder Gateway could not commit a recovered Vital upload dispatch outcome",
            retryable: true,
            dependency: "recorder-vital-upload-spool",
          },
        };
      }
    }
    const incomplete = completed !== recoverable.length;
    return {
      schemaVersion: recorderGatewaySchemaVersion,
      state: incomplete ? "incomplete" : "completed",
      attempted: recoverable.length,
      completed,
      observedAt: this.clock.now(),
      issue: incomplete ? {
        code: "recorder-vital-upload-recovery-outcome-unknown",
        message: "one or more Recorder Vital uploads still have an unknown Archive admission outcome",
        retryable: true,
        dependency: "guest-runtime-archive-source-admission",
      } : undefined,
    };
  }
}

export class SystemRecorderVitalUploadClock implements RecorderVitalUploadClock {
  public now(): string {
    return new Date().toISOString();
  }
}
