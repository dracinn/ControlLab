# Flydigi Charging Station 2 Pro RGB

ControlLab supports the Charging Station 2 Pro display through its dedicated
USB HID interface. This is separate from both the Vader controller's lighting
configuration and SDL's standard gamepad LED API.

## USB identity

- Vendor ID: `0x37D7`
- Product ID: `0x6001`
- Primary usage page: `0xFFA0`
- Primary usage: `1`
- Output report size: 64 bytes
- Report ID: `0`

## Frame layout

The display contains 162 RGB pixels, represented in ControlLab as an 18-by-9
grid. A complete static frame is sent as one initialization report followed by
ten data reports. Animated modes upload a loop of twelve complete frames; the
dock advances through that sequence using the configured cycle time.

The protocol remains a flat 162-pixel sequence. In the app, those pixels are
visualized over Flydigi's official Dock 2 Pro render as a three-pixel-thick,
inverted triangular perimeter with fourteen-pixel straight runs and clustered
corners, matching the physical front panel.

The initialization report begins:

```text
5A A5 61 07 0A 00 00 00 0A 7C
```

Each data report begins:

```text
5A A5 62 <packet-length> 00 <packet-count> <sequence-be16> <payload-length> <payload> <checksum>
```

- `packet-length` is the payload length plus seven. The values `0x39` and
  `0x31` seen in a full custom frame are therefore lengths, not intermediate
  and final flags.
- Payload chunks contain at most 50 bytes.
- The checksum is the wrapping sum from command byte `0x62` through the final
  payload byte.
- ControlLab waits 5 ms between reports.
- The configuration payload starts with frame count, cycle time, brightness,
  mode, direction, and color count. Palette colors and zero or more complete
  162-pixel frames follow.
- Both initialization and data reports contain the actual total packet count.
  This matters for animation sequences, which exceed the ten packets used by a
  single static frame.

## Space Station settings

Static analysis of `Flydigi.ChargerSdk.dll` from Space Station 4.2.0.9 recovered
the dock's complete lighting enum:

- Off
- Solid
- Default
- Custom
- Diagonal Flow
- Breathing
- Gradient
- Wave Gradient
- Rainbow
- Pulse

The direction values are None, Right, Left, Down, Up, Down-right, Up-right,
Down-left, and Up-left. ControlLab exposes the same mode, brightness, cycle
time, direction, and palette fields. Static modes include one complete frame,
while animated modes include a generated twelve-frame loop. Live hardware
testing showed that the dock acknowledges effect metadata without frames but
has no animation content to display.

The heartbeat exposes four device settings and the Charger SDK contains matching
write commands:

- `0x11`: sleep while charging
- `0x12`: LED sync
- `0x13`: turn off with the system
- `0x19`: show the charging animation

ControlLab reads these values before enabling their toggles. Every write waits
for a matching acknowledgement and rejects nonzero device status.

No firmware, bootloader, flash, or erase command is used by this path.

## Provenance

The framing was independently implemented from the protocol demonstrated by
[dracinn/Flydigi-Charging-Station-2-Pro-RGB](https://github.com/dracinn/Flydigi-Charging-Station-2-Pro-RGB)
and verified against a physical Flydigi CD2 on macOS. That repository labels
itself MIT in its README but does not currently include a separate license file;
ControlLab therefore uses the protocol facts without copying its source code.
Mode and setting definitions were independently recovered from Flydigi's
Space Station 4.2.0.9 Charger SDK.
