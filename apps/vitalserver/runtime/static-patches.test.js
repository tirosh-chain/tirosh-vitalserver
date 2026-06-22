"use strict";

const assert = require("assert/strict");
const test = require("node:test");

const { patchMyFilesScript } = require("./static-patches");

test("patchMyFilesScript reloads My Files when a date picker value changes", () => {
  const source = [
    'before;$("input[type=date]").change(function(e){13!==e.keyCode||',
    '$(this).val().startsWith("0")||',
    '("sdate"==this.id&&new Date($(this).val()).getTime()<=new Date($("#edate").val()).getTime()||',
    '"edate"==this.id&&new Date($("#sdate").val()).getTime()<=new Date($(this).val()).getTime())',
    "&&request_data();e=+$(this).val().substring(0,4);",
    '"sdate"==this.id&&new Date($(this).val()).getTime()>new Date($("#edate").val()).getTime()',
    '&&2e3<e&&$("#edate").val($("#sdate").val()),',
    '"edate"==this.id&&new Date($(this).val()).getTime()<new Date($("#sdate").val()).getTime()',
    '&&2e3<e&&$("#sdate").val($("#edate").val())}),',
    '$("input[type=date]").keypress(function(e){return true});after',
  ].join("");

  const patched = patchMyFilesScript(source);

  assert.equal(patched.applied, true);
  assert.match(
    patched.source,
    /\$\("input\[type=date\]"\)\.change\(function\(e\)\{date_onchange\(this\)\}\),\$\("input\[type=date\]"\)\.keypress/
  );
  assert.doesNotMatch(patched.source, /13!==e\.keyCode/);
});

test("patchMyFilesScript reports an explicit failure when the upstream handler is missing", () => {
  const patched = patchMyFilesScript("before;after");

  assert.equal(patched.applied, false);
  assert.equal(patched.source, "before;after");
  assert.equal(patched.reason, "date change handler start not found");
});
