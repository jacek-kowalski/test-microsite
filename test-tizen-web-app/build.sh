#!/usr/bin/env bash
#
# Build / install / launch the Tizen API probe web app.
#
# Assumes the Tizen Studio CLI is on PATH on whatever machine you run this on:
#   tizen  -> <tizen-studio>/tools/ide/bin
#   sdb    -> <tizen-studio>/tools
#
# Usage:
#   ./build.sh package                  # build the .wgt
#   ./build.sh install 192.168.1.50     # connect to the TV and install
#   ./build.sh all     192.168.1.50     # package + install + launch
#   ./build.sh log                      # follow the TV's log for probe output
#
#   CERT_PROFILE=myprofile ./build.sh package    # override the signing profile
#
set -euo pipefail

PKG_ID="AdgApiPrb1"
APP_ID="AdgApiPrb1.ApiProbe"
CERT_PROFILE="${CERT_PROFILE:-tvprofile}"

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${PROJECT_DIR}/.buildResult"

COMMAND="${1:-all}"
TV_IP="${2:-${TV_IP:-}}"

# --------------------------------------------------------------------------- #

die() { echo "ERROR: $*" >&2; exit 1; }
step() { echo; echo "==> $*"; }

require() {
    command -v "$1" >/dev/null 2>&1 || die \
"'$1' is not on PATH.

Install Tizen Studio with the TV extension, then add its tools to PATH:
  export PATH=\"\$PATH:<tizen-studio>/tools/ide/bin:<tizen-studio>/tools\"

Download: https://developer.samsung.com/smarttv/develop/tools/tizen-studio.html"
}

# --------------------------------------------------------------------------- #

do_sync() {
    step "Refreshing index.html from ../tizen_api_test_microsite.html"

    if command -v python >/dev/null 2>&1; then
        (cd "$PROJECT_DIR" && python sync_index.py)
    elif command -v python3 >/dev/null 2>&1; then
        (cd "$PROJECT_DIR" && python3 sync_index.py)
    else
        # index.html is committed, so this is only a convenience step.
        echo "python not found - using the committed index.html as-is."
    fi
}

do_package() {
    require tizen
    step "Building web app"
    rm -rf "$BUILD_DIR"
    tizen build-web -- "$PROJECT_DIR"

    step "Packaging .wgt (signing profile: ${CERT_PROFILE})"
    tizen package -t wgt -s "$CERT_PROFILE" -- "$BUILD_DIR" || die \
"Packaging failed.

Most often this means the signing profile '${CERT_PROFILE}' does not exist.
List profiles with:   tizen security-profiles list
Create one in Tizen Studio: Tools > Certificate Manager > Samsung > TV,
which needs your TV's DUID (Menu > Support > About This TV)."

    step "Done"
    find "$BUILD_DIR" -name '*.wgt' -exec ls -la {} \;
}

do_install() {
    require sdb
    require tizen

    if [ -n "$TV_IP" ]; then
        step "Connecting to TV at ${TV_IP}"
        sdb connect "$TV_IP" || die \
"Could not connect to ${TV_IP}.

On the TV: Apps > press 1-2-3-4-5 > Developer mode ON > enter this PC's IP,
then restart the TV. PC and TV must be on the same network."
    fi

    step "Devices"
    sdb devices

    local wgt
    wgt="$(find "$BUILD_DIR" -name '*.wgt' | head -1)"
    [ -n "$wgt" ] || die "No .wgt found. Run './build.sh package' first."

    step "Installing $(basename "$wgt")"
    tizen install -n "$(basename "$wgt")" -- "$(dirname "$wgt")"
}

do_launch() {
    require tizen
    step "Launching ${APP_ID}"
    tizen run -p "$PKG_ID" || die "Launch failed. Is the app installed?"
}

do_log() {
    require sdb
    step "Following TV log (Ctrl+C to stop)"
    echo "Probe output appears here via console.log; JSON dump is on-screen."
    sdb dlog -v time | grep -iE "ConsoleMessage|webapis|sso|adinfo|ApiProbe" || true
}

do_uninstall() {
    require tizen
    step "Uninstalling ${PKG_ID}"
    tizen uninstall -p "$PKG_ID" || true
}

# --------------------------------------------------------------------------- #

case "$COMMAND" in
    sync)      do_sync ;;
    package)   do_sync; do_package ;;
    install)   do_install ;;
    launch)    do_launch ;;
    log)       do_log ;;
    uninstall) do_uninstall ;;
    all)       do_sync; do_package; do_install; do_launch ;;
    *)
        echo "Usage: $0 {sync|package|install|launch|log|uninstall|all} [tv-ip]"
        exit 1
        ;;
esac
