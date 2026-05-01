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

  exec ${portmaster-fhs}/bin/portmaster-run -c "bash '$SCRIPT'"
''
