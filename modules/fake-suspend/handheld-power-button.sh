#!/usr/bin/env bash
# Watch a named input device for KEY_POWER release events and invoke
# handheld-fake-suspend on each press. The device is identified by its
# input-class name (e.g. "axp20x-pek") and resolved to /dev/input/eventN
# at startup, with a brief retry loop to ride out udev races at boot.
set -euo pipefail

: "${INPUT_DIR:=/sys/class/input}"
: "${EVTEST_BIN:=evtest}"
: "${FAKE_SUSPEND_BIN:=handheld-fake-suspend}"

resolve_device() {
  for ev_name_file in "${INPUT_DIR}"/event*/device/name; do
    [ -f "${ev_name_file}" ] || continue
    if [ "$(cat "${ev_name_file}" 2>/dev/null)" = "${DEVICE_NAME}" ]; then
      local evnum
      evnum="$(echo "${ev_name_file}" | sed -E 's|.*/event([0-9]+)/.*|\1|')"
      echo "/dev/input/event${evnum}"
      return 0
    fi
  done
  return 1
}

# When sourced for unit tests, stop here so the test can call resolve_device
# without entering the main event loop. `return` from outside a function only
# works in a sourced file — when sourced this exits the source cleanly; when
# run directly this is a no-op and we exit the script below.
if [ "${1:-}" = "--source-only" ]; then
  # shellcheck disable=SC2317  # reachable when sourced
  { return 0 2>/dev/null; } || exit 0
fi

DEVICE_NAME="${1:?device name (e.g. axp20x-pek) required as first arg}"

for _ in $(seq 1 50); do
  if DEVICE_PATH="$(resolve_device)"; then
    break
  fi
  sleep 0.1
done

if [ -z "${DEVICE_PATH:-}" ]; then
  echo "Power button '${DEVICE_NAME}' not found under ${INPUT_DIR}" >&2
  exit 1
fi

# Read evtest output line by line; KEY_POWER value 0 = release.
"${EVTEST_BIN}" "${DEVICE_PATH}" | while read -r line; do
  if [[ "${line}" == *"KEY_POWER"* && "${line}" == *"value 0"* ]]; then
    "${FAKE_SUSPEND_BIN}" power
  fi
done
