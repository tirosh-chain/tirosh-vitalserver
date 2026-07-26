"use strict";

const assert = require("assert/strict");
const fs = require("fs");
const NodeModule = require("module");
const os = require("os");
const path = require("path");
const test = require("node:test");
const zlib = require("zlib");

const {
  patchMyFilesScript,
  patchVitalServerReader,
  patchVitalWebviewScript,
} = require("./static-patches");

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

test("patchVitalServerReader uses the declared header length and validates versions", () => {
  const source =
    'before;g=!1,S=null,C=s.pipe(n);return new Promise(t=>{C.on("data",t=>{var e=0;if(!g){g=!0;var i=t.toString("utf8",e,e+4);middle;e+=4,e+=2,this.dgmt=t.readIntLE(e,2),e+=2,e+=4;for(var r=0;r<4;r++)t.readUIntLE(e,1),e+=1,3!=r&&0;after';

  const patched = patchVitalServerReader(source);

  assert.equal(patched.applied, true);
  assert.match(patched.source, /vitalHeaderLength=t\.readUIntLE\(e,2\)/);
  assert.match(patched.source, /e=10\+vitalHeaderLength/);
  assert.match(patched.source, /unsupported vital version/);
  assert.match(patched.source, /Buffer\.concat\(\[H,t\]/);
  assert.match(patched.source, /t\.length<10\+vitalDeclaredHeaderLength/);
  assert.doesNotMatch(patched.source, /e\+=4,e\+=2,this\.dgmt/);
});

test("patchVitalWebviewScript uses the declared header length for both passes", () => {
  const source =
    "before;offset=20,console.time('parsing');middle;for(offset=20;offset<data.byteLength;){};after";

  const patched = patchVitalWebviewScript(source);

  assert.equal(patched.applied, true);
  assert.match(patched.source, /vitalPacketOffset=10\+new DataView\(data\)/);
  assert.match(patched.source, /offset=vitalPacketOffset,console\.time/);
  assert.match(patched.source, /for\(offset=vitalPacketOffset;/);
  assert.match(patched.source, /unsupported vital version/);
  assert.doesNotMatch(patched.source, /offset=20/);
});

test("Vital reader patches fail explicitly when upstream anchors change", () => {
  const serverPatch = patchVitalServerReader("before;after");
  const webviewPatch = patchVitalWebviewScript("before;after");

  assert.equal(serverPatch.applied, false);
  assert.match(serverPatch.reason, /not found/);
  assert.equal(webviewPatch.applied, false);
  assert.match(webviewPatch.reason, /not found/);
});

test("Vital reader patches apply to the bundled upstream assets", () => {
  const vendorRoot = path.resolve(
    __dirname,
    "../../../vendor/vitalserver/vitalserver-old/service"
  );
  const serverSource = fs.readFileSync(
    path.join(vendorRoot, "include", "vitaldb.js"),
    "utf8"
  );
  const webviewSource = fs.readFileSync(
    path.join(vendorRoot, "static", "js", "webview.js"),
    "utf8"
  );

  const serverPatch = patchVitalServerReader(serverSource);
  const webviewPatch = patchVitalWebviewScript(webviewSource);

  assert.equal(serverPatch.applied, true, serverPatch.reason);
  assert.equal(webviewPatch.applied, true, webviewPatch.reason);
  assert.doesNotMatch(serverPatch.source, /e\+=4,e\+=2,this\.dgmt/);
  assert.doesNotMatch(webviewPatch.source, /offset=20/);
});

test("patched bundled index reader reads supported versions and extended headers", async (context) => {
  const vendorRoot = path.resolve(
    __dirname,
    "../../../vendor/vitalserver/vitalserver-old/service"
  );
  const readerPath = path.join(vendorRoot, "include", "vitaldb.js");
  const source = fs.readFileSync(readerPath, "utf8");
  const patched = patchVitalServerReader(source);
  assert.equal(patched.applied, true, patched.reason);

  const compiled = new NodeModule(readerPath, module);
  compiled.filename = readerPath;
  compiled.paths = NodeModule._nodeModulePaths(path.dirname(readerPath));
  compiled._compile(patched.source, readerPath);
  const VitalFile = compiled.exports;

  const tempDirectory = fs.mkdtempSync(path.join(os.tmpdir(), "vital-v3-reader-"));
  context.after(() => fs.rmSync(tempDirectory, { recursive: true, force: true }));
  for (const [version, timestamp, headerLength] of [
    [1, "130001", 10],
    [2, "130002", 10],
    [3, "130003", 27],
    [3, "130004", 65535],
  ]) {
    const filename = `OR-A_260721_${timestamp}`;
    const vitalPath = path.join(tempDirectory, `${filename}.vital`);
    fs.writeFileSync(
      vitalPath,
      zlib.gzipSync(vitalPayload(version, headerLength))
    );

    const values = {};
    const indexed = new Promise((resolve) => {
      const redis = {
        sadd() {},
        hincrby() {},
        zadd() {},
        set(key, value) {
          values[key] = value;
          if (key.startsWith("api:tracklist:")) {
            resolve();
          }
        },
      };
      new VitalFile(redis, vitalPath);
    });
    let timeoutId;
    const timeout = new Promise((_, reject) => {
      timeoutId = setTimeout(
        () => reject(new Error(`bundled v${version} reader index timeout`)),
        1000
      );
    });
    await Promise.race([indexed, timeout]);
    clearTimeout(timeoutId);

    const fileInfo = JSON.parse(values[`api:filelist:fileinfo:${filename}`]);
    const tracks = JSON.parse(values[`api:tracklist:${filename}`]);
    assert.equal(fileInfo.dtstart, 100);
    assert.equal(fileInfo.dtend, 100);
    assert.deepEqual(tracks, ["Source/HR"]);
  }
});

function vitalPayload(version, headerLength = version === 3 ? 27 : 10) {
  const header = Buffer.alloc(10 + headerLength);
  header.write("VITA", 0, "ascii");
  header.writeUInt32LE(version, 4);
  header.writeUInt16LE(headerLength, 8);
  header.writeInt16LE(-540, 10);
  if (version === 3) {
    header.writeDoubleLE(100, 20);
    header.writeDoubleLE(101, 28);
    header.writeUInt8(0, 36);
  }

  const device = Buffer.concat([
    uint32(1),
    vitalString("monitor"),
    vitalString("Source"),
    vitalString(""),
  ]);
  const track = Buffer.concat([
    uint16(1),
    Buffer.from([2, 1]),
    vitalString("HR"),
    vitalString("/min"),
    float32(0),
    float32(200),
    uint32(0),
    float32(0),
    float64(1),
    float64(0),
    Buffer.from([2]),
    uint32(1),
  ]);
  const record = Buffer.concat([uint16(10), float64(100), uint16(1), float32(72)]);
  return Buffer.concat([
    header,
    vitalPacket(9, device),
    vitalPacket(0, track),
    vitalPacket(1, record),
  ]);
}

function vitalPacket(type, body) {
  return Buffer.concat([Buffer.from([type]), uint32(body.length), body]);
}

function vitalString(value) {
  const body = Buffer.from(value, "utf8");
  return Buffer.concat([uint32(body.length), body]);
}

function uint16(value) {
  const buffer = Buffer.alloc(2);
  buffer.writeUInt16LE(value);
  return buffer;
}

function uint32(value) {
  const buffer = Buffer.alloc(4);
  buffer.writeUInt32LE(value);
  return buffer;
}

function float32(value) {
  const buffer = Buffer.alloc(4);
  buffer.writeFloatLE(value);
  return buffer;
}

function float64(value) {
  const buffer = Buffer.alloc(8);
  buffer.writeDoubleLE(value);
  return buffer;
}
