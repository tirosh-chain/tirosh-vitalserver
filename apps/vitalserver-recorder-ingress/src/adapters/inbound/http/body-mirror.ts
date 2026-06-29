"use strict";

function createBodyMirror(maxBodyBytes, onEnd) {
  const chunks = [];
  let size = 0;
  let truncated = false;

  return {
    push(chunk) {
      size += chunk.length;
      if (size <= maxBodyBytes) {
        chunks.push(chunk);
        return;
      }

      truncated = true;
      const already = chunks.reduce((total, item) => total + item.length, 0);
      const remaining = Math.max(0, maxBodyBytes - already);
      if (remaining > 0) chunks.push(chunk.slice(0, remaining));
    },
    end() {
      onEnd(Buffer.concat(chunks), truncated);
    },
  };
}

module.exports = { createBodyMirror };
