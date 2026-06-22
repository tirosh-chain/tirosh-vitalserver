"use strict";

function vitalFileWebPath(filename) {
  if (typeof filename !== "string" || filename.length < 20 || !filename.endsWith(".vital")) {
    return null;
  }

  const bedName = filename.substring(0, filename.length - 20);
  const yymmdd = filename.substring(filename.length - 19, filename.length - 13);
  if (!bedName || !/^\d{6}$/.test(yymmdd)) {
    return null;
  }

  const yyyy = new Date().getFullYear().toString().substring(0, 2) + yymmdd.substring(0, 4);

  return [
    "/vital_files",
    encodeURIComponent(bedName),
    encodeURIComponent(yyyy),
    encodeURIComponent(yymmdd),
    encodeURIComponent(filename),
  ].join("/");
}

module.exports = {
  vitalFileWebPath,
};
