# Standalone DTS Compilation Design

## Problem

Currently, our custom `rk3326-r36s.dts` is baked into the kernel source tree at build time:

- `pkgs/kernel-rk3326/default.nix` copies the `.dts` into `arch/arm64/boot/dts/rockchip/` via `postPatch`
- A Makefile patch (`patches/0001-add-r36s-to-makefile.patch`) adds it to the kernel's DTB build list
- The resulting `.dtb` comes out of the kernel build under `arch/arm64/boot/dts/rockchip/`
- `hardware.deviceTree.filter = "*rk3326-r36s.dtb"` picks it up from the kernel output

Consequences:
- **Every DTS change = full kernel rebuild** (~5 min on remote builder)
- **Fragile Makefile patching** — already bitten us once
- **Tight coupling** — kernel package knows about our device
- **Iteration pain** — most debugging is DTS-level (panel timings, pinctrl, etc.)

## Solution

Compile the DTS to DTB with `dtc` as a standalone derivation. NixOS's `hardware.deviceTree` module supports this directly via `dtbSource`.

### How it works

1. **New package** `pkgs/rk3326-dtb` runs `cpp` (for `#include` expansion) then `dtc` on our `.dts`
2. Produces a directory matching the layout NixOS expects: `$out/rockchip/rk3326-r36s.dtb`
3. `hardware.deviceTree.dtbSource = pkgs.rk3326-dtb` tells NixOS to use that directory
4. `hardware.deviceTree.name = "rockchip/rk3326-r36s.dtb"` selects our DTB
5. Kernel package becomes just a kernel — no DTS patching, no Makefile patch

### Include dependencies

Our DTS uses:
- `#include <dt-bindings/...>` — provided by kernel source at `include/`
- `#include "rk3326.dtsi"` — provided by kernel source at `arch/arm64/boot/dts/rockchip/`

Both come from the kernel source tarball. We can reference `pkgs.linux-rk3326.src` (or `linuxPackages_latest.kernel.src`) in the new package. Since the kernel source is already fetched, no extra download.

### The `cpp` + `dtc` pipeline

```bash
cpp -nostdinc -undef -x assembler-with-cpp \
    -I <kernel-src>/include \
    -I <kernel-src>/arch/arm64/boot/dts \
    -I <kernel-src>/arch/arm64/boot/dts/rockchip \
    rk3326-r36s.dts | \
dtc -I dts -O dtb -o rk3326-r36s.dtb
```

This is the same invocation the kernel's own Makefile uses to compile DTS files (see `scripts/Makefile.lib` in the kernel tree).

## Trade-offs

**Wins:**
- DTS rebuild: ~5 min → ~1 s
- **Kernel package becomes handheld-agnostic** — it's just an RK3326 kernel with the right driver config. Any RK3326-based device (R36S, R36H, RG351, ODROID-GO2/3, etc.) can share it and just provide its own DTB package.
- No more Makefile patching
- Easier to test panel tweaks, pinctrl changes, etc.

**Costs:**
- New package to maintain (small, ~20 lines)
- We depend on the kernel source tree layout for includes — minor risk if Linux reorganizes
- Slightly more complex `handhelds/r36h/default.nix` (one extra line to set `dtbSource`)

## Implementation plan

1. **Create `pkgs/rk3326-dtb/`** — new derivation that compiles the DTS
2. **Move the DTS file** from `pkgs/kernel-rk3326/rk3326-r36s.dts` to `pkgs/rk3326-dtb/rk3326-r36s.dts`
3. **Wire in overlay.nix** — add `rk3326-dtb = final.callPackage ./pkgs/rk3326-dtb { };`
4. **Update `handhelds/r36h/default.nix`**:
   - Change `hardware.deviceTree.filter` → `hardware.deviceTree.dtbSource = pkgs.rk3326-dtb`
5. **Clean up kernel package** — remove `postPatch` DTS copy and the Makefile patch
6. **Delete `pkgs/kernel-rk3326/patches/0001-add-r36s-to-makefile.patch`**
7. **Test**: build the NixOS configuration, verify the DTB is bit-for-bit identical to the current kernel-built one (or at least functionally equivalent)

## Future: overlays

Once this lands, panel variants could become `hardware.deviceTree.overlays` — drop-in DTS fragments that modify specific nodes (panel init sequences, timings) without forking the base DTS. Useful for the R36H "panel lottery."

## Open questions

- **Validation**: does the DTB need any post-processing that the kernel's build does (symbols table, `-@` flag for overlays)? The kernel passes `-@` when building DTBs to enable overlay support. We should match this.
- **Diff vs current DTB**: verify byte-identical output (modulo timestamps) to catch any regression before switching.
