import { randomUUID } from "crypto";
import { Pool, type PoolClient } from "pg";
import type {
  PreparedRecorderObservabilityLine,
  RecorderObservabilityAdmissionBatch,
  RecorderObservabilityRepositoryPort,
} from "../../../application/ports/outbound/recorder-observability-repository-port";
import {
  evaluateRecorderObservability,
  mergeCurrentProjection,
  summarizeCurrentProjection,
} from "../../../domain/recorder-observability";
import {
  decideRecorderObservabilityExpectation,
  validateRecorderObservabilityExpectationCommand,
  type RecorderObservabilityExpectationCommand,
  type RecorderObservabilityExpectationEvent,
  type RecorderObservabilityExpectationProjection,
} from "../../../domain/recorder-observability-expectation";
import type {
  CurrentProjection,
  ProjectionCandidate,
  RecorderObservabilityResourceType,
} from "../../../domain/recorder-observability";

type AggregateEntry = ProjectionCandidate & {
  associatedProfileRecordId?: string | null;
};
type AggregateDocument = Record<string, any>;

type CurrentRow = {
  vrcode: string;
  document: AggregateDocument;
  device_id: string;
  site_id: string | null;
  boot_id: string | null;
  profile_record_id: string | null;
  health_record_id: string | null;
  boot_record_id: string | null;
  projection_version: number;
  latest_received_at: Date;
};

