# ControlLab

ControlLab provides experimental macOS interoperability support for the Flydigi Vader 5 Pro
2.4 GHz USB receiver and Xbox-compatible Bluetooth mode. The USB bridge activates
the controller's enhanced HID protocol directly through IOKit; Bluetooth uses
SDL3's standard gamepad layer over the profile already exposed by macOS.

Static findings from the official Windows firmware updater, including the
update endpoint and recovered HID OTA packet format, are in
[`docs/windows-firmware-updater.md`](docs/windows-firmware-updater.md).
The current BS20 package layout and full-size recovery simulations are recorded
in [`docs/nearlink-firmware-analysis.md`](docs/nearlink-firmware-analysis.md).
An Android HCI snoop workflow for capturing the official mobile updater is in
[`docs/android-firmware-capture.md`](docs/android-firmware-capture.md).
The clean-room Space Station lighting analysis and recovered New XInput RGB
packet layout are in
[`docs/spacestation-rgb-analysis.md`](docs/spacestation-rgb-analysis.md).
The verified Charging Station 2 Pro display framing is documented in
[`docs/flydigi-dock-rgb.md`](docs/flydigi-dock-rgb.md).

The app now includes a **Firmware Diagnostics** section that reads the connected
controller's current firmware versions over USB, checks those versions against
Flydigi's service, downloads available packages to a user-selected file, inspects
packages, and runs an in-memory OTA simulator. Downloads are storage-only;
attempts to request a real firmware update are refused. The app does not switch
USB modes, erase, or write controller firmware.

Flydigi currently returns package links using HTTP. The downloader upgrades the
known `api-web.cdn.flydigi.com` host to its working HTTPS endpoint and rejects
unrecognized insecure download hosts.

> [!IMPORTANT]
> The firmware update process still requires testing on Windows with the official
> Flydigi application. In particular, the NearLink `SwitchUsb` transition,
> boot-mode USB identity, `.fwpkg` validation, acknowledgements, failure recovery,
> and rollback behavior must be captured and verified before real firmware writes
> are enabled on macOS. Do not use Firmware Diagnostics as a production updater.

## Hardware

- Controller: Flydigi Vader 5 Pro
- USB vendor ID: `0x37D7`
- USB product ID: `0x2401`
- Transport: Flydigi 2.4 GHz USB receiver
- Charging Station 2 Pro product ID: `0x6001`

The receiver exposes vendor-defined HID interfaces instead of a standard HID
gamepad collection. The bridge uses the `0xFFA0` interface, sends the documented
initialization sequence, and decodes the resulting `5A A5 EF` reports.

## Current status

Working and tested on Apple silicon:

- receiver discovery and user-space access
- Flydigi initialization handshake
- sticks, analog triggers, D-pad, and standard buttons
- M1-M4, LM/RM, Home, and Fn/O
- C and Z face inputs
- gyroscope and accelerometer decoding
- live controller, RF, SI, and dongle firmware-version reads
- SDL3-backed Xbox-compatible Bluetooth input for sticks, triggers, D-pad,
  standard buttons, and Guide/Home
- steady-color RGB control over the USB receiver after the current lighting
  configuration is read and validated
- SDL3 RGB output for gamepads that advertise SDL's standard RGB LED capability
- native IOKit control of all 162 RGB pixels on the Charging Station 2 Pro,
  including Space Station's ten lighting modes, brightness, cycle time,
  direction, palettes, custom frames, and display off
- live Charging Station behavior reads and writes for sleep while charging,
  charging animation, LED sync, and turn-off-with-system

The physical reader and protocol decoder work without elevated privileges.
Creating the standard virtual gamepad requires Apple's restricted
`com.apple.developer.hid.virtual.device` entitlement. Running as root does not
bypass that requirement on current macOS releases.

Gyroscope, accelerometer, and rumble are not yet exposed through the virtual
gamepad.

Bluetooth mode is monitor-only because macOS already exposes it as a standard
gamepad. Vader-specific extra buttons, motion sensors, and firmware metadata are
not present in its Bluetooth report; use the USB receiver for those features.
SDL 3.4.12 does not advertise an RGB LED for Flydigi's Xbox-compatible Bluetooth
profile, so Vader lighting currently uses the verified USB protocol. The SDL
path remains capability-gated for compatible standard gamepads.

The USB lighting implementation was checked against the official Space Station
4.2.0.9 controller library. ControlLab reads and validates the existing versioned
LED configuration before enabling Apply, then uses the recovered New XInput
`A8`/`A9` chunk protocol. It does not send speculative packets.

The lighting panel mirrors Space Station's Vader 5 controls: Default, Flow,
Breathing, Feedback, Gradient, Steady, and Off modes; brightness; animated cycle
time; and up to five colors where the selected effect supports them. Flow and
Default retain their device-supplied preset frames, and settings are remembered
per mode while ControlLab remains connected.

