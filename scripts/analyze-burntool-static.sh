#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 --input-dir DIR --ghidra-home DIR --output-dir DIR" >&2
  exit 2
}

input_dir=
ghidra_home=
output_dir=

while (($#)); do
  case "$1" in
    --input-dir)
      (($# >= 2)) || usage
      input_dir=$2
      shift 2
      ;;
    --ghidra-home)
      (($# >= 2)) || usage
      ghidra_home=$2
      shift 2
      ;;
    --output-dir)
      (($# >= 2)) || usage
      output_dir=$2
      shift 2
      ;;
    *)
      usage
      ;;
  esac
done

[[ -n "$input_dir" && -n "$ghidra_home" && -n "$output_dir" ]] || usage
[[ -d "$input_dir" ]] || { echo "Input directory not found: $input_dir" >&2; exit 1; }
[[ -x "$ghidra_home/support/analyzeHeadless" ]] ||
  { echo "Ghidra analyzeHeadless not found under: $ghidra_home" >&2; exit 1; }

burntool="$input_dir/BurnTool.exe"
libburn="$input_dir/libburn.dll"
[[ -f "$burntool" && -f "$libburn" ]] ||
  { echo "Input directory must contain BurnTool.exe and libburn.dll" >&2; exit 1; }

expected_burntool=31d424b7f1f083f9a45f000a907d87bb84abda3b394fbeff8adf5a0b812dbe76
expected_libburn=dd67d22d6e0fe7da2a087cdd623e8a1fee93000b96d9f089ad234dbd09533e43
actual_burntool=$(shasum -a 256 "$burntool" | awk '{print $1}')
actual_libburn=$(shasum -a 256 "$libburn" | awk '{print $1}')

[[ "$actual_burntool" == "$expected_burntool" ]] ||
  { echo "Refusing unknown BurnTool.exe hash: $actual_burntool" >&2; exit 1; }
[[ "$actual_libburn" == "$expected_libburn" ]] ||
  { echo "Refusing unknown libburn.dll hash: $actual_libburn" >&2; exit 1; }

mkdir -p "$output_dir"
metadata="$output_dir/metadata.txt"
{
  file "$burntool" "$libburn"
  shasum -a 256 "$burntool" "$libburn"
  /usr/bin/objdump -p "$burntool"
  /usr/bin/objdump -p "$libburn"
} > "$metadata"

project_parent="$output_dir/ghidra-project"
mkdir -p "$project_parent"
project_name="ControlLabBurn-$(date -u +%Y%m%dT%H%M%SZ)"
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")/ghidra" && pwd)

# Keep Ghidra from recursively importing unrelated DLLs beside the installed
# updater. The copies remain in the caller-selected analysis output directory.
staged_input="$output_dir/verified-input"
mkdir -p "$staged_input"
cp "$burntool" "$staged_input/BurnTool.exe"
cp "$libburn" "$staged_input/libburn.dll"

analysis_user_home="$output_dir/ghidra-user"
mkdir -p "$analysis_user_home"
export _JAVA_OPTIONS="-Duser.home=$analysis_user_home"

"$ghidra_home/support/analyzeHeadless" \
  "$project_parent" "$project_name" \
  -import "$staged_input/BurnTool.exe" "$staged_input/libburn.dll" \
  -max-cpu 6 \
  -analysisTimeoutPerFile 900 \
  -scriptPath "$script_dir" \
  -postScript ExportFirmwareAnalysis.java "$output_dir" \
  -log "$output_dir/ghidra.log" \
  -scriptlog "$output_dir/ghidra-script.log"

echo "Static analysis complete: $output_dir"
