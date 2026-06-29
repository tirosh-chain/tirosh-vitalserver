"use strict";

const auditEventTypes = Object.freeze({
  JOIN_VR: "join_vr",
  SEND_DATA: "send_data",
  REQ_CMD: "req_cmd",
  COMMAND_DISPATCH: "command_dispatch",
  PROXY_ERROR: "proxy_error",
});

const clientSocketEvents = Object.freeze({
  JOIN_VR: "join_vr",
  SEND_DATA: "send_data",
  REQ_CMD: "req_cmd",
});

const serverDispatchEvents = Object.freeze({
  UPDATE: "update",
  DEL_BED: "del_bed",
  RESTART: "restart",
  REBOOT: "reboot",
  ADD_EVENT: "add_event",
  EDIT_BED: "edit_bed",
  EDIT_CONF: "edit_conf",
});

const serverDispatchEventNames = Object.freeze(Object.values(serverDispatchEvents));

/**
 * @typedef {Object} AuditEnvelope
 * @property {1} schema_version
 * @property {"vitalserver-recorder-ingress"} source
 * @property {string} event_type
 * @property {string} ts ISO-8601 timestamp.
 * @property {number} ts_unix_ms Unix timestamp in milliseconds.
 */

/**
 * @typedef {Object} SelectedIpInfo
 * @property {string} selected_ip IP chosen for VRecorder identity.
 * @property {"x-forwarded-for"|"x-real-ip"|"forwarded"|"x-client-ip"|"remote-address"} selected_source
 * @property {string} remote_address TCP peer observed by the proxy.
 * @property {boolean} trust_proxy Whether forwarding headers were trusted.
 */

/**
 * Emitted when VRecorder sends Socket.IO join_vr.
 *
 * @typedef {Object} JoinVrAuditEvent
 * @property {"join_vr"} event_type
 * @property {string} request_id
 * @property {string} connection_id
 * @property {string} vrcode
 * @property {boolean} truncated
 * @property {string} selected_ip
 * @property {string} selected_source
 * @property {string} remote_address
 * @property {boolean} trust_proxy
 */

/**
 * Emitted when VRecorder sends Socket.IO send_data.
 *
 * @typedef {Object} SendDataAuditEvent
 * @property {"send_data"} event_type
 * @property {string} request_id
 * @property {string} connection_id
 * @property {string|undefined} vrcode
 * @property {boolean} truncated
 * @property {SendDataPayloadSummary} payload_summary
 */

/**
 * @typedef {Object} SendDataPayloadSummary
 * @property {"string"|string} payload_type
 * @property {number|undefined} bytes
 * @property {string|undefined} vrcode
 * @property {string|number|undefined} version
 * @property {number|undefined} rooms_count
 * @property {string|undefined} decode_error
 */

/**
 * Emitted when Web Monitoring UI sends Socket.IO req_cmd.
 *
 * @typedef {Object} ReqCmdAuditEvent
 * @property {"req_cmd"} event_type
 * @property {string} request_id
 * @property {string} connection_id
 * @property {string|undefined} command_job
 * @property {string|undefined} target_vrcode
 * @property {boolean} truncated
 * @property {Object|string} payload
 */

/**
 * Emitted when VitalServer emits a command event to a VRecorder socket/room.
 *
 * @typedef {Object} CommandDispatchAuditEvent
 * @property {"command_dispatch"} event_type
 * @property {string} request_id
 * @property {string} connection_id
 * @property {string|undefined} target_vrcode
 * @property {string|undefined} command_job
 * @property {string} dispatch_event
 * @property {boolean} truncated
 * @property {unknown} payload
 */

module.exports = {
  auditEventTypes,
  clientSocketEvents,
  serverDispatchEvents,
  serverDispatchEventNames,
};
