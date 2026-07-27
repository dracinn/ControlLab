# frozen_string_literal: true

# Adds fail-closed startup checkpoints to an extracted, disposable copy of
# Space Station's generated main.js. It never edits the installed application.

main_path, trace_path = ARGV
abort("usage: instrument-spacestation-main.rb <main.js> <windows-trace-path>") unless main_path && trace_path

source = File.binread(main_path)
escaped_trace_path = trace_path.dump

prelude = <<~JAVASCRIPT
  "use strict";
  globalThis.__controlLabDiagnostic = {
    fs: require("node:fs"),
    tracePath: #{escaped_trace_path}
  };
  globalThis.__controlLabMark = function (stage, detail) {
    const row = JSON.stringify({
      time: new Date().toISOString(),
      stage,
      detail: detail == null ? null : String(detail)
    });
    globalThis.__controlLabDiagnostic.fs.appendFileSync(
      globalThis.__controlLabDiagnostic.tracePath,
      row + "\\n"
    );
  };
  globalThis.__controlLabMark("main:start");
  process.on("uncaughtExceptionMonitor", function (error) {
    globalThis.__controlLabMark("main:uncaught", error && error.stack || error);
  });
JAVASCRIPT

replacements = {
  "\"use strict\";" => prelude,
  "console.log(\"===============MAIN PROCESS===========\");" =>
    "__controlLabMark(\"main:top-level-complete\");",
  "async function md(){const e=Ca();" =>
    "async function md(){__controlLabMark(\"window:create-start\");const e=Ca();__controlLabMark(\"window:created\");",
  "e.loadFile(v.join(__dirname,\"../renderer/main_window/index.html\")),Gd(e),e}" =>
    "__controlLabMark(\"window:load-file-start\"),e.loadFile(v.join(__dirname,\"../renderer/main_window/index.html\")).then(()=>__controlLabMark(\"window:load-file-complete\")).catch(t=>__controlLabMark(\"window:load-file-error\",t&&t.stack||t)),Gd(e),e}",
  "Fi(),S.app.whenReady().then(async()=>{" =>
    "__controlLabMark(\"socket:init-start\"),Fi(),__controlLabMark(\"electron:when-ready-wait\"),S.app.whenReady().then(async()=>{__controlLabMark(\"electron:ready\");",
  "U.once(\"ready-to-show\",()=>{" =>
    "U.once(\"ready-to-show\",()=>{__controlLabMark(\"window:ready-to-show\");"
}

replacements.each do |needle, replacement|
  count = source.scan(needle).length
  abort("expected exactly one occurrence of #{needle.inspect}, found #{count}") unless count == 1
  source = source.sub(needle, replacement)
end

File.binwrite(main_path, source)
puts main_path
