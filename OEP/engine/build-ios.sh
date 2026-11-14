#!/usr/bin/env bash
# OEP - iOS build driver.
#
# Fetches the pinned upstream sources, applies the OEP patches and drives the
# krkrz_ios CMake/Xcode build with the launcher sources added to the engine app.
#
#   ./build-ios.sh deps            clone + patch only
#   ./build-ios.sh configure       generate config + CMake project (simulator)
#   ./build-ios.sh build           build for the iOS Simulator (host arch)
#   ./build-ios.sh build-device    build for a device (arm64)
#   ./build-ios.sh archive         signed archive (needs DEVELOPMENT_TEAM)
#   ./build-ios.sh ipa             signed IPA via the krkrz_ios export flow
#   ./build-ios.sh ipa-unsigned    unsigned IPA (Payload/ zip, must be re-signed)
#
# Environment:
#   VCPKG_ROOT        required by the krkrz_ios toolchain
#   DEVELOPMENT_TEAM  Apple Team ID (signed archive / IPA only)
#   SDK               simulator (default) | device
#   CONFIG            Debug (default) | Release
#   OEP_WORK_DIR      build workspace (default: OEP/engine/.work)
#
set -euo pipefail

ENGINE_DIR="$(cd "$(dirname "$0")" && pwd)"
OEP_DIR="$(cd "$ENGINE_DIR/.." && pwd)"
IOS_APP_DIR="$OEP_DIR/ios"
WORK="${OEP_WORK_DIR:-$ENGINE_DIR/.work}"
SDK="${SDK:-simulator}"
CONFIG="${CONFIG:-Debug}"
PATCH_DIR="$ENGINE_DIR/patches"

KRKRZ_DEV="$WORK/krkrz_dev"
KRKRZ_IOS="$WORK/krkrz_ios"
GEN_DIR="$WORK/generated"
BUILD_DIR="$WORK/build-$SDK"

log() { printf '\033[1;35m[OEP]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[OEP] error:\033[0m %s\n' "$*" >&2; exit 1; }

pin() {
    python3 - "$1" "$2" <<'PY'
import json, sys
pins = json.load(open(sys.argv[1], encoding="utf-8"))
value = pins
for key in sys.argv[2].split("."):
    value = value[key]
print(value)
PY
}

fetch_commit() {
    local url="$1" commit="$2" dir="$3" recursive="${4:-0}"
    if [ -d "$dir/.git" ]; then
        log "reusing $dir"
        git -C "$dir" fetch --depth 1 origin "$commit" >/dev/null 2>&1 || true
    else
        log "cloning $url @ ${commit:0:10}"
        mkdir -p "$dir"
        git -C "$dir" init -q
        git -C "$dir" remote add origin "$url"
        git -C "$dir" fetch --depth 1 origin "$commit"
    fi
    git -C "$dir" checkout -q "$commit"
    if [ "$recursive" = "1" ]; then
        log "updating submodules (this fetches the engine plugins)"
        git -C "$dir" submodule update --init --recursive
    fi
}

apply_patch() {
    local dir="$1" patch="$2"
    if [ ! -f "$patch" ]; then die "missing patch $patch"; fi
    if git -C "$dir" apply --reverse --check "$patch" >/dev/null 2>&1; then
        log "patch already applied: $(basename "$patch")"
        return
    fi
    if ! git -C "$dir" apply --check "$patch" 2>/dev/null; then
        # tolerate whitespace / CRLF drift between the patch and the checkout
        git -C "$dir" apply --check --ignore-whitespace "$patch" ||
            die "patch does not apply: $(basename "$patch")"
        git -C "$dir" apply --ignore-whitespace "$patch"
    else
        git -C "$dir" apply "$patch"
    fi
    log "applied $(basename "$patch")"
}

require_macos() {
    [ "$(uname -s)" = "Darwin" ] || die "iOS builds need macOS with Xcode"
}

