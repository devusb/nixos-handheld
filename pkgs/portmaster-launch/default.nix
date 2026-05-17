{
  writeShellScriptBin,
  writeText,
  portmaster-fhs,
}:

let
  # PortMaster's device_info.txt sets CFW_NAME by greping /etc/os-release for
  # `NAME="..."` (quoted). NixOS writes `NAME=NixOS` (unquoted), so the regex
  # misses and CFW_NAME ends up empty — meaning `mod_${CFW_NAME}.txt` resolves
  # to `mod_.txt` and our NixOS overrides are never sourced. BASH_ENV runs
  # this snippet at startup of every non-interactive bash, marking CFW_NAME
  # readonly so device_info.txt's clobber silently no-ops.
  bashEnv = writeText "portmaster-launch-bash-env" ''
    declare -rx CFW_NAME=NixOS
  '';
in
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

  exec ${portmaster-fhs}/bin/portmaster-run -c "BASH_ENV=${bashEnv} bash \"\$0\"" "$SCRIPT"
''