export function createRecorderObservabilityRepository(config: {
  host: string;
  port: number;
  database: string;
  user: string;
  password: string;
  maxConnections: number;
  freshnessToleranceMultiplier?: number;
  freshnessAllowanceSeconds?: number;
  firstReportGraceSeconds?: number;
  eventId?: () => string;
  now?: () => string;
}): RecorderObservabilityRepositoryPort {
  const pool = new Pool({
    host: config.host,
    port: config.port,
    database: config.database,
    user: config.user,
    password: config.password,
    max: config.maxConnections,
  });
  const freshnessToleranceMultiplier =
    config.freshnessToleranceMultiplier || 3;
  const freshnessAllowanceSeconds = config.freshnessAllowanceSeconds ?? 30;
  const firstReportGraceSeconds = config.firstReportGraceSeconds ?? 300;
  const eventId = config.eventId ?? randomUUID;
  const now = config.now ?? (() => new Date().toISOString());

  return {
    async ping() {
      const result = await pool.query(
        `WITH required(table_name, column_name) AS (
           VALUES
             ('requests', 'request_id'),
             ('requests', 'resource_type'),
             ('requests', 'contract_receipts'),
             ('records', 'record_id'),
             ('records', 'request_id'),
             ('records', 'disposition'),
             ('records', 'document'),
             ('records', 'projection_state'),
             ('current', 'vrcode'),
             ('current', 'document'),
             ('current', 'report_state'),
             ('current', 'latest_received_at'),
             ('expectations', 'vrcode'),
             ('expectations', 'revision'),
             ('expectations', 'lifecycle_state'),
             ('expectations', 'source_event_id'),
             ('expectations', 'support_state'),
             ('expectations', 'source'),
             ('expectation_events', 'event_id'),
             ('expectation_events', 'command_id'),
             ('expectation_events', 'revision')
         )
         SELECT required.table_name, required.column_name
           FROM required
           LEFT JOIN information_schema.columns AS actual
             ON actual.table_schema = 'recorder_observability'
            AND actual.table_name = required.table_name
            AND actual.column_name = required.column_name
          WHERE actual.column_name IS NULL
          ORDER BY required.table_name, required.column_name`,
      );
      if (result.rows.length > 0) {
        const missing = result.rows.map(
          (row) => `${row.table_name}.${row.column_name}`,
        );
        throw new Error(
          `recorder_observability_schema_not_ready:missing=${missing.join(",")}`,
        );
      }
    },
    async admit(batch) {
      return withTransaction(pool, async (client) => admit(client, batch));
    },
    async listPendingProjection(limit) {
      const result = await pool.query(
        `SELECT record_id::text, vrcode, resource_type, document,
                document_device_id, site_id, boot_id, sequence,
                device_observed_at, device_time_state, received_at,
                projection_version
           FROM recorder_observability.records
          WHERE disposition = 'accepted' AND projection_state = 'pending'
          ORDER BY record_id
          LIMIT $1`,
        [limit],
      );
      return result.rows.map(candidateFromRow);
    },
    async readCurrent(vrcode, resourceType) {
      const result = await pool.query(
        `SELECT * FROM recorder_observability.current WHERE vrcode = $1`,
        [vrcode],
      );
      const row = result.rows[0] as CurrentRow | undefined;
      if (resourceType === "bootEvent") return null;
      const entry = (
        resourceType === "recorderProfile"
          ? row?.document?.recorderProfile?.latest
          : row?.document?.[resourceType]
      ) as AggregateEntry | undefined;
      return entry ? currentFromEntry(entry) : null;
    },
    async applyProjection(candidate, replaceCurrent) {
      await withTransaction(pool, async (client) => {
        const locked = await client.query(
          `SELECT * FROM recorder_observability.current
            WHERE vrcode = $1 FOR UPDATE`,
          [candidate.vrcode],
        );
        const row = locked.rows[0] as CurrentRow | undefined;
        let document = { ...(row?.document || {}) };
        if (replaceCurrent) {
          document = mergeCurrentProjection(document, candidate);
          if (candidate.resourceType === "observation") {
            const associated = await loadAssociatedProfile(client, candidate);
            if (associated) {
              document.recorderProfile = {
                ...(document.recorderProfile || {}),
                associated,
              };
            }
          }
          associateProfile(document, candidate);
          await upsertCurrent(client, row, candidate, document);
        }
        await client.query(
          `UPDATE recorder_observability.records
              SET projection_state = $2,
                  projected_at = CURRENT_TIMESTAMP,
                  projection_error = NULL
            WHERE record_id = $1 AND projection_state = 'pending'`,
          [candidate.recordId, replaceCurrent ? "applied" : "ignored"],
        );
      });
    },
    async failProjection(recordId, error) {
      await pool.query(
        `UPDATE recorder_observability.records
            SET projection_state = 'failed',
                projected_at = CURRENT_TIMESTAMP,
                projection_error = $2
          WHERE record_id = $1 AND projection_state = 'pending'`,
        [recordId, error.slice(0, 2048)],
      );
    },
    async applyExpectationCommand(command) {
      return withTransaction(pool, async (client) => {
        await client.query(
          "SELECT pg_advisory_xact_lock(hashtextextended($1, 0))",
          [command.vrcode],
        );
        const currentResult = await client.query(
          `SELECT *
             FROM recorder_observability.expectations
            WHERE vrcode = $1
            FOR UPDATE`,
          [command.vrcode],
        );
        const receivedAt = now();
        const validationFailure =
          validateRecorderObservabilityExpectationCommand(command, receivedAt);
        if (validationFailure) {
          return {
            kind: "rejected",
            currentRevision: currentResult.rows[0]
              ? Number(currentResult.rows[0].revision)
              : 0,
            failure: validationFailure,
          };
        }
        const existingEventResult = await client.query(
          `SELECT *
             FROM recorder_observability.expectation_events
            WHERE command_id = $1`,
          [command.commandId],
        );
        const decision = decideRecorderObservabilityExpectation({
          command,
          current: currentResult.rows[0]
            ? expectationProjectionFromRow(currentResult.rows[0])
            : null,
          existingEvent: existingEventResult.rows[0]
            ? expectationEventFromRow(existingEventResult.rows[0])
            : null,
          eventId: eventId(),
          receivedAt,
        });
        if (decision.kind !== "accepted") return decision;

        await insertExpectationEvent(client, decision.event);
        const saved = await saveExpectationProjection(
          client,
          decision.projection,
          decision.event.previousRevision,
        );
        if (!saved) {
          throw new Error(
            `expectation_projection_cas_failed:vrcode=${command.vrcode}`
              + `:expectedRevision=${decision.event.previousRevision}`,
          );
        }
        return decision;
      });
    },
    async listCurrentRecorders() {
      const result = await pool.query(
        `WITH current_summary AS (
           SELECT vrcode,
                CASE
                  WHEN health_record_id IS NULL THEN 'missing'
                  WHEN profile_record_id IS NULL
                    OR document->'observation'->>'associatedProfileRecordId'
                       IS DISTINCT FROM
                       document->'recorderProfile'->'associated'->>'recordId'
                    THEN 'missing'
                  WHEN jsonb_typeof(
                    document->'recorderProfile'->'associated'->'document'
                      ->'collection'->'observationIntervalSeconds'
                  ) <> 'number'
                    THEN 'readFailed'
                  WHEN (document->'observation'->>'receivedAt')::timestamptz
                       + make_interval(secs =>
                         (
                           document->'recorderProfile'->'associated'->'document'
                             ->'collection'->>'observationIntervalSeconds'
                         )::double precision * $1 + $2
                       ) < CURRENT_TIMESTAMP
                    THEN 'stale'
                  ELSE 'current'
                END AS report_state,
                profile_state, collection_state,
                document->'observation'->>'receivedAt'
                  AS latest_observation_received_at,
                recent_restart_at, active_signal_count,
                document
           FROM recorder_observability.current
        )
        SELECT COALESCE(current_summary.vrcode, expectation.vrcode) AS vrcode,
               current_summary.report_state,
               current_summary.profile_state,
               current_summary.collection_state,
               current_summary.latest_observation_received_at,
               current_summary.recent_restart_at,
               current_summary.active_signal_count,
               current_summary.document,
               expectation.support_state,
               expectation.source,
               expectation.recorder_version,
               expectation.producer_version,
               expectation.protocol_version,
               expectation.catalog_revision,
               expectation.expected_since,
               CURRENT_TIMESTAMP AS evaluated_at
          FROM current_summary
          FULL OUTER JOIN (
            SELECT *
              FROM recorder_observability.expectations
             WHERE lifecycle_state = 'active'
          ) AS expectation
            ON expectation.vrcode = current_summary.vrcode
         ORDER BY vrcode`,
        [freshnessToleranceMultiplier, freshnessAllowanceSeconds],
      );
      return result.rows.map((row) => summaryFromRow(
        row,
        firstReportGraceSeconds,
      ));
    },
    async readRecorderObservability(vrcode) {
      const result = await pool.query(
        `WITH current_summary AS (
           SELECT vrcode,
                CASE
                  WHEN health_record_id IS NULL THEN 'missing'
                  WHEN profile_record_id IS NULL
                    OR document->'observation'->>'associatedProfileRecordId'
                       IS DISTINCT FROM
                       document->'recorderProfile'->'associated'->>'recordId'
                    THEN 'missing'
                  WHEN jsonb_typeof(
                    document->'recorderProfile'->'associated'->'document'
                      ->'collection'->'observationIntervalSeconds'
                  ) <> 'number'
                    THEN 'readFailed'
                  WHEN (document->'observation'->>'receivedAt')::timestamptz
                       + make_interval(secs =>
                         (
                           document->'recorderProfile'->'associated'->'document'
                             ->'collection'->>'observationIntervalSeconds'
                         )::double precision * $2 + $3
                       ) < CURRENT_TIMESTAMP
                    THEN 'stale'
                  ELSE 'current'
                END AS report_state,
                profile_state, collection_state,
                document->'observation'->>'receivedAt'
                  AS latest_observation_received_at,
                recent_restart_at, active_signal_count,
                document
           FROM recorder_observability.current
          WHERE vrcode = $1
        )
        SELECT COALESCE(current_summary.vrcode, expectation.vrcode) AS vrcode,
               current_summary.report_state,
               current_summary.profile_state,
               current_summary.collection_state,
               current_summary.latest_observation_received_at,
               current_summary.recent_restart_at,
               current_summary.active_signal_count,
               current_summary.document,
               expectation.support_state,
               expectation.source,
               expectation.recorder_version,
               expectation.producer_version,
               expectation.protocol_version,
               expectation.catalog_revision,
               expectation.expected_since,
               CURRENT_TIMESTAMP AS evaluated_at
          FROM current_summary
          FULL OUTER JOIN (
            SELECT *
              FROM recorder_observability.expectations
             WHERE vrcode = $1
               AND lifecycle_state = 'active'
          ) AS expectation
            ON expectation.vrcode = current_summary.vrcode`,
        [
          vrcode,
          freshnessToleranceMultiplier,
          freshnessAllowanceSeconds,
        ],
      );
      return result.rows.map((row) => ({
        ...summaryFromRow(row, firstReportGraceSeconds),
        resources: row.document || null,
      }));
    },
    async close() {
      await pool.end();
    },
  };
}

