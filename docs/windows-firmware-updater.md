# Windows firmware updater findings

This note records static analysis of Flydigi Space Station through 4.2.0.9. No
Windows executable was run and no firmware was written to a device.

## Update discovery

The Electron application sends a JSON `POST` request to:

`https://api.flydigi.com/pc/Update/firmware`

For a standard Vader 5 Pro, the identifying values are `device_code = k5`,
`device_id = 128`, VID `37d7`, and PID `2401`. The request includes the current
main, RF, SI, and dongle versions. `Vader5FirmwareUpdateClient` implements this
request and response format.

Using versions read live from the attached controller over USB on 2026-07-21
(main `7.1.5.2`, RF `1.0.2.6`, SI `3.5.1.7`, dongle `0.4.6.7`), the service
reported that main and SI were current. A refreshed catalog snapshot on
2026-07-22 offered:

- Dongle `2.1.3.1`: `K5_BS20_Dongle_V2131_DFU.fwpkg`
- RF `1.1.3.1`: `K5_BS20_Gamepad_V1131_DFU.fwpkg`

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
