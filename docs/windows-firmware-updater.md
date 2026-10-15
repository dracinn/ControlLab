# Windows firmware updater findings

This note records static analysis of Flydigi Space Station through 4.2.0.9. No
Windows executable was run and no firmware was written to a device.

## Update discovery

The Electron application sends a JSON `POST` request to:

`https://api.flydigi.com/pc/Update/firmware`

For the Vader 5 Pro the identifying values are `device_code = f5`,
`device_id = 130`, VID `37d7`, and PID `2401` — the device reports
`DeviceType` 0x82 (F5) in its heartbeat response, and the SDK maps
`"VADER 5"` -> `"f5"`. (`device_code = k5`/`device_id = 128` is the Apex 5 —
an earlier draft of this document used those values by mistake.) The request
includes the current main, RF, SI, and dongle versions.
`Vader5FirmwareUpdateClient` implements this request and response format.

Using versions read live over USB (main `7.1.5.2`, RF `1.0.2.6`, SI `3.5.1.7`,
dongle `0.4.6.7`), the f5 catalog offers (with `appVersion` >= `5.0.0.0`;
older app versions see fewer entries — e.g. `4.1.0.31` only exposes main
`7.1.5.4`):

- Main `7.2.2.6`: `F5P_MH2113_Refactor_V7226.bin` (Megahunt, raw ARM image,
  208500 B, vector table at base `0x08000000`)
- RF `1.0.4.3`: `F5P_8208_Refactor_V1043.bin` (Telink 8208 image, `KNLT`
  magic, `source_bin_size` at offset 24, 27380 B)
- Dongle `0.4.8.3`: `F5P_Telink80_Dongle_Refactor_V0483.bin` (Telink image,
  27012 B)
- SI: `null`

Per-chip `min_app_version` gates which releases are returned; the app now
reports `5.0.0.0` so all currently published updates are visible.

## Windows dispatch

The app calls `FirmwareConsole.exe` with the device code, chip module, chip
type, firmware URL, VID, and PID. The console downloads a direct binary or
extracts the first `.bin`, `.ufw`, or `.hex` file from a ZIP, then selects a
backend from the chip type:

- WCH: CH375 updater
- Telink: HID updater
- NearLink: HSH BurnTool updater
- Megahunt: external HID boot tool
- FREQ: screen OTA updater
- Jieli: JieLi updater

The available Vader 5 RF and dongle packages are BS20/NearLink `.fwpkg` files.
The Windows backend invokes its bundled tool in this form:

`BurnTool.exe -dfu -pid:0xPID -vid:0xVID -usage:0x1 -usagepage:0xUSAGE -bin:PACKAGE`

RF uses usage page `FFEF`; other modules use `FFEE`. The package begins with
magic `4e 15 8d cb`. Space Station 4.2.0.9's native updater has now been
recovered without execution. BurnTool decrypts the protected content with
AES-128-CBC, then `libburn` parses and CRC-checks the decoded partition table.
The key derivation, boot identity, and exact transport acknowledgements remain
unresolved, so the NearLink writer has not been connected to the macOS app.

More detailed binary hashes, parser structure, and transport findings are in
[`nearlink-firmware-analysis.md`](nearlink-firmware-analysis.md).

## Recovered HID OTA codec

`Vader5HIDOTAProtocol` is a clean Swift representation of the managed HID
backend used for compatible chip types. Reports are 64 bytes with report ID
`05`:

- Start: `05 02 02 00 01 ff`
- Data: `05 02 LL 00`, followed by up to three 20-byte records
- Record: 16-bit block index, 16 data bytes, CRC-16/MODBUS
- Finish: `05 02 06 00 02 ff`, last block index, two's-complement index
- Completion response: `05 02 03 00 06 ff STATUS`
- Firmware-info response: `05 01 08 00 VERSION32 CRC32`

The codec intentionally does not switch the controller into boot mode or write
to its HID interface. Before enabling writes, capture and verify the
`SwitchUsb` transition, boot-mode USB identity, acknowledgements, and recovery
behavior on sacrificial/test hardware.

## SwitchUsb mode-switch (decoded 2026-07-23)

`SpaceStationService` handles the `SwitchUsb` IPC command and calls
`ControllerSdk.SwitchToFirmwareUpgradeMode(controller, chipModule, chipType)`.
For a `NewXInput` device (Flydigi VID 0x37D7, non-Microsoft manufacturer) the
switch command is a 32-byte report on the 0xFFA0 command interface:

```
byte 0: 0x00        (out report ID slot; overwritten to 0 — no report IDs on 0xFFA0)
byte 1: 0x5A        (sync hi)
byte 2: 0xA5        (sync lo)
byte 3: 0x1F        (command ID 31 — SwitchToFirmwareUpgradeMode)
byte 4: 0x03        (payload length 3)
byte 5: chipModule  (0x06 = ChipDongle)
byte 6: checksum    (additive sum of bytes 3..5: 0x1F+0x03+0x06 = 0x28)
bytes 7-31: zero padding
```

So the dongle switch report is: `00 5A A5 1F 03 06 28 00×25`.

Confirmed USB topology of the receiver in normal mode (via IOHIDManager):

| Interface | UsagePage | Usage | Report IDs | Purpose |
|-----------|-----------|-------|------------|---------|
| 0xFFA0 | 65440 | 1 | none (0) | Flydigi command channel, 32-byte in/out |
| 0x0001 | 1 | 2 | 2 | gamepad reports |
| 0xFFEE | 65518 | 0 | 5 | firmware update channel, 64-byte in/out/feature |

The FFEE update interface is already present and responsive in normal mode —
the earlier `Device Not Found` from FirmwareConsole in the VM was purely a
Windows guest USB enumeration failure (composite device Code 10), not a missing
interface. `libusb` cannot claim the HID interfaces on macOS while the Apple
HID driver holds them, so QEMU `usb-host` passthrough of the whole composite
device is a dead end on this host.

Receiver `chipType` for the Vader 5 Pro (F5, `DeviceType` 130) dongle is
**Telink** — `GenerateControllerVader5` maps `ChipDongle -> ChipType.Telink`,
so the dongle update uses the FFEE `HidUpdater` OTA codec. (The
`NearLink -> BurnTool.exe -dfu` path applies to the **Apex 5** (K5,
`DeviceType` 128) — `GenerateControllerApex5` maps its dongle to `NearLink`.
`K5_BS20_Dongle_*.fwpkg` is therefore Apex 5 firmware, not Vader 5 Pro.)

The genuine Vader 5 Pro dongle package is a Telink image
(`OTA_F5_Dongle_V0467_1209.bin`, `TLNK`/`KNLT` magic, `driver_sdk_B80_S2`
trailer, `source_bin_size` u32 at offset 24, image CRC32 at `size - 4` —
exactly the layout `HidUpdater.LoadBinFile` expects).

## Investigation status

- [x] SwitchUsb command bytes decoded (`5A A5 1F 03 06 28` on the FFA0 interface)
- [x] Telink `HidUpdater` OTA codec byte-exact (already in `Vader5HIDOTAProtocol`)
- [x] FFEE channel confirmed live in normal mode (feature report 5 read OK)
- [x] SwitchUsb sent on the host FFA0 interface; command echoed back on the FFA0
      input pipe (`5A A5 1F 03 06 28 … 50`), no USB re-enumeration
- [x] FFEE transport probed: every 64-byte output report is echoed verbatim on
      the FFEE input pipe — this echo is the per-frame ACK the official
      `HidUpdater` waits for (it only parses the completion frame
      `05 02 03 00 06 ff STATUS`)
- [x] Correct macOS write form confirmed:
      `IOHIDDeviceSetReport(dev, kIOHIDReportTypeOutput, 5, buf64)` where
      `buf64[0] = 0x05` (report ID inline). A 63-byte body (report ID as a
      separate argument only) is accepted by the host but produces no echo.
- [x] Dry-run with the genuine F5 dongle image
      (`OTA_F5_Dongle_V0467_1209.bin`, same version as installed): start frame
      `05 02 02 00 01 ff` and two data frames each produced clean echo-ACKs —
      the earlier `05 02 03 00 06 ff 0b` error was caused by feeding the Apex 5
      `K5_BS20` `.fwpkg`, i.e. wrong image for this chip. The Telink OTA write
      path accepts the correct image.
- [x] Finish/commit frame semantics probed safely: after start + two data
      frames, sending `05 02 06 00 02 ff <lastBlock> <~lastBlock+1>` with
      `lastBlock=5` produced the completion frame `05 02 03 00 06 ff 0b` —
      error `0x0b`, image validation rejected the truncated payload and the
      device stayed fully operational (versions intact, stream alive). This
      confirms a partial OTA does not commit: the dongle validates the image
      before swapping.