async function admit(
  client: PoolClient,
  batch: RecorderObservabilityAdmissionBatch,
) {
  await client.query(
    `INSERT INTO recorder_observability.requests (
       request_id, resource_type, vrcode, request_device_id, source_ip,
       received_at, line_count, accepted_count, duplicate_count,
       quarantined_count, contract_receipts
     ) VALUES ($1,$2,$3,$4,$5,$6,0,0,0,0,'[]'::jsonb)`,
    [
      batch.requestId,
      batch.resourceType,
      batch.vrcode,
      batch.requestDeviceId,
      batch.sourceIp || null,
      batch.receivedAt,
    ],
  );
  const counts = { accepted: 0, duplicates: 0, quarantined: 0 };
  const receipts = new Set<string>();
  for (const line of batch.lines) {
    if (line.contractReceipt) receipts.add(line.contractReceipt);
    if (line.failureCode) {
      await insertQuarantine(client, batch, line);
      counts.quarantined += 1;
      continue;
    }
    const accepted = await insertAccepted(client, batch, line);
    if (accepted) {
      counts.accepted += 1;
      continue;
    }
    const existing = await client.query(
      `SELECT record_id::text, canonical_sha256
         FROM recorder_observability.records
        WHERE disposition = 'accepted'
          AND vrcode = $1 AND claimed_event_id = $2`,
      [batch.vrcode, line.identity.eventId],
    );
    const existingRow = existing.rows[0];
    if (existingRow?.canonical_sha256 === line.canonicalSha256) {
      await insertDuplicate(client, batch, line, existingRow.record_id);
      counts.duplicates += 1;
    } else {
      await insertQuarantine(
        client,
        batch,
        {
          ...line,
          failureCode: "event_id_content_conflict",
          failureDetail: existingRow
            ? `existingCanonicalSha256=${existingRow.canonical_sha256}`
            : "accepted event disappeared during admission",
        },
      );
      counts.quarantined += 1;
    }
  }
  await client.query(
    `UPDATE recorder_observability.requests
        SET line_count = $2,
            accepted_count = $3,
            duplicate_count = $4,
            quarantined_count = $5,
            contract_receipts = $6::jsonb
      WHERE request_id = $1`,
    [
      batch.requestId,
      batch.lines.length,
      counts.accepted,
      counts.duplicates,
      counts.quarantined,
      JSON.stringify([...receipts].sort()),
    ],
  );
  return counts;
}

