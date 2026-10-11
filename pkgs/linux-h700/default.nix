{
  lib,
  fetchFromGitHub,
  fetchurl,
  linuxManualConfig,
  stdenv,
  flex,
  bison,
  perl,
  runCommand,
  rg28xx-panel-firmware,
  wireless-regdb,
  ...
}:
let
  # The H700 PKG_VERSION in ROCKNIX's
  # projects/ROCKNIX/packages/linux/package.mk. Fetched directly rather than
  # via a nixpkgs kernel attr so an EOL series being dropped from nixpkgs
  # cannot break the build.
  version = "7.2";
  modDirVersion = "7.2.0";
  src = fetchurl {
    url = "mirror://kernel/linux/kernel/v7.x/linux-${version}.tar.xz";
    hash = "sha256-+f7z0UwN9TgZAm9L50RZg1wqCw3L9bW72eoZ8IKUArM=";
  };

  # ROCKNIX H700 kernel sources: shared and device patches, device trees, and
  # kernel config. Pinned to a rev on their default branch.
  rocknix = fetchFromGitHub {
    owner = "ROCKNIX";
    repo = "distribution";
    rev = "abfdf71dcdd60312101440edc32d62f4d1e55eb8";
    sparseCheckout = [
      "projects/ROCKNIX/packages/linux/patches"
      "projects/ROCKNIX/devices/H700/patches/linux"
      "projects/ROCKNIX/devices/H700/linux"
    ];
    hash = "sha256-5qAz2kqb7QWMzpwVFduBHRvcmWRutRtyaikeY6MHYho=";
  };

  rocknixLinux = "${rocknix}/projects/ROCKNIX/packages/linux/patches";
  rocknixH700 = "${rocknix}/projects/ROCKNIX/devices/H700";

  # Version-specific patch directories ROCKNIX applies for H700: any the H700
  # case adds to PKG_PATCH_DIRS, then the one named exactly after PKG_VERSION.
  versionPatchDirs = [ "7.2" ];

  # Patch directories in the order ROCKNIX's scripts/unpack applies them for H700.
  patchDirs = [
    "${rocknixLinux}/mainline"
  ]
  ++ map (d: "${rocknixLinux}/${d}") versionPatchDirs
  ++ [ "${rocknixH700}/patches/linux" ];

  excludedPatches = [ ];

  # Options layered over ROCKNIX's config.
  localConfig = {
    USB_ETH = "m";
  };

  patchedSrc = stdenv.mkDerivation {
    name = "linux-h700-${version}-patched";
    inherit src;
    patchPhase = ''
      runHook prePatch
      for dir in ${lib.escapeShellArgs patchDirs}; do
        [ -d "$dir" ] || { echo "missing patch directory: $dir" >&2; exit 1; }
        for p in "$dir"/*.patch; do
          [ -e "$p" ] || continue
          case " ${toString excludedPatches} " in
            *" $(basename "$p") "*) echo "skipping $p"; continue ;;
          esac
          echo "applying $p"
          patch -p1 --no-backup-if-mismatch < "$p"
        done
      done
      runHook postPatch
    '';
    postPatch = ''
      cp -r ${rocknixH700}/linux/dts/. arch/arm64/boot/dts/
      chmod -R u+w arch/arm64/boot/dts

      mkdir -p external-firmware/panels
      cp ${rg28xx-panel-firmware}/lib/firmware/panels/anbernic,rg28xx-panel.panel \
         external-firmware/panels/
      cp ${wireless-regdb}/lib/firmware/regulatory.db{,.p7s} external-firmware/
    '';
    dontConfigure = true;
    dontBuild = true;
    installPhase = "cp -r . $out";
  };

  configfile =
    runCommand "linux-h700-config"
      {
        nativeBuildInputs = [
          stdenv.cc
          flex
          bison
          perl
        ];
      }
      ''
        cp -r ${patchedSrc} linux-src
        chmod -R u+w linux-src
        cd linux-src

        cp ${rocknixH700}/linux/linux.aarch64.conf .config
        scripts/config \
          --set-str INITRAMFS_SOURCE "" \
          --set-str DEFAULT_HOSTNAME "" \
          --set-str EXTRA_FIRMWARE_DIR "external-firmware" \
          --set-str EXTRA_FIRMWARE "$(cd external-firmware && find . -type f | sed 's|^\./||' | sort | xargs)" \
          ${lib.concatStringsSep " " (lib.mapAttrsToList (k: v: "--set-val ${k} ${v}") localConfig)}
        make olddefconfig

        ${lib.concatStringsSep "\n" (
          lib.mapAttrsToList (k: v: ''
            grep -qx 'CONFIG_${k}=${v}' .config || { echo "CONFIG_${k}=${v} did not survive olddefconfig"; exit 1; }
          '') localConfig
        )}
        cp .config $out
      '';
in
(linuxManualConfig {
  src = patchedSrc;
  inherit
    version
    modDirVersion
    configfile
    ;
  allowImportFromDerivation = true;
  extraMeta.branch = lib.versions.majorMinor version;
}).overrideAttrs
  (old: {
    passthru = (old.passthru or { }) // {
      features = { };
    };
  })
