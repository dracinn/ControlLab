#!/bin/sh
set -eu

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 BUGREPORT_ZIP_OR_BTSNOOP_LOG OUTPUT_DIRECTORY" >&2
    exit 2
fi

input=$1
output_directory=$2
mkdir -p "$output_directory"
capture="$output_directory/btsnoop_hci.log"

case "$input" in
    *.zip)
        # Motorola bug reports may include an empty btsnoop_hci.log alongside
        # the real capture in hci_snoop*.cfa. Select the largest known capture
        # instead of accepting the first matching filename.
        entry=$(unzip -l "$input" | awk '
            $4 ~ /(btsnoop_hci|bluetooth_hci|hci_snoop).*\.(log|cfa)$/ && $1 > largest {
                largest = $1
                capture = $4
            }
            END { print capture }
        ')
        if [ -z "$entry" ]; then
            echo "No Bluetooth HCI snoop log was found in the bug report." >&2
            exit 1
        fi
        unzip -p "$input" "$entry" > "$capture"
        ;;
    *)
        cp "$input" "$capture"
        ;;
esac

capture_size=$(wc -c < "$capture" | tr -d ' ')
if [ "$capture_size" -le 16 ]; then
    echo "The Bluetooth HCI capture contains no packets." >&2
    exit 1
fi

capture_magic=$(od -An -tx1 -N8 "$capture" | tr -d ' \n')
if [ "$capture_magic" != "6274736e6f6f7000" ]; then
    echo "The extracted file is not a btsnoop capture." >&2
    exit 1
fi

echo "Extracted $capture"

if command -v tshark >/dev/null 2>&1; then
    tshark -r "$capture" -Y 'btatt' -w "$output_directory/gatt-only.pcapng"
    tshark -r "$capture" -Y 'btatt.opcode == 0x12 || btatt.opcode == 0x52 || btatt.opcode == 0x1b || btatt.opcode == 0x1d' \
        -T json > "$output_directory/gatt-writes-and-notifications.json"
    echo "Wrote filtered GATT traffic and JSON to $output_directory"
else
    echo "tshark was not found. Open $capture in Wireshark and filter with: btatt"
fi
