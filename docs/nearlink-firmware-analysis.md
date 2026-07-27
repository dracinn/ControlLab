# Vader 5 Pro NearLink firmware analysis

This document records read-only analysis performed on macOS. No firmware-write,
erase, update-mode, or bootloader-transition command was sent to a controller.

## Official catalog snapshot

On 2026-07-22, Flydigi's catalog returned these updates for a Vader 5 Pro
reporting controller `7.1.5.2`, RF `1.0.2.6`, SI `3.5.1.7`, and dongle
`0.4.6.7`:

| Module | Version | Package | Size | SHA-256 |
| --- | --- | --- | ---: | --- |
| Dongle | 2.1.3.1 | `K5_BS20_Dongle_V2131_DFU.fwpkg` | 327,312 | `9f0e81fbfffc00fad5f84567529b616cfffdf9750e4edd6b9921315b36d4957b` |
| RF | 1.1.3.1 | `K5_BS20_Gamepad_V1131_DFU.fwpkg` | 331,472 | `1d3327d77fc9c603ab8d62263b80457eae0bdd90afe426ddd787ef226679334a` |

## Confirmed package layout

Both packages have the same bounded container structure:

| Field | Dongle | RF |
| --- | ---: | ---: |
| outer header | `0x0000`, 1,280 bytes | same |
| inner header | `0x0500`, 768 bytes | same |
| descriptor table | `0x0800` | same |
| `QTOF` subpackage | `0x0830`, 325,216 bytes | `0x0830`, 329,376 bytes |
| protected payload | `0x08D0`, 325,056 bytes | `0x08D0`, 329,216 bytes |
| payload prefix | `5A 00 10 00` | same |

Descriptor offsets and lengths are little-endian 32-bit values. In both files,
the protected payload ends exactly at the subpackage boundary and the
subpackage ends exactly at end-of-file. The inner descriptor contains the exact
SHA-256 of the protected payload; ControlLab verifies it during inspection. The
outer descriptor's 32-byte value does not match a direct SHA-256 or SM3 digest
of the complete `QTOF` range and remains unidentified. The high-entropy body is
consistent with encrypted or compressed data, but that remains an inference.

`Vader5FirmwarePackageInspector` now parses and bounds-checks this structure. It
does not extract, decrypt, modify, or execute the payload.

## Full-size simulator results

The official dongle package produced 20,457 recovered-HID blocks and the RF
package produced 20,717. Both passed these in-memory scenarios:

- clean transfer
- one corrupted packet followed by a successful retry
- disconnect followed by a restart from block zero
- interruption followed by a restart from block zero

These tests validate ControlLab's simulator and recovered generic HID codec.
They do **not** prove that the NearLink bootloader uses that codec.

## Native updater recovered from Space Station 4.2.0.9

The Space Station 4.2.0.9 installer is Inno Setup 6.7.0. It was unpacked on
macOS without executing any Windows code. The following native components were
recovered and inspected with PE metadata, strings, exports, and disassembly:

| Component | Size | SHA-256 |
| --- | ---: | --- |
| `BurnTool.exe` | 2,057,376 | `31d424b7f1f083f9a45f000a907d87bb84abda3b394fbeff8adf5a0b812dbe76` |
| `libburn.dll` | 3,506,624 | `dd67d22d6e0fe7da2a087cdd623e8a1fee93000b96d9f089ad234dbd09533e43` |
| `FirmwareConsole.exe` | 71,135,192 | `f3ee2578b5fd9bd926540f37401bdfc2dc0def957aea41c5860f82e42d2a52cf` |
| `SpaceStationService.exe` | 80,379,816 | `a6130e58ea566a6e390b51ccaaa77f30880be839de4537a4ef272cf5c91d4015` |

The binaries are not committed to this repository.

### Confirmed dispatch

Space Station first sends IPC command `IpcCommandEnum_SwitchUsb` (`15`) with
the device category, code, UID, chip module, and chip type. It waits five
seconds, then starts `FirmwareConsole.exe` with those values, the firmware URL,
and the runtime VID/PID. The console's NearLink backend invokes:

```text
BurnTool.exe -dfu -pid:0xPID -vid:0xVID -usage:0x1 -usagepage:0xPAGE -bin:PACKAGE
```