deps() {
    local pins="$ENGINE_DIR/pins.json"
    local dev_url dev_commit core_commit ios_url ios_commit
    dev_url="$(pin "$pins" krkrz_dev.url)"
    dev_commit="$(pin "$pins" krkrz_dev.commit)"
    core_commit="$(pin "$pins" krkrz_core.commit)"
    ios_url="$(pin "$pins" krkrz_ios.url)"
    ios_commit="$(pin "$pins" krkrz_ios.commit)"

    require_macos
    mkdir -p "$WORK"

    fetch_commit "$dev_url" "$dev_commit" "$KRKRZ_DEV" 1
    # The engine core is a submodule; make sure it is exactly the pinned commit.
    if [ -d "$KRKRZ_DEV/src/core/.git" ] || [ -f "$KRKRZ_DEV/src/core/.git" ]; then
        git -C "$KRKRZ_DEV/src/core" fetch --depth 1 origin "$core_commit" >/dev/null 2>&1 || true
        git -C "$KRKRZ_DEV/src/core" checkout -q "$core_commit"
        log "krkrz core at $(git -C "$KRKRZ_DEV/src/core" rev-parse --short HEAD)"
    else
        die "krkrz_dev/src/core is missing (submodule update failed)"
    fi

    fetch_commit "$ios_url" "$ios_commit" "$KRKRZ_IOS"
    apply_patch "$KRKRZ_DEV/src/core" "$PATCH_DIR/0001-krkrz-core-oep-host.patch"
    apply_patch "$KRKRZ_IOS" "$PATCH_DIR/0002-krkrz-ios-oep-app.patch"
    # memfile (submodule): (tTJSVariant)NULL is ambiguous on 64-bit non-Windows
    apply_patch "$KRKRZ_DEV/src/plugins/memfile" "$PATCH_DIR/0003-memfile-variant-null.patch"
}

generate_config() {
    require_macos
    [ -d "$KRKRZ_IOS" ] || die "run '$0 deps' first"
    [ -n "${VCPKG_ROOT:-}" ] || die "VCPKG_ROOT is not set (see docs/build.md)"
    log "generating the test game audio (bundled with the app)"
    python3 "$OEP_DIR/testdata/build-testdata.py" >/dev/null ||         log "warning: test data generation failed (the app will still build)"

    log "generating app config"
    (
        cd "$KRKRZ_IOS"
        PROJECT_DIR="$ENGINE_DIR" \
        APP_CONFIG_FILE="$ENGINE_DIR/ios-config.json" \
        OUT_DIR="$GEN_DIR" \
        KRKRZ_BASE="$WORK" \
        python3 -I scripts/gen-config.py
    )
}

configure() {
    generate_config
    local sysroot arch triplet
    if [ "$SDK" = "device" ]; then
        sysroot="iphoneos"; arch="arm64"; triplet="arm64-ios-krkrz"
    else
        sysroot="iphonesimulator"
        arch="$(uname -m)"
        if [ "$arch" = "x86_64" ]; then
            triplet="x64-ios-simulator-krkrz"
        else
            triplet="arm64-ios-simulator-krkrz"
        fi
    fi
    log "configure ($sysroot/$arch, $CONFIG)"
    # CMake 4 removed compatibility with cmake_minimum_required(<3.5); several
    # upstream dependencies still declare older minimums.
    cmake -S "$KRKRZ_IOS" -B "$BUILD_DIR" -G Xcode \
        -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
        -DCMAKE_SYSTEM_NAME=iOS \
        -DCMAKE_OSX_SYSROOT="$sysroot" \
        -DCMAKE_OSX_ARCHITECTURES="$arch" \
        -DCMAKE_TOOLCHAIN_FILE="$VCPKG_ROOT/scripts/buildsystems/vcpkg.cmake" \
        -DVCPKG_TARGET_TRIPLET="$triplet" \
        -DMYAPP_DIR="$GEN_DIR" \
        -DOEP_APP_DIR="$IOS_APP_DIR"
}

