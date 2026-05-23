# PortMaster on R36H — runtime notes

Quirks discovered while getting PortMaster ports to launch and play correctly on the R36H. Most are not visible from the .gptk/.cfg or the gptokeyb2 README — they were found by reading the gptokeyb2 source and tracing port launch scripts.

## `bind_directories` is not defined by PortMaster's core scripts

Many port launch scripts (`/roms/ports/<Port>/*.sh`) call `bind_directories <xdg_dir> <port_conf_dir>` to redirect the engine's writable XDG directory into the port's own `conf/` subdirectory. The script sed-replaces port-specific values (resolution, controls, etc.) into the port's conf, then expects `bind_directories` to make the engine read/write from there.

`bind_directories` is **not** defined in `control.txt`, `device_info.txt`, or any of PortMaster's runtime scripts on the SD card — it's a ROCKNIX/ArkOS-specific helper expected to be supplied by the device CFW. On those CFWs it's typically a `mount --bind`.

Without it:
- The script's sed-modifications go to a path the engine never reads.
- The engine reads its real XDG path (e.g. `~/.local/share/openjo/`) and uses whatever stale state is there.
- On a fresh install the engine writes defaults based on SDL desktop mode detection — which on Mali/Panfrost can pick a wrong-sized "desktop" (e.g. 1920x1152 instead of 640x480), leaving the rendered image truncated to the visible framebuffer.

### Our fix

`pkgs/portmaster-launch` ships a `BASH_ENV` file that defines `bind_directories` as a symlink helper. It runs at the top of every non-interactive bash inside the FHS sandbox, so port scripts get a working implementation before they call it.

The symlink approach can't do bind-mounts inside bwrap, but for the standard use case (engine reads/writes one location) a symlink works identically. The implementation handles the first-time migration case (target dir already populated from a prior run without `bind_directories`) by `cp -an`'ing target into source before replacing target with the symlink. Source wins on conflicts so the port's freshly-sed'd cfg is preserved.

### Spotting the symptom

If a port launches but renders to a small corner of the screen, or only partially fills it, suspect `bind_directories`. Quick check on device:

```bash
ls -la /home/gamer/.local/share/<port_engine_name>/
# If it's a regular dir (not a symlink), bind_directories never ran.
```

To recover from stale state from before the fix:

```bash
rm -rf /home/gamer/.local/share/<port_engine_name>
# Next launch, bind_directories will create the symlink from scratch.
```

## gptokeyb2 tuning for 640x480

Three gotchas in `gptokeyb2` (PortsMaster/gptokeyb2 @ 7100d03) that affect every port's `.gptk` file on this hardware.

### 1. `deadzone_mode` defaults to a buggy axial implementation

`src/analog.c:dz_axial` computes its threshold as `deadzone * fabs(input)`, then checks `|input| < threshold`. Since `deadzone` is normalized to `[0, 1)`, the comparison is always false — the function never zeros anything. `DZ_DEFAULT` falls through to this same path.

Result: `deadzone = N` in a `.gptk` does nothing in the default mode. Stick noise (kernel `fuzz` value) reaches the mouse layer unattenuated.

Workaround: always set `deadzone_mode = scaled_radial` alongside `deadzone`. `dz_scaled_radial` correctly tests `vector_magnitude < deadzone` and re-scales the output above the threshold so movement starts from zero at the boundary.

### 2. `mouse_scale` is an alias for `deadzone_scale`, not a separate sensitivity

In `src/config.c`, both `mouse_scale` and `deadzone_scale` set the same field (`current_state.deadzone_scale`). It's applied as the final multiplier on the analog-derived mouse delta. The default value is 512.

A separate `mouse_slow_scale` (default 50) exists but only applies when a held `mouse_slow` button is pressed — it's not a runtime sensitivity control.

### 3. Default values are tuned for desktop resolutions

`deadzone_scale = 512` × `1000 / mouse_delay_ms = 62 Hz` = ~31,700 px/sec max cursor velocity. Fine on 1920x1080; on 640x480 the cursor crosses the screen ~50× per second at full deflection — unusable.

### Recommended R36H baseline

Drop into the `.gptk` for any PortMaster port with analog-stick-to-mouse mappings:

```
deadzone = 6000
deadzone_mode = scaled_radial
deadzone_triggers = 3000
mouse_scale = 24
mouse_delay = 16
```

Rationale:
- `deadzone = 6000` → ~18% of normalized stick range. The R36H's `singleadc-joypad` reports `fuzz = 32` on a `[-1800, 1800]` axis, which is ~2% noise in SDL-normalized units. 18% is a generous cushion.
- `mouse_scale = 24` → max ~1500 px/sec at full deflection. Crosses 640 px in ~0.4 sec.
- `mouse_delay = 16` keeps polling at 62 Hz (smooth tracking).

Adjust `mouse_scale` ±50% to taste per port.

## Per-game tuning: JK Outcast / Academy

Both ports ship `.gptk` files with `mouse_scale = 8192` (16× the gptokeyb2 default) and no `deadzone` — they were tuned for a different device. Applied edits on device:

```
# /roms/ports/JediOutcast/openjo_sp.aarch64.gptk
# /roms/ports/JediAcademy/openjk_sp.aarch64.gptk
deadzone = 6000
deadzone_mode = scaled_radial
deadzone_triggers = 3000
mouse_scale = 24
mouse_delay = 16
```

JK's own `sensitivity` cvar is an *additional* in-game amplifier on top of the mouse delta. The shipped port cfg has `seta sensitivity "15.562500"` (~3× the engine default of 5). Drop to `5` for sane in-game look:

```
# conf/openjo/base/openjo_sp.cfg
seta sensitivity "5.000000"
```

Already-correct cvars in the shipped Outcast cfg (no edit needed):

- `cg_dynamicCrosshair "1"` — crosshair changes color on target
- `cg_crosshairIdentifyTarget "1"` — friend/foe identification
- `g_saberAutoAim "1"` — lightsaber lock-on (the only autoaim Q3 engines have; blaster aim is purely mouse)
- `g_saberAutoBlocking "1"`

These edits live on the SD card (`/roms/ports/...`), not in the Nix store. They'll be lost if the port is re-downloaded via PortMaster's installer. If this becomes a maintenance burden, the path forward is either a NixOS activation script that drops tuned `.gptk` files into `/roms/ports/` on switch, or a `mod_NixOS.txt` extension that overrides the values via env vars at launch time.