- [x] **Full update performed on real hardware** (2025-10-14): the complete
      `OTA_F5_Dongle_V0467_1209.bin` image (22212 B → 1389 records → 463 data
      frames) was transferred echo-paced on FFEE, followed by the finish frame
      `05 02 06 00 02 ff 6c 05 94 fa` (lastBlock=1388, complement 0xFA94).
      The device replied `05 02 03 00 06 ff 00` — status `0x00`, OTA success.
      Post-commit heartbeat confirmed the dongle healthy and reporting the
      same version `0.4.6.7` (the image was version-identical, so the commit
      was a no-op in content but exercised the entire write+commit path).
- [x] In-app writer enabled: `Vader5DongleUpdater` performs the verified
      flow on the real FFEE interface (echo-paced data frames, finish-frame
      completion status). Verified again via
      `controllab-cli --update-dongle <image> --confirm-update` — full image
      transferred, completion `0x00`, device healthy. GUI exposes it behind a
      confirmation dialog when a validated Telink dongle image is inspected.

## Multi-module support (2026-07-23)

The F5 module map from `GenerateControllerVader5`:

| Module | Chip | Backend | Channel |
|--------|------|---------|---------|
| ChipMain (0) | Megahunt MH2113 | `MhExeUpdater` → `tool/mhtool/hid_boot_command.exe` | separate boot device |
| ChipRf (1) | Telink 8208 | `HidUpdater` | usage page `FFEF` |
| ChipSi (2) | Jieli | `JieLiUpdater` / `jl_firmware_upgrade_x64.dll` | USB mass-storage UFW |
| ChipDongle (6) | Telink | `HidUpdater` | usage page `FFEE` (done) |

`SwitchUsb` on FFA0 takes the `ChipModule` value directly:
`5A A5 1F 03 <module> <sum(1F 03 module)>`. `FirmwareConsole` only invokes it
for `ChipType.Wch`; Telink targets go straight to `HidUpdater`.

### Controller FFEF channel (probed on hardware)

When the controller is connected by USB-C it enumerates as `37d7:2401` (same
VID/PID/product string as the receiver) with interfaces `0001` (gamepad),
`FFA0` (command), and `FFEF` (update). The FFEF endpoint accepts report ID 5
output reports and echoes them. During an OTA probe it answered every frame
with `05 02 03 00 06 ff 09 XX` — status `0x09`, which the official
`HidUpdater` treats as "OTA Fail, Error Code = 9". The channel is live but
rejects OTA frames in the observed state; the missing arming precondition
(possibly radio-link state, battery/charge gating, or an additional FFA0
handshake) is not yet identified. No RF image has been committed.

### Megahunt main chip (decoded from `hid_boot_command.exe`)

The boot tool opens `hid_open(vid=0x0483, pid=0x5720)` — a distinct boot-mode
USB identity that does not enumerate in normal mode — and speaks HID feature
reports:

- `01`: `[01][cmd32][00 00 00 00]` send (9 B); `[01][4-byte value]` read (5 B)
- `02`: `[02][len][00][data <= 60]` write (63 B); same layout read back
- `03`: `[03][8-byte value][4-byte value]` set (13 B) and get
- `04`: `[04][cmd32]` (5 B)
- `05`: `[05 A5 A5 A5 A5]` — ISP-entry magic

Console flow per the binary's strings: chip erase → flag write → program
(progress %) → flag read → verify (progress %) → "update complete". The
trigger that makes the controller enumerate `0483:5720` (the Megahunt boot
mode) is still unidentified; `SwitchUsb(ChipMain)` did not produce a new
device in the tested states.

### SI chip (Jieli)

`JieLiUpdater` scans drive letters A–Z for a vendor mass-storage device and
writes a `.ufw` via `jl_firmware_upgrade_x64.dll` — a Windows drive-letter
workflow. The equivalent on macOS would be watching for a new MSD volume and
writing the UFW file; no such volume has been observed yet.

### Implementation state

`Vader5DongleUpdater` gained a `Target` selector — `.dongle` (FFEE, verified)
and `.controllerRF` (FFEF, channel live, commit not yet verified — the
`0x09` precondition must be resolved first). The GUI offers an install
button per target only when that channel is enumerated and the inspected
image passes Telink validation. CLI: `--update-dongle` / `--update-rf`, both
requiring `--confirm-update`.

`SwitchUsb` (`00 5A A5 1F 03 06 28 …` on FFA0; byte 0 is the report-ID slot the
Windows `WriteDataImpl` overwrites with `_outReportId = 0`) is echoed by the
device but produces no observable state change — no re-enumeration, no DFU
interface, and FFEE answers OTA frames whether or not it was sent. For the
Telink dongle path it appears to be belt-and-braces; `FirmwareConsole` itself
only invokes the switch for `ChipType.Wch`.
