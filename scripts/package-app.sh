#!/bin/zsh
set -euo pipefail

repo_dir="${0:A:h:h}"
configuration="${CONFIGURATION:-release}"
app_dir="${repo_dir}/build/Vader5.app"
binary="${repo_dir}/.build/${configuration}/Vader5GUI"

cd "${repo_dir}"
swift_build_args=(-c "${configuration}" --product Vader5GUI)
if [[ "${SWIFTPM_DISABLE_SANDBOX:-0}" == "1" ]]; then
    swift_build_args+=(--disable-sandbox)
fi
swift build "${swift_build_args[@]}"
rm -rf "${app_dir}"
mkdir -p "${app_dir}/Contents/MacOS" "${app_dir}/Contents/Resources"
cp "${binary}" "${app_dir}/Contents/MacOS/Vader5GUI"
cp "${repo_dir}/Resources/Info.plist" "${app_dir}/Contents/Info.plist"

if [[ -n "${SIGNING_IDENTITY:-}" ]]; then
    codesign --force --options runtime --timestamp --sign "${SIGNING_IDENTITY}" \
        --entitlements "${repo_dir}/Vader5.entitlements" "${app_dir}"
else
    codesign --force --sign - "${app_dir}"
fi

print "Built ${app_dir}"