RF uses usage page `FFEF`; dongle/other modules use `FFEE`. Space Station also
contains a compatibility rewrite from normal Xbox VID/PID `045e:028e` to
`04b4:2412` for main/dongle updates. That rewrite is confirmed application
behavior, but it is not sufficient evidence that `04b4:2412` is the Vader 5
Pro receiver's boot identity.

The shipped chip table maps `BS2X`, `BS2X-USB`, `BS2X-Jlink`, and `BS2X-SLE`
to BurnTool configuration IDs 12, 14, 15, and 21 respectively. Its DFU config
leaves VID/PID blank because they are supplied at runtime.

### Recovered SwitchUsb frame and live result

Static extraction and decompilation of the self-contained
`SpaceStationService.exe` bundle recovered the controller SDK's
`SwitchToFirmwareUpgradeModeCommandFactory`. For Flydigi VID `37d7`, the SDK
selects its NewXInput protocol and builds a 32-byte HIDAPI buffer:

```text
report-id | 5A A5 | command | length | chip-module | checksum | zero padding
00          5A A5   1F        03       module        sum(1F,03,module)
```

The main-chip payload therefore begins `5A A5 1F 03 00 22`; RF begins
`5A A5 1F 03 01 23`. The `00` report-ID byte is supplied separately to
IOHID on macOS. `CHIP_MAIN` is `0`, `CHIP_RF` is `1`, and the checksum is an
eight-bit additive sum. The command has no specialized acknowledgement
parser. Space Station's communication layer can send the initial command plus
three retries at 500 ms intervals before the renderer's five-second delay
expires.

On 2026-07-23, the main and RF forms were tested against a wired Vader 5 Pro
at `37d7:2401`. A normal `FFA0` heartbeat was required and received before
each transition attempt. Tests covered one send, the four-attempt retry
sequence, and both the 31-byte HIDAPI payload and the 32-byte IOHID report
form. No test launched BurnTool or sent firmware, erase, or data frames.

None of the transition attempts caused USB re-enumeration or exposed the
expected RF `FFEF` interface. The normal heartbeat continued to respond, and
the `FFEE` feature status remained the runtime signature
`04 55 91 01 00 00 00 00` repeated through the 64-byte report. Directly
replaying the recovered frame therefore does **not** reproduce Space Station's
mode switch on this device. A required service/session state or another
precondition remains unidentified, so ControlLab must not expose this command
as a user-facing update control.

### Confirmed package processing

`BurnTool.exe` imports OpenSSL's `AES_set_decrypt_key` and `AES_cbc_encrypt`.
The decryption wrapper selects a 128-bit key, copies a separate 16-byte IV, and
calls AES-CBC in decrypt mode before validating the decoded package magic. The
static call path has not yet established how the key and IV are derived, so
ControlLab does not attempt decryption.

`libburn.dll` exports `DownloadAllinoneBin`, `OpenUsb`, `SetChipType`,
`SetHandshakeTimeout`, and `SetPerPacketSize`. Its BS2X-related `BurnTypeSixChip`
implementation includes `ParseNormalFwpkg`, `ParseNewFwpkg`, `SendShakeHand`,
`DownloadBootData`, `SendSsbData`, `SendShaData`, and `SendExitFrame`.

The decoded normal package parser recognizes magic `0xEFBEADDF`. The new parser
accepts the `0xEFBEADCF` through `0xEFBEADDE` family, bounds-checks its table,
and verifies a SOP CRC-16 before accepting partition records. New-format table
entries are `0x118` bytes; older entries are `0x34` bytes. These structures are
inside the protected payload and are not the outer `4E 15 8D CB` container.

The transport uses libusb bulk and interrupt transfers, discovers endpoints
from the active USB interface, and has distinct handshake, data, erase, and
frame timeout paths. Embedded messages confirm retry and ACK-timeout behavior,
but the exact retry counts and acknowledgement bytes have not yet been proven.

## Gate for any future hardware experiment

Real writes remain disabled. A hardware experiment must not be added until all
of the following are captured and reviewed:

- the missing `SwitchUsb` precondition and an observable transition or response
- normal and bootloader USB identities and HID descriptors
- package authentication/decryption behavior
- data acknowledgements, timeouts, retry limits, and completion verification
- a readable backup or vendor-supported recovery procedure
- proof on a spare dongle that interruption does not create an unrecoverable state

Until then, ControlLab may inspect packages and simulate update behavior only.