async function insertAccepted(
  client: PoolClient,
  batch: RecorderObservabilityAdmissionBatch,
  line: PreparedRecorderObservabilityLine,
): Promise<boolean> {
  const result = await client.query(
    `INSERT INTO recorder_observability.records (
       request_id, line_number, disposition, resource_type, vrcode,
       request_device_id, document_device_id, claimed_event_id,
       schema_version, kind, site_id, boot_id, sequence,
       device_observed_at, device_time_state, raw_sha256, canonical_sha256,
       raw_document, document, failure_code, failure_detail,
       projection_state, received_at
     ) VALUES (
       $1,$2,'accepted',$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,
       $15,$16,NULL,$17::jsonb,NULL,NULL,'pending',$18
     )
     ON CONFLICT (vrcode, claimed_event_id)
       WHERE disposition = 'accepted'
     DO NOTHING
     RETURNING record_id`,
    values(batch, line, JSON.stringify(line.document)),
  );
  return result.rowCount === 1;
}

async function insertDuplicate(
  client: PoolClient,
  batch: RecorderObservabilityAdmissionBatch,
  line: PreparedRecorderObservabilityLine,
  duplicateOfRecordId: string,
) {
  await client.query(
    `INSERT INTO recorder_observability.records (
       request_id, line_number, disposition, resource_type, vrcode,
       request_device_id, document_device_id, claimed_event_id,
       schema_version, kind, site_id, boot_id, sequence,
       device_observed_at, device_time_state, raw_sha256, canonical_sha256,
       raw_document, document, duplicate_of_record_id,
       failure_code, failure_detail, projection_state, received_at
     ) VALUES (
       $1,$2,'duplicate',$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,
       $15,$16,NULL,NULL,$17,NULL,NULL,'not_applicable',$18
     )`,
    [
      ...values(batch, line, null).slice(0, 16),
      duplicateOfRecordId,
      batch.receivedAt,
    ],
  );
}

