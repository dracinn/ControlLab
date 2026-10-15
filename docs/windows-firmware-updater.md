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
dongle `0.4.6.7`), the f5 catalog offers:

- Main `7.1.5.4`: `F5_Gamepad_MH2113_V7154_DFU_20260612.bin` (Megahunt)
- Dongle `0.4.6.7`: `OTA_F5_Dongle_V0467_1209.bin` (Telink OTA image — only
  listed when the reported version is older, i.e. already current here)
- RF and SI return `null` (current)

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

`SwitchUsb` (`00 5A A5 1F 03 06 28 …` on FFA0; byte 0 is the report-ID slot the
Windows `WriteDataImpl` overwrites with `_outReportId = 0`) is echoed by the
device but produces no observable state change — no re-enumeration, no DFU
interface, and FFEE answers OTA frames whether or not it was sent. For the
Telink dongle path it appears to be belt-and-braces; `FirmwareConsole` itself
only invokes the switch for `ChipType.Wch`.
