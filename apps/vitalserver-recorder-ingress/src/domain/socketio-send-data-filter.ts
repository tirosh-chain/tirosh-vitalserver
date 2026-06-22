"use strict";

const { clientSocketEvents } = require("./audit-event-contracts");
const { splitEngineIoPayload } = require("./engine-io-payload");

function filterClientSocketIoSendDataPayload(payload) {
  if (!payload || typeof payload !== "string") {
    return { action: "pass", payload, dropBinaryAttachments: 0 };
  }

  const packets = splitEngineIoPayload(payload);
  const kept = [];
  let changed = false;
  let dropBinaryAttachments = 0;

  for (const packet of packets) {
    const sendData = sendDataPacketInfo(packet);
    if (!sendData.isSendData) {
      kept.push(packet);
      continue;
    }

    changed = true;
    dropBinaryAttachments += sendData.binaryAttachmentCount;
  }

  if (!changed) return { action: "pass", payload, dropBinaryAttachments: 0 };
  if (kept.length === 0) return { action: "drop", payload: null, dropBinaryAttachments };
  return {
    action: "replace",
    payload: encodeEngineIoPayload(kept),
    dropBinaryAttachments,
  };
}

function sendDataPacketInfo(packet) {
  const isBinaryEvent = packet.startsWith("45");
  if (!packet.startsWith("42") && !isBinaryEvent) {
    return { isSendData: false, binaryAttachmentCount: 0 };
  }

  const start = packet.indexOf("[");
  if (start < 0) return { isSendData: false, binaryAttachmentCount: 0 };

  let data;
  try {
    data = JSON.parse(packet.slice(start));
  } catch {
    return { isSendData: false, binaryAttachmentCount: 0 };
  }
  if (!Array.isArray(data) || data[0] !== clientSocketEvents.SEND_DATA) {
    return { isSendData: false, binaryAttachmentCount: 0 };
  }

  return {
    isSendData: true,
    binaryAttachmentCount: isBinaryEvent ? binaryAttachmentCount(packet) : 0,
  };
}

function binaryAttachmentCount(packet) {
  const match = /^45(\d*)-/.exec(packet);
  if (!match) return 1;
  const count = Number.parseInt(match[1] || "1", 10);
  return Number.isFinite(count) && count > 0 ? count : 1;
}

function encodeEngineIoPayload(packets) {
  if (packets.length === 1) return packets[0];
  return packets.map((packet) => `${packet.length}:${packet}`).join("");
}

module.exports = {
  filterClientSocketIoSendDataPayload,
  sendDataPacketInfo,
};
