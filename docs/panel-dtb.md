# Generating the Display Panel DTB

The R36H ships with various NV3051D LCD panel variants ("panel lottery"). Each variant needs a different init sequence. The DTB at `boards/r36h/dtb/rk3326-gameconsole-r36s-rocknix.dtb` contains the init sequence for one specific panel variant.

If your R36H has a different panel (display doesn't work, backlight cycles), you'll need to generate a new DTB from a working ArkOS/ArkOS-R3XS SD card.

## Prerequisites

- A working ArkOS SD card for your R36H (boots with working display)
- Python with `fdt` package: `pip install fdt`
- `dtc` (device tree compiler): `nix-shell -p dtc`
- The ohjhas kernel source: `git clone --branch linux-6.12.y-rk3326 https://github.com/ohjhas/linux-stable-rk3326.git`

## Steps

### 1. Get the ArkOS DTB

Mount the ArkOS boot partition and copy `gameconsole-r36s.dtb`:

```bash
sudo mount /dev/sdX1 /mnt
cp /mnt/gameconsole-r36s.dtb /tmp/arkos-panel.dtb
sudo umount /mnt
```

### 2. Extract the panel init sequence

Use ROCKNIX's `importpanel.py`:

```bash
curl -sL "https://raw.githubusercontent.com/ROCKNIX/distribution/next/projects/ROCKNIX/packages/linux-drivers/generic-dsi/scripts/importpanel.py" -o /tmp/importpanel.py
python /tmp/importpanel.py -O dts /tmp/arkos-panel.dtb > /tmp/panel-overlay.dts
```

This outputs a DTS overlay with the `panel_description` property containing your panel's init sequence.

### 3. Build the base DTS

Preprocess the R36S device tree from the kernel source:

```bash
cd /path/to/linux-stable-rk3326
nix-shell -p dtc gcc --run '
  cpp -nostdinc -I include -I arch/arm64/boot/dts -I arch/arm64/boot/dts/rockchip \
    -undef -D__DTS__ -x assembler-with-cpp \
    arch/arm64/boot/dts/rockchip/rk3326-gameconsole-r36s.dts \
    -o /tmp/r36s-base.dts.pp
  dtc -I dts -O dts /tmp/r36s-base.dts.pp -o /tmp/r36s-editable.dts
'
```

### 4. Replace the panel node

In `/tmp/r36s-editable.dts`, find the `internal_display: panel@0` node (search for `panel@0`). Replace the `compatible` and add the `panel_description` from step 2:

```python
python3 -c "
with open('/tmp/r36s-editable.dts') as f:
    dts = f.read()

# Extract panel_description from the overlay
with open('/tmp/panel-overlay.dts') as f:
    overlay = f.read()
import re
panel_desc = re.search(r'panel_description =.*?;', overlay, re.DOTALL).group()

# Find and replace the panel node
start = dts.find('internal_display: panel@0 {')
depth = 0
pos = start
while pos < len(dts):
    if dts[pos] == '{': depth += 1
    elif dts[pos] == '}':
        depth -= 1
        if depth == 0:
            end = pos + 2
            break
    pos += 1

# Build replacement with rocknix generic-dsi compatible
replacement = '''		internal_display: panel@0 {
			reg = <0x00>;
			backlight = <&backlight>;
			reset-gpios = <&gpio3 0x10 0x01>;
			compatible = \"rocknix,generic-dsi\";
			iovcc-supply = <&vcc_lcd>;
			vdd-supply = <&vcc_lcd>;

			''' + panel_desc + '''

			port {
				mipi_in_panel: endpoint {
					remote-endpoint = <&mipi_out_panel>;
					phandle = <0x92>;
				};
			};
		};'''

new_dts = dts[:start] + replacement + dts[end:]
with open('/tmp/r36s-rocknix.dts', 'w') as f:
    f.write(new_dts)
"
```

### 5. Compile the DTB

```bash
nix-shell -p dtc --run "dtc -I dts -O dtb /tmp/r36s-rocknix.dts -o boards/r36h/dtb/rk3326-gameconsole-r36s-rocknix.dtb"
```

### 6. Verify

```bash
nix-shell -p dtc --run "dtc -I dtb -O dts boards/r36h/dtb/rk3326-gameconsole-r36s-rocknix.dtb" | grep "rocknix"
# Should show: compatible = "rocknix,generic-dsi";
```

Rebuild the image and flash.
