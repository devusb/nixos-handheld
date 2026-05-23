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
  #
  # bind_directories is a ROCKNIX/ArkOS helper that port launchers call to
  # redirect the engine's XDG dir into the port's conf/save dir. Upstream
  # implements it with mount --bind; we use a symlink so it works inside the
  # bwrap FHS sandbox. Without this, port launchers that sed the port-side
  # cfg (e.g. Jedi Outcast forcing 640x480) are no-ops because the engine
  # actually reads its default XDG path.
  bashEnv = writeText "portmaster-launch-bash-env" ''
    declare -rx CFW_NAME=NixOS

    bind_directories() {
      local target=$1
      local source=$2
      [ -z "$target" ] || [ -z "$source" ] && return 0
      mkdir -p "$source"
      if [ -L "$target" ]; then
        ln -snf "$source" "$target"
        return 0
      fi
      if [ -d "$target" ]; then
        cp -an "$target"/. "$source"/ 2>/dev/null || true
        rm -rf "$target"
      fi
      mkdir -p "$(dirname "$target")"
      ln -snf "$source" "$target"
    }
    export -f bind_directories
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