build() {
    [ -d "$BUILD_DIR/krkrz_ios.xcodeproj" ] || configure
    local sysroot arch
    if [ "$SDK" = "device" ]; then sysroot="iphoneos"; arch="arm64"; else sysroot="iphonesimulator"; arch="$(uname -m)"; fi
    log "building ($CONFIG, $sysroot)"
    xcodebuild -project "$BUILD_DIR/krkrz_ios.xcodeproj" \
        -target krkrz -configuration "$CONFIG" -sdk "$sysroot" -arch "$arch" \
        build
}

archive() {
    [ -n "${DEVELOPMENT_TEAM:-}" ] || die "DEVELOPMENT_TEAM is required for a signed archive"
    rm -rf "$ENGINE_DIR/archive"
    xcodebuild -project "$BUILD_DIR/krkrz_ios.xcodeproj" -scheme krkrz \
        -configuration Release -destination "generic/platform=iOS" \
        -archivePath "$ENGINE_DIR/archive/OEP.xcarchive" \
        -allowProvisioningUpdates archive
}

ipa() {
    archive
    local export="$ENGINE_DIR/ExportOptions.plist"
    python3 -I "$KRKRZ_IOS/scripts/export-options.py" development "$DEVELOPMENT_TEAM" "$export"
    rm -rf "$ENGINE_DIR/ipa"
    xcodebuild -exportArchive -archivePath "$ENGINE_DIR/archive/OEP.xcarchive" \
        -exportPath "$ENGINE_DIR/ipa" -exportOptionsPlist "$export" \
        -allowProvisioningUpdates
    ls -l "$ENGINE_DIR/ipa"
}

ipa_unsigned() {
    generate_config
    local dist_dir="$WORK/build-dist"
    log "configuring an unsigned device build"
    cmake -S "$KRKRZ_IOS" -B "$dist_dir" -G Xcode \
        -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
        -DCMAKE_SYSTEM_NAME=iOS \
        -DCMAKE_OSX_SYSROOT=iphoneos \
        -DCMAKE_OSX_ARCHITECTURES=arm64 \
        -DCMAKE_TOOLCHAIN_FILE="$VCPKG_ROOT/scripts/buildsystems/vcpkg.cmake" \
        -DVCPKG_TARGET_TRIPLET=arm64-ios-krkrz \
        -DMYAPP_DIR="$GEN_DIR" \
        -DOEP_APP_DIR="$IOS_APP_DIR"
    xcodebuild -project "$dist_dir/krkrz_ios.xcodeproj" -target krkrz \
        -configuration Release -sdk iphoneos -arch arm64 \
        CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
        build
    local app
    app="$(find "$dist_dir" -name 'krkrz.app' -type d | head -1)"
    [ -n "$app" ] || die "built .app not found"
    rm -rf "$ENGINE_DIR/ipa-unsigned"
    mkdir -p "$ENGINE_DIR/ipa-unsigned/Payload"
    cp -R "$app" "$ENGINE_DIR/ipa-unsigned/Payload/"
    (cd "$ENGINE_DIR/ipa-unsigned" && zip -qry "OEP-unsigned.ipa" Payload)
    log "unsigned IPA: $ENGINE_DIR/ipa-unsigned/OEP-unsigned.ipa"
    log "it must be signed (Sideloadly / AltStore / your own certificate) before installing"
}

case "${1:-build}" in
    deps) deps ;;
    configure) configure ;;
    build) deps; build ;;
    build-device) SDK=device deps; SDK=device configure; SDK=device build ;;
    archive) deps; archive ;;
    ipa) deps; ipa ;;
    ipa-unsigned) deps; ipa_unsigned ;;
    *) die "unknown command '$1' (deps|configure|build|build-device|archive|ipa|ipa-unsigned)" ;;
esac