async function insertQuarantine(
  client: PoolClient,
  batch: RecorderObservabilityAdmissionBatch,
  line: PreparedRecorderObservabilityLine,
) {
  await client.query(
    `INSERT INTO recorder_observability.records (
       request_id, line_number, disposition, resource_type, vrcode,
       request_device_id, document_device_id, claimed_event_id,
       schema_version, kind, site_id, boot_id, sequence,
       device_observed_at, device_time_state, raw_sha256, canonical_sha256,
       raw_document, document, failure_code, failure_detail,
       projection_state, received_at
    ) VALUES (
       $1,$2,'quarantined',$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,
       $15,$16,$17,$18::jsonb,$19,$20,'not_applicable',$21
     )`,
    [
      ...values(batch, line, null).slice(0, 16),
      line.rawDocument,
      JSON.stringify(line.document),
      line.failureCode,
      line.failureDetail,
      batch.receivedAt,
    ],
  );
}

function values(
  batch: RecorderObservabilityAdmissionBatch,
  line: PreparedRecorderObservabilityLine,
  document: string | null,
) {
  return [
    batch.requestId,
    line.lineNumber,
    batch.resourceType,
    batch.vrcode,
    batch.requestDeviceId,
    line.identity.deviceId || null,
    line.identity.eventId || null,
    line.identity.schemaVersion || null,
    line.identity.kind || null,
    line.identity.siteId || null,
    line.identity.bootId || null,
    line.identity.sequence ?? null,
    line.identity.deviceObservedAt || null,
    line.identity.deviceTimeState || null,
    line.rawSha256,
    line.canonicalSha256,
    document,
    batch.receivedAt,
  ];
}

function candidateFromRow(row): ProjectionCandidate {
  return {
    recordId: String(row.record_id),
    vrcode: row.vrcode,
    resourceType: row.resource_type,
    document: row.document,
    deviceId: row.document_device_id,
    siteId: row.site_id,
    bootId: row.boot_id,
    sequence: row.sequence === null ? null : Number(row.sequence),
    deviceObservedAt: iso(row.device_observed_at),
    deviceTimeState: row.device_time_state,
    receivedAt: iso(row.received_at) as string,
    projectionVersion: row.projection_version,
  };
}

function currentFromEntry(entry: AggregateEntry): CurrentProjection {
  return {
    ...entry,
    associatedProfileRecordId: entry.associatedProfileRecordId || null,
  };
}

async function loadAssociatedProfile(
  client: PoolClient,
  health: ProjectionCandidate,
): Promise<AggregateEntry | null> {
  if (!health.bootId) return null;
  const result = await client.query(
    `SELECT record_id::text, vrcode, resource_type, document,
            document_device_id, site_id, boot_id, sequence,
            device_observed_at, device_time_state, received_at,
            projection_version
       FROM recorder_observability.records
      WHERE disposition = 'accepted'
        AND resource_type = 'recorderProfile'
        AND vrcode = $1
        AND document_device_id = $2
        AND boot_id = $3
      ORDER BY sequence DESC NULLS LAST, received_at DESC, record_id DESC
      LIMIT 1`,
    [health.vrcode, health.deviceId, health.bootId],
  );
  return result.rows[0] ? candidateFromRow(result.rows[0]) : null;
}

function associateProfile(
  document: AggregateDocument,
  candidate: ProjectionCandidate,
) {
  const profiles = document.recorderProfile;
  const latest = profiles?.latest as AggregateEntry | undefined;
  const existingAssociated = profiles?.associated as AggregateEntry | undefined;
  const health = document.observation;
  const profile = latest
    && latest.deviceId === health?.deviceId
    && latest.bootId
    && latest.bootId === health?.bootId
    ? latest
    : existingAssociated
      && existingAssociated.deviceId === health?.deviceId
      && existingAssociated.bootId
      && existingAssociated.bootId === health?.bootId
      ? existingAssociated
      : null;
  if (
    (candidate.resourceType === "recorderProfile"
      || candidate.resourceType === "observation")
    && profile
    && health
    && profile.deviceId === health.deviceId
    && profile.bootId
    && profile.bootId === health.bootId
  ) {
    document.recorderProfile = {
      ...(profiles || {}),
      associated: profile,
    };
    document.observation = {
      ...health,
      associatedProfileRecordId: profile.recordId,
    };
  } else if (candidate.resourceType === "observation" && health) {
    document.observation = {
      ...health,
      associatedProfileRecordId: null,
    };
  }
}

