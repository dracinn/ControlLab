#!/bin/zsh
set -euo pipefail

repo_dir="${0:A:h:h}"
configuration="${CONFIGURATION:-release}"
app_dir="${repo_dir}/build/ControlLab.app"
binary="${repo_dir}/.build/${configuration}/ControlLab"
sdl_framework="${repo_dir}/Vendor/SDL3.xcframework/macos-arm64_x86_64/SDL3.framework"

cd "${repo_dir}"
swift_build_args=(-c "${configuration}" --product ControlLab)
if [[ "${SWIFTPM_DISABLE_SANDBOX:-0}" == "1" ]]; then
    swift_build_args+=(--disable-sandbox)
fi
swift build "${swift_build_args[@]}"
rm -rf "${app_dir}"
mkdir -p "${app_dir}/Contents/MacOS" "${app_dir}/Contents/Resources/ThirdPartyNotices" \
    "${app_dir}/Contents/Frameworks"
cp "${binary}" "${app_dir}/Contents/MacOS/ControlLab"
cp "${repo_dir}/Resources/Info.plist" "${app_dir}/Contents/Info.plist"
cp "${repo_dir}/Sources/Vader5GUI/Resources/Vader5Pro-Official.png" \
    "${app_dir}/Contents/Resources/Vader5Pro-Official.png"
cp "${repo_dir}/Sources/Vader5GUI/Resources/FlydigiDock2Pro-Official.jpg" \
    "${app_dir}/Contents/Resources/FlydigiDock2Pro-Official.jpg"
cp "${repo_dir}/Sources/Vader5GUI/Resources/FlydigiDock2Pro-Front.png" \
    "${app_dir}/Contents/Resources/FlydigiDock2Pro-Front.png"
cp -R "${sdl_framework}" "${app_dir}/Contents/Frameworks/SDL3.framework"
cp "${repo_dir}/ThirdPartyNotices/SDL3-LICENSE.txt" \
    "${app_dir}/Contents/Resources/ThirdPartyNotices/SDL3-LICENSE.txt"
cp "${repo_dir}/ThirdPartyNotices/FLYDIGI-ASSET-NOTICE.md" \
    "${app_dir}/Contents/Resources/ThirdPartyNotices/FLYDIGI-ASSET-NOTICE.md"
install_name_tool -add_rpath "@executable_path/../Frameworks" \
    "${app_dir}/Contents/MacOS/ControlLab"

if [[ -n "${SIGNING_IDENTITY:-}" ]]; then
    codesign --force --options runtime --timestamp --sign "${SIGNING_IDENTITY}" \
        "${app_dir}/Contents/Frameworks/SDL3.framework"
    codesign --force --options runtime --timestamp --sign "${SIGNING_IDENTITY}" \
        --entitlements "${repo_dir}/ControlLab.entitlements" "${app_dir}"
else
    codesign --force --sign - "${app_dir}/Contents/Frameworks/SDL3.framework"
    codesign --force --sign - "${app_dir}"
fi

print "Built ${app_dir}"
