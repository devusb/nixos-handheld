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
  writeShellApplication,
  git,
  curl,
  gnused,
  gnugrep,
  gawk,
  coreutils,
  nix,
  ...
}:
let
  # Kernel version pinned to match the ROCKNIX patch rev below — their
  # patches target this exact tree, so the two move as a pair. Fetched
  # directly rather than via a nixpkgs kernel attr so an EOL series being
  # dropped from nixpkgs can't break the build.
  version = "7.0.11";
  modDirVersion = "7.0.11";
  src = fetchurl {
    url = "mirror://kernel/linux/kernel/v7.x/linux-${version}.tar.xz";
    hash = "sha256-5WyDVt2gETamBBxu+DK9Dsmb0tNd/5eDKqXsEO0BQwQ=";
  };

  # ROCKNIX H700 kernel patch series.
  rocknixPatches = fetchFromGitHub {
    owner = "ROCKNIX";
    repo = "distribution";
    rev = "2b61fed6221ba5a004ee9854cfe80a19f127bacd";
    sparseCheckout = [ "projects/ROCKNIX/devices/H700/patches/linux" ];
    hash = "sha256-SQd1zOI2YRS/6haW54wLsZsUndK/gGK3LfcfgZgt3Pg=";
  };

  # Applied wholesale. DTS-only patches are redundant at runtime
  # (the DTB build pulls the same DTS via the patched kernel source),
  # but kept here so the kernel source tree matches upstream's
  # expectation for the rest of the patches.
  patches = map (n: "${rocknixPatches}/projects/ROCKNIX/devices/H700/patches/linux/${n}") [
    "0002-rg35xx-enable-HDMI-LCD.patch"
    "0003-Update-sun8i_tcon_top.c.patch"
    "0007-rg35xx-add-GPU-opp.patch"
    "0008-sun20i-add-pwm-driver.patch"
    "0009-h616-add-pwm-node.patch"
    "0010-rg35xx-enable-pwm-backlight.patch"
    "0040-Revert-usb-musb-Fix-hardware-lockup-on-first-Rx-endp.patch"
    "0110-v2_20250226_kikuchan98_drm_panel_add_generic_mipi_panel_driver.patch"
    "0111-rg35xx-2024-use-panel-mipi-dpi-spi-driver.patch"
    "0124-battery-name.patch"
    "0126-20241018_macroalpha82_rg35xx_add_additional_hardware_support.patch"
    "0127-enable-mmc1-for-RG35XX-2024.patch"
    "0140-rg35xx-2024-use-rocknix-joypad-driver.patch"
    "0150-add-forcefeedback.patch"
    "0151-phy-fix-OTG-host-mode.patch"
    "0152-rg35xx-2024-enable-usb-otg.patch"
    "0153-enable-rgb-leds.patch"
    "0154-rocknix-dt-id.patch"
    "0155-sun4i-set-rgb-connector-as-DSI.patch"
    "0200-h700-update-opps.patch"
    "0204-dts-Enable-hdmi-sound.patch"
    "0901-dts-rg35xx-2024-fix-led-1-color.patch"
  ];

  # Patched source: stdenv handles unpack + patchPhase natively. Patches
  # must apply BEFORE the configfile derivation runs `make defconfig` —
  # otherwise patch-added Kconfig symbols (DRM_PANEL_MIPI, PWM_SUN20I,
  # etc.) are unknown and silently dropped from .config. postPatch
  # stages the panel firmware blob where CONFIG_EXTRA_FIRMWARE_DIR
  # points so the build bakes it into the kernel image.
  patchedSrc = stdenv.mkDerivation {
    name = "linux-h700-${version}-patched";
    inherit src patches;
    postPatch = ''
      mkdir -p external-firmware/panels
      cp ${rg28xx-panel-firmware}/lib/firmware/panels/anbernic,rg28xx-panel.panel \
         external-firmware/panels/
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

        cp ${./h700_defconfig} arch/arm64/configs/h700_defconfig

        make h700_defconfig
        cp .config $out
      '';

  # Bumps the ROCKNIX rev and the coupled kernel version+hash together,
  # deriving the kernel version from ROCKNIX's package.mk H700 case.
  updateScript = writeShellApplication {
    name = "update-linux-h700";
    runtimeInputs = [
      git
      curl
      gnused
      gnugrep
      gawk
      coreutils
      nix
    ];
    text = builtins.readFile ./update.sh;
  };
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
      updateScript = [ (lib.getExe updateScript) ];
    };
  })