async function upsertCurrent(
  client: PoolClient,
  current: CurrentRow | undefined,
  candidate: ProjectionCandidate,
  document: AggregateDocument,
) {
  const health = document.observation as AggregateEntry | undefined;
  const profileLatest = document.recorderProfile?.latest as
    | AggregateEntry
    | undefined;
  const profileAssociated = document.recorderProfile?.associated as
    | AggregateEntry
    | undefined;
  const bootStarted = document.bootEvent?.started as AggregateEntry | undefined;
  const bootShutdown = document.bootEvent?.shutdown as AggregateEntry | undefined;
  const summary = summarizeCurrentProjection(document);
  const aggregateEntries = Object.entries(document)
    .flatMap(([key, value]) => key === "bootEvent"
      ? Object.values(value || {})
      : [value]) as AggregateEntry[];
  const latestReceivedAt = aggregateEntries
    .map((entry) => entry.receivedAt)
    .filter(Boolean)
    .sort()
    .at(-1) || candidate.receivedAt;
  await client.query(
    `INSERT INTO recorder_observability.current (
       vrcode, profile_record_id, health_record_id, boot_record_id,
       projection_version, document, device_id, site_id, boot_id,
       report_state, severity, profile_state, collection_state,
       latest_received_at,
       recent_restart_at, active_signal_count, updated_at
     ) VALUES (
       $1,$2,$3,$4,$5,$6::jsonb,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,
       CURRENT_TIMESTAMP
     )
     ON CONFLICT (vrcode) DO UPDATE SET
       profile_record_id = EXCLUDED.profile_record_id,
       health_record_id = EXCLUDED.health_record_id,
       boot_record_id = EXCLUDED.boot_record_id,
       projection_version = EXCLUDED.projection_version,
       document = EXCLUDED.document,
       device_id = EXCLUDED.device_id,
       site_id = EXCLUDED.site_id,
       boot_id = EXCLUDED.boot_id,
       report_state = EXCLUDED.report_state,
       severity = EXCLUDED.severity,
       profile_state = EXCLUDED.profile_state,
       collection_state = EXCLUDED.collection_state,
       latest_received_at = EXCLUDED.latest_received_at,
       recent_restart_at = EXCLUDED.recent_restart_at,
       active_signal_count = EXCLUDED.active_signal_count,
       updated_at = CURRENT_TIMESTAMP`,
    [
      candidate.vrcode,
      profileLatest?.recordId || current?.profile_record_id || null,
      health?.recordId || current?.health_record_id || null,
      bootStarted?.recordId || current?.boot_record_id || null,
      candidate.projectionVersion,
      JSON.stringify(document),
      health?.deviceId || profileLatest?.deviceId || bootStarted?.deviceId
        || bootShutdown?.deviceId
        || current?.device_id || candidate.deviceId,
      health?.siteId || profileLatest?.siteId || bootStarted?.siteId
        || current?.site_id || candidate.siteId,
      health?.bootId || bootStarted?.bootId || current?.boot_id
        || candidate.bootId,
      summary.reportState,
      summary.severity,
      profileLatest
        ? profileAssociated
          ? "associated"
          : "latest_unassociated"
        : "missing",
      summary.collectionState,
      latestReceivedAt,
      summary.lastBootStartedAt,
      summary.readIssueCount,
    ],
  );
}

