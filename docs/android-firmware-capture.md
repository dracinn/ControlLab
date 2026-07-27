# Capturing a Flydigi mobile firmware update

This workflow captures Bluetooth traffic from the official Flydigi mobile app
without requiring Windows or root access. It is intended for protocol analysis,
not for enabling firmware writes in ControlLab.

## Before capturing

1. Use an Android phone with **Developer options** enabled.
2. Enable **Bluetooth HCI snoop log** in Developer options, then toggle Bluetooth
   off and on. Some manufacturers require a phone restart.
3. Enable USB debugging and authorize this Mac when prompted.
4. Connect the controller to the official Flydigi mobile app.

An Android bug report contains private system and account information. Keep the
full ZIP local. Do not commit it or attach it to a public issue.

## Capture

Start with a fresh Bluetooth log if the phone provides that option. In the
official app, perform only the update being studied and note the module and
versions before and after. Then run:

```sh
scripts/capture-android-hci.sh captures/android
```

Extract and filter the Bluetooth data:

```sh
scripts/analyze-android-hci.sh captures/android/flydigi-bugreport-TIMESTAMP.zip captures/android/analysis
```

If Wireshark's `tshark` command is installed, the analyzer creates a GATT-only
capture and JSON containing writes, write commands, notifications, and
indications. Otherwise, open `btsnoop_hci.log` in Wireshark and use `btatt` as
the display filter.

## What to record

- controller mode and connection method
- installed and target main, RF, and SI versions
- GATT service and characteristic UUIDs
- the command immediately preceding a disconnect or reboot
- bootloader advertisements and identity changes
- chunk size, sequence numbers, acknowledgements, retry timing, and completion
- behavior after intentionally cancelling before data transfer begins

Do not intentionally remove power during a real mobile update. Recovery and
power-loss testing belongs on spare hardware after the bootloader and rollback
behavior are understood.