Dock lighting is an independent IOKit path matching USB `37D7:6001` on usage
page `FFA0`. It does not require the controller bridge to be connected and does
not route through SDL. ControlLab mirrors Space Station's Off, Solid, Default,
Custom, Diagonal Flow, Breathing, Gradient, Wave Gradient, Rainbow, and Pulse
modes with Space Station's 16-row, 162-pixel preview and animation patterns,
plus matching brightness, cycle-time, direction, and palette controls.
It also reads and applies Space Station's charging and power behavior toggles.
The core API accepts a full 162-pixel frame for custom designs and animations.

The **Configuration** workspace mirrors Space Station's four-profile layout and
its Common, Button, Joystick, Gyro, and Trigger option groups. It includes local
drafts for button assignments, turbo and macros, circularity algorithms,
sensitivity curves, active ranges and dead zones, gyro mapping, trigger ranges,
vibration, sleep time, joystick accuracy, debounce, and center sensitivity.
These drafts persist on the Mac. Applying profile settings to controller memory
remains disabled until the corresponding Vader 5 USB write protocol is captured
and validated; ControlLab does not send guessed configuration packets.

## Architecture

The GUI branch keeps protocol and device access independent from presentation.
Both transports converge on the same `Vader5State` model:

```text
USB receiver -> Vader5Core / direct IOKit --+
                                             +-> Vader5State
Bluetooth   -> SDL3 gamepad backend --------+

Charging Station 2 Pro -> Vader5Core / direct IOKit -> 162-pixel RGB frame
```

- `Vader5Core` — reusable Swift library for report parsing, receiver I/O, and
  optional virtual-gamepad output
- `SDLGamepadC` — narrow SDL3 adapter for standard Bluetooth gamepad state
- `controllab-cli` — small command-line client for diagnostics and automation
- `ControlLab` — native SwiftUI macOS client with connection controls and live
  Space Station-style controller visualization; sticks move in place and every
  standard, macro, rear, shoulder, trigger, Home, and Fn input lights up on the
  controller graphic
- `Vader5CoreTests` — synthetic protocol-report tests

Both clients use the same `Vader5Bridge` API. The bridge supports `.monitor`
mode, which reads and displays the physical controller without a restricted
entitlement, and `.virtualGamepad` mode for signed production builds.

On the Controller screen, choose **Edit layout** to drag each input overlay over
the official controller render. Choose **Done** when aligned. Positions are
saved automatically on the Mac and reused by the other controller previews;
**Reset** restores ControlLab's built-in aligned positions.

## Build

Xcode command-line tools are required. The repository vendors the universal
macOS framework from the official
[SDL 3.4.12 release](https://github.com/libsdl-org/SDL/releases/tag/release-3.4.12),
and `make app` embeds and signs it inside `ControlLab.app`.

```sh
make test       # build the package and run core tests
make cli        # build controllab-cli
make gui        # build the SwiftUI executable
make app        # package build/ControlLab.app
```

Run the monitor-only CLI without the virtual-HID entitlement:

```sh
swift run controllab-cli --monitor --verbose
```

Monitor the paired Xbox-compatible Bluetooth profile:

```sh
swift run controllab-cli --bluetooth --verbose
```

Read the firmware versions currently reported by the connected device:

```sh
swift run controllab-cli --firmware

# Inspect or simulate a downloaded package without opening a HID device
swift run controllab-cli --inspect-firmware /path/to/update.fwpkg
swift run controllab-cli --simulate-firmware /path/to/update.fwpkg
```

Control the Charging Station 2 Pro display directly:

```sh
swift run controllab-cli --dock-status
swift run controllab-cli --dock-config
swift run controllab-cli --dock-color 0060FF 75
swift run controllab-cli --dock-mode gradient
swift run controllab-cli --dock-off
```

Open the packaged GUI:

```sh
open build/ControlLab.app
```

For virtual-gamepad output, sign the executable with a provisioning profile
that contains `com.apple.developer.hid.virtual.device`. A sample entitlement
file is included as `ControlLab.entitlements`. Set `SIGNING_IDENTITY` when packaging
an approved build:

```sh
SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" make app
```

## Protocol layout

Enhanced reports are 32 bytes and begin with `5A A5 EF`:

- bytes 3-10: four signed 16-bit stick axes
- bytes 11-12: D-pad and standard buttons
- bytes 13-14: extra buttons
- bytes 15-16: analog triggers
- bytes 17-22: three-axis gyroscope
- bytes 23-28: three-axis accelerometer

The protocol work was informed by the open-source
[BANANASJIM/flydigi-vader5](https://github.com/BANANASJIM/flydigi-vader5)
Linux driver and verified against physical hardware on macOS.

## License

ControlLab is MIT licensed. SDL3 is distributed under the zlib license; its
license is included at `ThirdPartyNotices/SDL3-LICENSE.txt` and in packaged apps.
The official Vader 5 Pro render is copyright Flydigi and is excluded from the
MIT license; see `ThirdPartyNotices/FLYDIGI-ASSET-NOTICE.md`.
