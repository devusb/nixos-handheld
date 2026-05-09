{ writeShellScriptBin, portmaster-fhs }:

writeShellScriptBin "portmaster-launch" ''
  set -e
  if [ $# -lt 1 ]; then
    echo "usage: portmaster-launch <path-to-port.sh>" >&2
    exit 1
  fi

  SCRIPT=$1
  if [ ! -f "$SCRIPT" ]; then
    echo "portmaster-launch: not a file: $SCRIPT" >&2
    exit 1
  fi

  # CFW_NAME=NixOS so PortMaster's upstream launchers source our
  # /roms/ports/PortMaster/mod_NixOS.txt for device-specific overrides.
  exec ${portmaster-fhs}/bin/portmaster-run -c "CFW_NAME=NixOS bash '$SCRIPT'"
''
