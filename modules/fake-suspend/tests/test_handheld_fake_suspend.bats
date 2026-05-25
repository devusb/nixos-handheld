#!/usr/bin/env bats
# Tests for handheld-fake-suspend.sh. The script reads sysfs paths and helper
# binaries from env vars so we can run it against a fake /sys tree.

setup() {
  FAKE_ROOT="$(mktemp -d)"
  export FAKE_ROOT
  export BL_POWER_GLOB="$FAKE_ROOT/sys/class/backlight/*/bl_power"
  export CPU_ONLINE_GLOB="$FAKE_ROOT/sys/devices/system/cpu/cpu*/online"
  export INPUT_DIR="$FAKE_ROOT/sys/class/input"
  export STATE_DIR="$FAKE_ROOT/run/handheld-fake-suspend"
  export PACTL_BIN="$BATS_TEST_DIRNAME/mocks/pactl"
  export EVTEST_BIN="$BATS_TEST_DIRNAME/mocks/evtest"
  export PARK_CORES=0
  export SHUTDOWN_DELAY=0

  mkdir -p "$FAKE_ROOT/sys/class/backlight/backlight0"
  echo 0 > "$FAKE_ROOT/sys/class/backlight/backlight0/bl_power"

  for i in 0 1 2 3; do
    mkdir -p "$FAKE_ROOT/sys/devices/system/cpu/cpu${i}"
    echo 1 > "$FAKE_ROOT/sys/devices/system/cpu/cpu${i}/online"
  done

  # One non-whitelisted input device, used to verify input grabbing
  mkdir -p "$INPUT_DIR/event2/device"
  echo "joypad-rg28xx" > "$INPUT_DIR/event2/device/name"

  mkdir -p "$STATE_DIR"
  : > "$STATE_DIR/pactl.log"
  : > "$STATE_DIR/evtest.log"

  SCRIPT="$BATS_TEST_DIRNAME/../handheld-fake-suspend.sh"
}

teardown() {
  rm -rf "$FAKE_ROOT"
}

@test "suspend blanks the backlight (bl_power=4)" {
  "$SCRIPT" suspend
  [ "$(cat "$FAKE_ROOT/sys/class/backlight/backlight0/bl_power")" = "4" ]
}

@test "resume restores the backlight (bl_power=0)" {
  "$SCRIPT" suspend
  "$SCRIPT" resume
  [ "$(cat "$FAKE_ROOT/sys/class/backlight/backlight0/bl_power")" = "0" ]
}

@test "suspend with PARK_CORES=1 offlines cpu1..N but leaves cpu0 online" {
  PARK_CORES=1 "$SCRIPT" suspend
  [ "$(cat "$FAKE_ROOT/sys/devices/system/cpu/cpu0/online")" = "1" ]
  [ "$(cat "$FAKE_ROOT/sys/devices/system/cpu/cpu1/online")" = "0" ]
  [ "$(cat "$FAKE_ROOT/sys/devices/system/cpu/cpu3/online")" = "0" ]
}

@test "suspend with PARK_CORES=0 (default) leaves cores online" {
  "$SCRIPT" suspend
  [ "$(cat "$FAKE_ROOT/sys/devices/system/cpu/cpu1/online")" = "1" ]
  [ "$(cat "$FAKE_ROOT/sys/devices/system/cpu/cpu3/online")" = "1" ]
}

@test "resume re-onlines cores after park" {
  PARK_CORES=1 "$SCRIPT" suspend
  PARK_CORES=1 "$SCRIPT" resume
  for i in 0 1 2 3; do
    [ "$(cat "$FAKE_ROOT/sys/devices/system/cpu/cpu${i}/online")" = "1" ]
  done
}

@test "suspend writes the active flag file" {
  "$SCRIPT" suspend
  [ -f "$STATE_DIR/fake-suspend-active" ]
}

@test "resume clears the active flag file" {
  "$SCRIPT" suspend
  "$SCRIPT" resume
  [ ! -f "$STATE_DIR/fake-suspend-active" ]
}

@test "pactl is invoked to mute on suspend" {
  "$SCRIPT" suspend
  grep -q "set-sink-mute @DEFAULT_SINK@ true" "$STATE_DIR/pactl.log"
}

@test "pactl is invoked to unmute on resume" {
  "$SCRIPT" suspend
  "$SCRIPT" resume
  grep -q "set-sink-mute @DEFAULT_SINK@ false" "$STATE_DIR/pactl.log"
}

# Note: block_input runs evtest --grab in the background (because real evtest
# blocks forever holding the grab). The mock evtest exits immediately, but its
# log write races the caller — give it a moment to flush before asserting.
@test "evtest --grab is invoked on non-whitelisted input devices during suspend" {
  INPUT_WHITELIST="axp20x-pek" "$SCRIPT" suspend
  sleep 0.2
  grep -q -- "--grab" "$STATE_DIR/evtest.log"
}

@test "whitelisted input devices are NOT grabbed" {
  mkdir -p "$INPUT_DIR/event1/device"
  echo "axp20x-pek" > "$INPUT_DIR/event1/device/name"

  INPUT_WHITELIST="axp20x-pek" "$SCRIPT" suspend
  sleep 0.2

  ! grep -q "/dev/input/event1" "$STATE_DIR/evtest.log"
  grep -q "/dev/input/event2" "$STATE_DIR/evtest.log"
}

# --- handheld-power-button.sh resolve_device unit tests ---

@test "power-button: resolve_device returns event path for matching name" {
  mkdir -p "$INPUT_DIR/event3/device"
  echo "axp20x-pek" > "$INPUT_DIR/event3/device/name"

  result=$(DEVICE_NAME="axp20x-pek" \
           INPUT_DIR="$INPUT_DIR" \
           bash -c '
             source '"$BATS_TEST_DIRNAME"'/../handheld-power-button.sh --source-only
             resolve_device
           ')
  [ "$result" = "/dev/input/event3" ]
}

@test "power-button: resolve_device fails when name not present" {
  run bash -c '
    DEVICE_NAME="not-a-real-device" \
    INPUT_DIR="'"$INPUT_DIR"'" \
    bash -c "
      source '"$BATS_TEST_DIRNAME"'/../handheld-power-button.sh --source-only
      resolve_device
    "
  '
  [ "$status" -ne 0 ]
}
