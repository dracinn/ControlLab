"use strict";

// Diagnostic-only probe for the Koffi native addon bundled with Space Station.
// Run this with a disposable Electron executable whose RunAsNode fuse is enabled.
// It defines an in-memory type only; it does not load a DLL or access hardware.

const fs = require("node:fs");
const koffiPath = process.argv[2];
const resultPath = process.argv[3];

if (!koffiPath || !resultPath) {
  process.exitCode = 2;
} else {
  const result = {
    runtime: {
      electron: process.versions.electron,
      node: process.versions.node,
      modules: process.versions.modules,
      napi: process.versions.napi,
    },
  };

  try {
    const koffi = require(koffiPath);
    const probeType = koffi.pack("ControlLabProbe", {
      marker: "uint8_t",
      value: "uint32_t",
    });
    Object.assign(result, {
      loaded: true,
      exports: Object.keys(koffi).sort(),
      probeType: {
        type: typeof probeType,
        keys: Object.keys(probeType).sort(),
      },
    });
  } catch (error) {
    Object.assign(result, {
      loaded: false,
      error: error instanceof Error ? error.stack : String(error),
    });
    process.exitCode = 1;
  }

  fs.writeFileSync(resultPath, `${JSON.stringify(result, null, 2)}\n`);
}
