{
  lib,
  fetchFromGitHub,
  linuxPackages_latest,
  linuxManualConfig,
  stdenv,
  flex,
  bison,
  perl,
  runCommand,
  rg28xx-panel-firmware,
  ...
}:
let
  inherit (linuxPackages_latest.kernel) src version modDirVersion;

  # ROCKNIX H700 kernel patch series fetched directly from the
  # distribution repo. Sparse-checkout limits the fetch to the H700
  # patches dir (~400 KiB) instead of pulling the full 500 MiB tree.
  # Bump rev + hash together to roll forward.
  rocknixPatches = fetchFromGitHub {
    owner = "ROCKNIX";
    repo = "distribution";
    rev = "e7b9e9a30440bf6a7eb41dc229a43f4f4a6d4371";
    sparseCheckout = [ "projects/ROCKNIX/devices/H700/patches/linux" ];
    hash = "sha256-XXaEd617pSl4zBzFIU4f3QrM1/nkA7b/DzK5bZTv398=";
  };

  # Applied wholesale. DTS-only patches are redundant at runtime (we
  # use h700-dtb-rocknix) but are kept here so the kernel source tree
  # matches ROCKNIX's. Trim once we've identified which patches are
  # actually doing work.
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