async function withTransaction<T>(
  pool: Pool,
  callback: (client: PoolClient) => Promise<T>,
): Promise<T> {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const result = await callback(client);
    await client.query("COMMIT");
    return result;
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

async function insertExpectationEvent(
  client: PoolClient,
  event: RecorderObservabilityExpectationEvent,
): Promise<void> {
  await client.query(
    `INSERT INTO recorder_observability.expectation_events (
       event_id, command_id, vrcode, previous_revision, revision, action,
       support_state, source, recorder_version, producer_version,
       protocol_version, catalog_revision, expected_since, evidence_document,
       decided_at, received_at
     ) VALUES (
       $1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14::jsonb,$15,$16
     )`,
    [
      event.eventId,
      event.commandId,
      event.vrcode,
      event.previousRevision,
      event.revision,
      event.action,
      event.supportState,
      event.source,
      event.recorderVersion,
      event.producerVersion,
      event.protocolVersion,
      event.catalogRevision,
      event.expectedSince,
      JSON.stringify(event.evidenceDocument),
      event.decidedAt,
      event.receivedAt,
    ],
  );
}

async function saveExpectationProjection(
  client: PoolClient,
  projection: RecorderObservabilityExpectationProjection,
  expectedRevision: number,
): Promise<boolean> {
  const result = await client.query(
    `INSERT INTO recorder_observability.expectations (
       vrcode, revision, lifecycle_state, source_event_id, support_state,
       source, recorder_version, producer_version, protocol_version,
       catalog_revision, expected_since, evidence_document, updated_at
     ) VALUES (
       $1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12::jsonb,$13
     )
     ON CONFLICT (vrcode) DO UPDATE SET
       revision = EXCLUDED.revision,
       lifecycle_state = EXCLUDED.lifecycle_state,
       source_event_id = EXCLUDED.source_event_id,
       support_state = EXCLUDED.support_state,
       source = EXCLUDED.source,
       recorder_version = EXCLUDED.recorder_version,
       producer_version = EXCLUDED.producer_version,
       protocol_version = EXCLUDED.protocol_version,
       catalog_revision = EXCLUDED.catalog_revision,
       expected_since = EXCLUDED.expected_since,
       evidence_document = EXCLUDED.evidence_document,
       updated_at = EXCLUDED.updated_at
     WHERE recorder_observability.expectations.revision = $14`,
    [
      projection.vrcode,
      projection.revision,
      projection.lifecycleState,
      projection.sourceEventId,
      projection.supportState,
      projection.source,
      projection.recorderVersion,
      projection.producerVersion,
      projection.protocolVersion,
      projection.catalogRevision,
      projection.expectedSince,
      JSON.stringify(projection.evidenceDocument),
      projection.updatedAt,
      expectedRevision,
    ],
  );
  return result.rowCount === 1;
}

function expectationProjectionFromRow(
  row: Record<string, any>,
): RecorderObservabilityExpectationProjection {
  return {
    vrcode: String(row.vrcode),
    revision: Number(row.revision),
    lifecycleState: row.lifecycle_state,
    sourceEventId: String(row.source_event_id),
    supportState: row.support_state || null,
    source: row.source || null,
    recorderVersion: row.recorder_version || null,
    producerVersion: row.producer_version || null,
    protocolVersion: row.protocol_version || null,
    catalogRevision: row.catalog_revision || null,
    expectedSince: iso(row.expected_since),
    evidenceDocument: row.evidence_document,
    updatedAt: iso(row.updated_at) || "",
  };
}

function expectationEventFromRow(
  row: Record<string, any>,
): RecorderObservabilityExpectationEvent {
  return {
    eventId: String(row.event_id),
    commandId: String(row.command_id),
    vrcode: String(row.vrcode),
    expectedRevision: Number(row.previous_revision),
    previousRevision: Number(row.previous_revision),
    revision: Number(row.revision),
    action: row.action,
    supportState: row.support_state || null,
    source: row.source || null,
    recorderVersion: row.recorder_version || null,
    producerVersion: row.producer_version || null,
    protocolVersion: row.protocol_version || null,
    catalogRevision: row.catalog_revision || null,
    expectedSince: iso(row.expected_since),
    evidenceDocument: row.evidence_document,
    decidedAt: iso(row.decided_at) || "",
    receivedAt: iso(row.received_at) || "",
  };
}

function iso(value: unknown): string | null {
  if (!value) return null;
  return value instanceof Date ? value.toISOString() : String(value);
}

function summaryFromRow(
  row: Record<string, any>,
  firstReportGraceSeconds: number,
) {
  const expectation = row.support_state
    ? {
      supportState: row.support_state,
      source: row.source,
      recorderVersion: row.recorder_version || null,
      producerVersion: row.producer_version || null,
      protocolVersion: row.protocol_version || null,
      catalogRevision: row.catalog_revision || null,
      expectedSince: iso(row.expected_since),
    }
    : null;
  const evaluation = evaluateRecorderObservability({
    currentReportState: row.report_state || null,
    expectation,
    now: iso(row.evaluated_at) || "",
    firstReportGraceSeconds,
  });
  return {
    vrcode: String(row.vrcode),
    ...evaluation,
    profileState: row.profile_state || null,
    collectionState: row.collection_state || null,
    latestObservationReceivedAt: iso(row.latest_observation_received_at),
    lastBootStartedAt: iso(row.recent_restart_at),
    readIssueCount: Number(row.active_signal_count || 0),
    expectedSince: expectation?.expectedSince || null,
    recorderVersion: expectation?.recorderVersion || null,
    producerVersion: expectation?.producerVersion || null,
    protocolVersion: expectation?.protocolVersion || null,
  };
}

module.exports = { createRecorderObservabilityRepository };
