# Space Station service IPC

This analysis covers Flydigi Space Station 4.2.0.9 running in the CrossOver
`Test` bottle. It is limited to static inspection and a connection-only named
pipe probe. No controller command or firmware payload was sent.

## CrossOver startup result

`SpaceStationService.exe` starts successfully and the Windows service manager
reports it as `RUNNING`. Its log reaches:

```text
FlydigiWorker Waiting for client connection...
```

The Electron client log from an earlier launch failed with:

```text
connect ENOENT \\?\pipe\fcs.sock
```

The connection-only probe subsequently connected to `fcs.sock` successfully.
The service log recorded a client connection, clean disconnect, and return to
its accept loop. CrossOver's named-pipe transport is therefore working; the old
`ENOENT` entries were produced before the service was ready. The current GUI
launch starts Electron's main, GPU, and network-service processes but does not
update its application log or create a renderer process, so the remaining
failure occurs earlier in Electron initialization and is separate from IPC.
Missing Steam, Epic, and Xbox registry entries are logged but do not stop the
IPC server.

The service is a .NET 6 single-file bundle. Static extraction identifies
`SpaceStationService.dll` as its entry point. `FlydigiWorker.CreatePipeServer`
creates a byte-mode, asynchronous `NamedPipeServerStream` named `fcs.sock`,
with 10 MiB input and output buffers and unlimited server instances. On
Windows it first calls `NamedPipeServerStreamAcl.Create` with access for
built-in users, creator-owner, and local system; it falls back to the ordinary
constructor if ACL creation fails.

The connection-only probe in
`scripts/crossover/SpaceStationPipeProbe.cs` can test this endpoint without
serializing an `IpcCommand`. Connecting and immediately closing cannot request
a device operation or firmware update.

## Electron startup isolation

The installed GUI is Space Station `4.2.0.9`, packaged with Electron `36.9.5`,
Chromium `136.0.7103.177`, Node `22.19.0`, Node module ABI `135`, and N-API
version `10`.

The Electron fuse wire was read directly from the executable using Electron's
documented sentinel and schema:

| Fuse | Installed state |
| --- | --- |
| `RunAsNode` | disabled |
| `EnableCookieEncryption` | enabled |
| `EnableNodeOptionsEnvironmentVariable` | disabled |
| `EnableNodeCliInspectArguments` | disabled |
| `EnableEmbeddedAsarIntegrityValidation` | enabled |
| `OnlyLoadAppFromAsar` | enabled |
| `LoadBrowserProcessSpecificV8Snapshot` | disabled |
| `GrantFileProtocolExtraPrivileges` | enabled |

These settings explain why `ELECTRON_RUN_AS_NODE`, `NODE_OPTIONS=--require`,
and an unpacked `resources/app` directory do not affect the installed
executable. They are packaging security controls, not evidence of a CrossOver
failure.

A disposable copy of the application was used for further isolation. Only the
copy's `RunAsNode` fuse was enabled. The diagnostic probe in
`scripts/crossover/koffi-probe.js` loaded the bundled
`win32_x64/koffi.node` module and successfully defined a packed structure.
Koffi is therefore compatible with the packaged Node/N-API runtime under
CrossOver; the normal N-API fallback seen in the module trace is not the GUI
blocker.

The ASAR was then extracted with `scripts/crossover/extract-asar.rb`. In the
disposable executable, embedded-ASAR validation and only-load-ASAR were
disabled, and the extracted main process was instrumented with
`scripts/crossover/instrument-spacestation-main.rb`. Both ordinary and
explicit-app-directory launches created the Electron browser process. The
explicit launch also created GPU and network-service processes, but neither
launch reached the first statement in `main.js` or created a renderer process.
Changing the application's GPU flags did not change this result.

This narrows the remaining GUI failure to Electron/Chromium bootstrap under
the current CrossOver environment, before Flydigi application JavaScript. It
is not caused by the named pipe, Space Station service, renderer assets, or
Koffi. The complete official GUI therefore still needs a compatible Windows
environment (a VM or physical Windows installation) unless a future CrossOver
release fixes this Electron 36 startup path. ControlLab can continue using the
working service protocol analysis and native macOS IOKit implementations
without depending on the official GUI.

## Wire framing

Both the Electron client and service implement the same framing. Every message
starts with an ASCII header terminated by LF. All integer lengths are signed
32-bit little-endian values.

| Header | Following data |
| --- | --- |
| `FDG_PROTOCOL\n` | 4-byte protobuf length, then one protobuf |
| `FDG_CHUNK\n` | total length, chunk count, then repeated 4-byte chunk length and chunk data |
| `FDG_COMPRESSED\n` | 4-byte gzip length, then gzip-compressed protobuf |

Messages below 1 MiB use `FDG_PROTOCOL`. Messages from 1 MiB through just under
5 MiB use 64 KiB chunks. Messages of at least 5 MiB use gzip. The service
rejects headers longer than 256 bytes, small messages larger than 1 MiB,
chunked messages larger than 5 MiB, chunks larger than 64 KiB, and compressed
payloads larger than 100 MiB.

Client-to-service payloads are protobuf `IpcCommand` messages. The envelope
starts with:

- field 1: `cmdId` (`IpcCommandEnum`)
- field 2: `category` (`Category`)
- fields 3 through 86: a `oneof` containing the command-specific parameters

Service-to-client payloads are protobuf `IpcResult` messages. Their common
fields are:

- field 1: `cmdId`
- field 2: `state`
- field 3: `code`
- field 4: `category`
- remaining fields: a `oneof` containing the result data

`Init` is command ID `1`. Device enumeration starts at `0x1001`; configuration
commands start at `0x1010`. `SwitchUsb` is command ID `15`, confirming that it
is an explicit IPC operation rather than an automatic part of pipe startup.
ControlLab must not send it during compatibility probing.

## Integration consequence

A native macOS compatibility service is technically feasible because the
transport, framing, protobuf descriptor, and command IDs are present in the
installed Electron bundle. It should be implemented as a separate adapter:

1. expose a local `fcs.sock` endpoint compatible with the Electron client;
2. implement only read-only `Init`, device-list, and device-detail operations;
3. translate supported controller and dock operations to ControlLab's IOKit
   layer;
4. explicitly reject `SwitchUsb`, firmware, calibration, test, and other
   destructive or insufficiently understood commands.

This would enable controlled portions of Space Station's UI. It would not
replace the Windows virtual keyboard, virtual mouse, XInput filter, or other
kernel-driver functionality.
