"use strict";

// Diagnostic-only startup shim for Flydigi Space Station under CrossOver.
// It prevents the native Koffi addon from loading during Electron bootstrap.
// Any later attempt to call a native library fails closed.

const Module = require("module");
const originalLoad = Module._load;

function unavailable(operation) {
  return function () {
    throw new Error(
      `Koffi ${operation} is disabled by the ControlLab CrossOver startup shim`
    );
  };
}

const koffiStub = {
  array(type, length) {
    return { kind: "array", type, length };
  },
  pack(name, members) {
    return { kind: "packed-struct", name, members };
  },
  alloc: unavailable("alloc"),
  decode: unavailable("decode"),
  load: unavailable("load"),
};

Module._load = function (request, parent, isMain) {
  if (request === "koffi") {
    return koffiStub;
  }

  return originalLoad.call(this, request, parent, isMain);
};
