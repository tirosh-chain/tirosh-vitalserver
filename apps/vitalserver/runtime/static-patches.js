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

function patchVitalServerReader(source) {
  if (typeof source !== "string") {
    return patchFailure(source, "source must be a string");
  }

  const streamHeaderStart =
    'g=!1,S=null,C=s.pipe(n);return new Promise(t=>{C.on("data",t=>{var e=0;if(!g){g=!0;var i=t.toString("utf8",e,e+4);';
  const bufferedStreamHeaderStart =
    'g=!1,S=null,H=null,C=s.pipe(n);return new Promise(t=>{C.on("data",t=>{var e=0;if(!g){if(H&&(t=Buffer.concat([H,t],H.length+t.length)),t.length<10)return void(H=t);var vitalDeclaredHeaderLength=t.readUIntLE(8,2);if(t.length<10+vitalDeclaredHeaderLength)return void(H=t);H=null,g=!0;var i=t.toString("utf8",e,e+4);';
  const buffered = replaceExactlyOnce(
    source,
    streamHeaderStart,
    bufferedStreamHeaderStart,
    "VitalServer reader streaming header boundary"
  );
  if (!buffered.applied) {
    return buffered;
  }

  const headerParser =
    'e+=4,e+=2,this.dgmt=t.readIntLE(e,2),e+=2,e+=4;for(var r=0;r<4;r++)t.readUIntLE(e,1),e+=1,3!=r&&0';
  const versionedHeaderParser =
    'var vitalVersion=t.readUIntLE(e,4);if(1!=vitalVersion&&2!=vitalVersion&&3!=vitalVersion)throw new Error("unsupported vital version "+vitalVersion);e+=4;var vitalHeaderLength=t.readUIntLE(e,2);this.dgmt=t.readIntLE(e+2,2),e=10+vitalHeaderLength';
  return replaceExactlyOnce(
    buffered.source,
    headerParser,
    versionedHeaderParser,
    "VitalServer reader fixed header parser"
  );
}

function patchVitalWebviewScript(source) {
  if (typeof source !== "string") {
    return patchFailure(source, "source must be a string");
  }

  const firstPass = replaceExactlyOnce(
    source,
    ";offset=20,console.time",
    ';var vitalVersion=new DataView(data).getUint32(4,!0);if(1!==vitalVersion&&2!==vitalVersion&&3!==vitalVersion)throw new Error("unsupported vital version "+vitalVersion);var vitalPacketOffset=10+new DataView(data).getUint16(8,!0);offset=vitalPacketOffset,console.time',
    "webview first packet offset"
  );
  if (!firstPass.applied) {
    return firstPass;
  }
  return replaceExactlyOnce(
    firstPass.source,
    "for(offset=20;",
    "for(offset=vitalPacketOffset;",
    "webview second packet offset"
  );
}

function replaceExactlyOnce(source, target, replacement, label) {
  const first = source.indexOf(target);
  if (first < 0) {
    return patchFailure(source, `${label} not found`);
  }
  if (source.indexOf(target, first + target.length) >= 0) {
    return patchFailure(source, `${label} is ambiguous`);
  }
  return {
    applied: true,
    source: source.slice(0, first) + replacement + source.slice(first + target.length),
    reason: null,
  };
}

function patchFailure(source, reason) {
  return { applied: false, source: source, reason: reason };
}

module.exports = {
  patchMyFilesScript,
  patchVitalServerReader,
  patchVitalWebviewScript,
};
