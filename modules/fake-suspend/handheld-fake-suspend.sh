#!/usr/bin/env bash
# Userspace fake-suspend for handhelds whose SoC lacks working suspend-to-RAM.
# Blanks the backlight, mutes audio, parks cores, grabs non-whitelisted inputs.
# The running game keeps executing so resume is instant.
#
# Adapted from ROCKNIX's rocknix-fake-suspend (GPL-2.0). ROCKNIX-specific
# helpers (get_setting, ledcontrol, swaymsg, weston-dpms, ES HTTP API) are
# stripped — we have no compositor and no equivalent settings store. Paths are
# env-overridable so the script is testable against a fake /sys tree.
set -euo pipefail

# --- Env-overridable paths (defaults are production sysfs/runtime locations) ---
: "${BL_POWER_GLOB:=/sys/class/backlight/*/bl_power}"
: "${CPU_ONLINE_GLOB:=/sys/devices/system/cpu/cpu*/online}"
: "${INPUT_DIR:=/sys/class/input}"
: "${STATE_DIR:=/run/handheld-fake-suspend}"
: "${PACTL_BIN:=pactl}"
: "${EVTEST_BIN:=evtest}"

# --- Tunables from environment ---
: "${PARK_CORES:=0}"
: "${SHUTDOWN_DELAY:=0}"
: "${INPUT_WHITELIST:=}"

ACTIVE_FLAG="${STATE_DIR}/fake-suspend-active"
GRAB_PIDS="${STATE_DIR}/grab-pids"

mkdir -p "${STATE_DIR}"

display_off() {
  for bl in ${BL_POWER_GLOB}; do
    [ -f "${bl}" ] && echo 4 > "${bl}"
  done
}

display_on() {
  for bl in ${BL_POWER_GLOB}; do
    [ -f "${bl}" ] && echo 0 > "${bl}"
  done
}

mute_audio() {
  "${PACTL_BIN}" set-sink-mute @DEFAULT_SINK@ true || true
}

unmute_audio() {
  "${PACTL_BIN}" set-sink-mute @DEFAULT_SINK@ false || true
}

park_cores() {
  [ "${PARK_CORES}" = "1" ] || return 0
  for online in ${CPU_ONLINE_GLOB}; do
    case "${online}" in
      */cpu0/online) ;;  # keep CPU0
      *) [ -f "${online}" ] && echo 0 > "${online}" ;;
    esac
  done
}

unpark_cores() {
  for online in ${CPU_ONLINE_GLOB}; do
    [ -f "${online}" ] && echo 1 > "${online}"
  done
}

# Comma- or colon-separated whitelist match
is_whitelisted() {
  local name="$1"
  local list="${INPUT_WHITELIST//,/ }"
  list="${list//:/ }"
  for w in ${list}; do
    [ "${name}" = "${w}" ] && return 0
  done
  return 1
}

block_input() {
  : > "${GRAB_PIDS}"
  for ev_name_file in "${INPUT_DIR}"/event*/device/name; do
    [ -f "${ev_name_file}" ] || continue
    local name
    name="$(cat "${ev_name_file}")"
    is_whitelisted "${name}" && continue

    # /sys/class/input/eventN/device/name -> /dev/input/eventN
    local evnum
    evnum="$(echo "${ev_name_file}" | sed -E 's|.*/event([0-9]+)/.*|\1|')"
    local dev="/dev/input/event${evnum}"

    "${EVTEST_BIN}" --grab "${dev}" >/dev/null 2>&1 &
    echo $! >> "${GRAB_PIDS}"
  done
}

unblock_input() {
  [ -f "${GRAB_PIDS}" ] || return 0
  while read -r pid; do
    [ -n "${pid}" ] && kill "${pid}" 2>/dev/null || true
  done < "${GRAB_PIDS}"
  rm -f "${GRAB_PIDS}"
}

do_suspend() {
  touch "${ACTIVE_FLAG}"
  display_off
  mute_audio
  park_cores
  block_input
}

do_resume() {
  unblock_input
  unpark_cores
  unmute_audio
  display_on
  rm -f "${ACTIVE_FLAG}"
}

# --- Main dispatch ---
case "${1:-}" in
  suspend) do_suspend ;;
  resume)  do_resume  ;;
  power)
    # Power button toggle: if active, resume; else suspend.
    if [ -f "${ACTIVE_FLAG}" ]; then
      do_resume
    else
      do_suspend
    fi
    ;;
  *)
    echo "Usage: $0 {suspend|resume|power}" >&2
    exit 1
    ;;
esac
