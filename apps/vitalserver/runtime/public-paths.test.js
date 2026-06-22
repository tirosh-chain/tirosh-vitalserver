"use strict";

const assert = require("assert/strict");
const test = require("node:test");

const { vitalFileWebPath } = require("./public-paths");

test("vitalFileWebPath returns a same-origin static path", () => {
  assert.equal(
    vitalFileWebPath("testkit-bedebe2_260617_072042.vital"),
    "/vital_files/testkit-bedebe2/202606/260617/testkit-bedebe2_260617_072042.vital"
  );
});

test("vitalFileWebPath encodes path segments", () => {
  assert.equal(
    vitalFileWebPath("OR A_260617_072042.vital"),
    "/vital_files/OR%20A/202606/260617/OR%20A_260617_072042.vital"
  );
});

test("vitalFileWebPath rejects invalid vital filenames", () => {
  assert.equal(vitalFileWebPath("testkit-bedebe2.vital"), null);
  assert.equal(vitalFileWebPath("testkit-bedebe2_abcdef_072042.vital"), null);
  assert.equal(vitalFileWebPath("testkit-bedebe2_260617_072042.txt"), null);
});
