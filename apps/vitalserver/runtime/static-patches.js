"use strict";

function patchMyFilesScript(source) {
  if (typeof source !== "string") {
    return {
      applied: false,
      source: source,
      reason: "source must be a string",
    };
  }

  const handlerStart = '$("input[type=date]").change(function(e){13!==e.keyCode||';
  const handlerEnd = '}),$("input[type=date]").keypress';
  const startIndex = source.indexOf(handlerStart);
  if (startIndex < 0) {
    return {
      applied: false,
      source: source,
      reason: "date change handler start not found",
    };
  }

  const endIndex = source.indexOf(handlerEnd, startIndex);
  if (endIndex < 0) {
    return {
      applied: false,
      source: source,
      reason: "date change handler end not found",
    };
  }

  return {
    applied: true,
    source:
      source.slice(0, startIndex) +
      '$("input[type=date]").change(function(e){date_onchange(this)' +
      source.slice(endIndex),
    reason: null,
  };
}

module.exports = {
  patchMyFilesScript,
};
