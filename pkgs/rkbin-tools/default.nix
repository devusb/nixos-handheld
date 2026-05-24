{
  stdenvNoCC,
  lib,
  rkbin,
  qemu-user,
  runtimeShell,
  pkgsCross,
}:

# loaderimage and trust_merger are dynamically linked x86_64 ELFs needing
# /lib64/ld-linux-x86-64.so.2. qemu-x86_64 with QEMU_LD_PREFIX pointing at
# a cross-compiled x86_64 glibc gives them the runtime they need.
let
  ldPrefix = pkgsCross.gnu64.glibc;
in

# Rockchip's proprietary firmware tools (loaderimage, trust_merger). Prebuilt
# x86_64-linux ELFs vendored in rkbin's source. We wrap them with qemu-x86_64
# when building on aarch64 so they're usable as native commands.
#
# Same pattern as nixpkgs.rkboot (pkgs/by-name/rk/rkboot/package.nix), which
# qemu-wraps boot_merger from the same source tree.
stdenvNoCC.mkDerivation {
  pname = "rkbin-tools";
  inherit (rkbin) src version;

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin $out/libexec
    for tool in loaderimage trust_merger; do
      install -Dm755 tools/$tool $out/libexec/$tool
      cat > $out/bin/$tool <<EOF
    #!${runtimeShell}
    ${lib.optionalString stdenvNoCC.hostPlatform.isAarch64 ''
      export QEMU_LD_PREFIX=${ldPrefix}
      exec ${qemu-user}/bin/qemu-x86_64 $out/libexec/$tool "\$@"
    ''}
    ${lib.optionalString stdenvNoCC.hostPlatform.isx86_64 ''
      exec $out/libexec/$tool "\$@"
    ''}
    EOF
      chmod +x $out/bin/$tool
    done

    runHook postInstall
  '';

  meta = {
    description = "Rockchip proprietary firmware tools (loaderimage, trust_merger), qemu-wrapped on non-x86_64";
    homepage = "https://github.com/rockchip-linux/rkbin";
    license = lib.licenses.unfreeRedistributable;
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
}
