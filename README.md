# cosmic-comp-evdi — fix DisplayLink lag in the COSMIC desktop

**Fixes laggy, stuttering DisplayLink monitors and high CPU usage of `cosmic-comp` on
the COSMIC desktop under Wayland. Packaged for and tested on Arch Linux and CachyOS.**

Patched build of [cosmic-comp](https://github.com/pop-os/cosmic-comp), the COSMIC
Wayland compositor, that renders **DisplayLink (evdi) monitors on the GPU** instead of
on the CPU via llvmpipe. On a 3440×1440 @ 100 Hz DisplayLink monitor it brings the
compositor from **~7.6 CPU cores down to ~0.5** while moving windows, and removes the
freeze of all monitors when the workspace overview is opened.

> [!IMPORTANT]
> **Supported: Arch Linux and CachyOS, COSMIC on Wayland.** That is the only setup this
> package has been tested on. It is distributed as the pacman package
> `cosmic-comp-evdi`, which replaces the stock `cosmic-comp` package. Other
> distributions are not supported by the install scripts.

Tested with the Lenovo ThinkPad Hybrid USB-C with USB-A Dock. It should help with any
DisplayLink dock or adapter (Lenovo, Dell D6000 / D3100, Targus, Plugable, …) that shows
up as an `evdi` device and uses the DisplayLink driver (`displaylink` / `evdi-dkms`).

> [!WARNING]
> This is an unofficial patch. A similar approach was proposed upstream in
> [pop-os/cosmic-comp#2109](https://github.com/pop-os/cosmic-comp/pull/2109) and was
> closed without being merged; a maintainer noted that rendering into linear GPU buffers
> may be slower on some GPU/driver combinations. It works well on the hardware listed
> below — measure on yours (see [Testing](#testing)).

## The problem

With a monitor connected through a DisplayLink dock (any dock or adapter driven by
the `evdi` kernel module and `DisplayLinkManager`), COSMIC on Wayland becomes sluggish:

- the whole picture on the DisplayLink monitor stutters when windows move, pages
  scroll or videos play — not only the cursor;
- opening the workspace overview (<kbd>Super</kbd>+<kbd>W</kbd>) makes **all**
  monitors, including the built-in one, freeze and stutter;
- `cosmic-comp` uses several CPU cores, almost all of it in `llvmpipe-*` threads.

## Root cause

DisplayLink is not a real display controller. `evdi` exposes a virtual DRM device
without any render engine; `DisplayLinkManager` reads finished frames from system
memory, compresses them and sends them over USB.

cosmic-comp creates a renderer for every DRM device. For `evdi` there is no hardware
driver, so Mesa backs it with **llvmpipe** (software OpenGL on the CPU). Three code
paths ended up using it:

1. **Compositing the evdi output.** Depending on the windows on the active workspace,
   cosmic-comp either composited the whole frame with llvmpipe, or rendered it on the
   primary GPU and then had to copy it to evdi. That copy tries to import the primary
   GPU's (tiled, compressed) buffer into the evdi device, which fails
   (`Error importing dmabuf from renderD129 to card3: Failed to import buffer`), so
   smithay falls back to `cpu-copy`: read the frame back to RAM and redraw it with
   llvmpipe. Either way, every frame of a 3440×1440 @ 100 Hz output is drawn on the CPU.
2. **Workspace overview and screencopy.** Workspace previews are captured with
   `render_workspace_to_buffer()`, which picks the renderer of the device the output
   belongs to — llvmpipe for evdi. This runs on the compositor's **main thread**, so
   while llvmpipe renders the previews every output stalls.
3. *(Not changed here.)* cosmic-comp disables cursor planes on evdi because of
   corruption on some systems. With the patches below the cursor is composited by the
   GPU, so this no longer matters.

## The fix

Two small patches on top of the upstream release tag:

| Patch | What it does |
|---|---|
| [`0001-render-evdi-outputs-on-primary-gpu.patch`](0001-render-evdi-outputs-on-primary-gpu.patch) | After the output is initialised, the swapchain of a software (evdi) output is re-created with a GBM allocator on the **primary GPU** using the **linear** modifier, and the output is rendered with a single renderer on that GPU. The linear dmabuf is imported directly into evdi, so there is no llvmpipe composition and no CPU read-back. |
| [`0002-offscreen-capture-on-primary-gpu.patch`](0002-offscreen-capture-on-primary-gpu.patch) | `target_node_for_output()` ignores software devices, so workspace previews and screencopy of evdi outputs fall back to the primary GPU instead of llvmpipe. |

The only CPU work left is what DisplayLink itself requires: `DisplayLinkManager`
reading and compressing the finished frame.

## Results

Measured with [`tools/measure.sh`](tools/measure.sh) and `perf` on the hardware below.
Values are CPU cores used by `cosmic-comp` (and its llvmpipe threads) over the sampling
window.

| Scenario | Stock cosmic-comp | cosmic-comp-evdi |
|---|---|---|
| Nothing moving on screen | 0.86 (llvmpipe 0.62) | 0.03 (llvmpipe 0.00) |
| Dragging / scrolling windows on the DisplayLink monitor | 7.59 (llvmpipe 7.31) | 0.50 (llvmpipe 0.00) |
| Workspace overview open | 5.98 (llvmpipe 5.65), all monitors freeze | 0.88 (llvmpipe 0.00), no freezes |

`DisplayLinkManager` itself used ~0.5 cores while windows were moving in both cases.

Test system:

- Lenovo ThinkPad, Intel Core i7-1360P, Intel Iris Xe (Raptor Lake-P) as primary GPU
  (an NVIDIA RTX A500 is present but not used by the compositor)
- ThinkPad Hybrid USB-C with USB-A Dock (DisplayLink `17e9:6015`), USB 3
- Lenovo T34WD-40, 3440×1440 @ 100 Hz, plus the 1920×1200 built-in panel
- CachyOS, Linux 7.3, Mesa 26.2.6, evdi 1.15.0, DisplayLink driver 6.3, COSMIC 1.11.0

## Requirements

- Arch Linux or CachyOS with the COSMIC desktop (Wayland session) installed from the
  repositories
- `cosmic-comp` from the repositories at the **same version** as `pkgver` in the
  [`PKGBUILD`](PKGBUILD) (currently 1.11.0); mixing COSMIC component versions is not
  supported
- `base-devel`, plus the build dependencies (`cargo`, `git`, `just`, `lld`), which
  `makepkg -s` installs automatically
- A primary GPU with a Mesa driver (tested with Intel `iris`)

## Install

```sh
git clone https://github.com/ReykoMe/cosmic-comp-evdi.git
cd cosmic-comp-evdi
./install.sh
```

The script checks that the installed `cosmic-comp` matches the PKGBUILD version, builds
the package with `makepkg` (about 5–15 minutes) and installs it with `pacman -U`.
pacman will ask to replace `cosmic-comp` with `cosmic-comp-evdi`; answer **y**.
Use `./install.sh --yes` to skip all prompts.

Then **log out and log back in** — the running compositor is not replaced until the
session restarts.

Manual alternative:

```sh
makepkg -si
```

## Testing

After logging back in, run the measurement script while reproducing each scenario:

```sh
./tools/measure.sh          # 10 s sample; pass another duration as the first argument
```

Example output with the patch active:

```text
cosmic-comp pid 12345: /usr/bin/cosmic-comp (cosmic-comp-evdi)
DisplayLink (evdi) outputs: card3-DVI-I-2
Patch active: evdi outputs are rendered on the primary GPU
Over 10s: cosmic-comp 0.20 cores, of which llvmpipe 0.00 cores
```

What to check:

1. `/usr/bin/cosmic-comp` is owned by `cosmic-comp-evdi`.
2. The line `Patch active` is printed. It comes from the compositor log:
   `journalctl -b _COMM=cosmic-comp | grep 'will use primary GPU'`.
3. `llvmpipe` stays at or near **0** cores while:
   - dragging a window and scrolling a web page on the DisplayLink monitor;
   - keeping the workspace overview (<kbd>Super</kbd>+<kbd>W</kbd>) open and moving the
     mouse over it.
4. The compositor log has no `Falling back to cpu-copy` or
   `Error importing dmabuf … Failed to import buffer` lines.
5. The cursor on the DisplayLink monitor does not leave trails, and hot-plugging the
   dock (unplug, plug back in) brings the monitor back.

For a detailed CPU profile, install `perf` and record the compositor:

```sh
sudo sysctl kernel.perf_event_paranoid=-1   # temporary, until reboot
perf record -F 499 -p "$(pgrep -x cosmic-comp)" -- sleep 10
perf report --sort comm,dso
```

Before the fix, almost all samples are in `llvmpipe-*` threads executing JIT code.

## Uninstall

```sh
./uninstall.sh
```

This replaces `cosmic-comp-evdi` with the stock `cosmic-comp` from the repositories,
verifies that `/usr/bin/cosmic-comp` belongs to the stock package again and deletes the
build artifacts in this directory (`src/`, `pkg/`, the cloned sources and built
packages; keep them with `--keep-build`). The package installs nothing outside the files
of the stock `cosmic-comp` package, so nothing else is left behind. Log out and back in
afterwards.

Manual alternative: `sudo pacman -S cosmic-comp` (accept removing `cosmic-comp-evdi`).

## Updating to a new COSMIC release

Nothing needs to be done until a new COSMIC version is released. Because
`cosmic-comp-evdi` replaces `cosmic-comp`, `pacman -Syu` does **not** update the
compositor when that happens — other COSMIC packages update, the compositor stays on
the old version. To move it to the new version:

1. Set `pkgver` in the [`PKGBUILD`](PKGBUILD) to the new COSMIC version (for example
   `1.12.0`) and refresh the checksums:
   ```sh
   updpkgsums   # from the pacman-contrib package
   ```
2. Run `./install.sh`. While building, it applies the patches to the new cosmic-comp
   sources and prints `Applying 0001-…` / `Applying 0002-…`.
   - If the build finishes, the patches still fit: log out and back in.
   - If it stops with `Hunk #… FAILED` right after an `Applying …` line, the cosmic-comp
     code changed where a patch touches it. The patch has to be ported to the new
     version (re-create the change on top of the new `epoch-<version>` tag of
     cosmic-comp and export it with `git format-patch`), or wait for an updated release
     of this repository.
3. Until then, or if you no longer need the fix, run `./uninstall.sh` to return to the
   stock compositor so that COSMIC can be updated normally.

## FAQ

**Is this the right fix for my problem?**
Most likely, if you use COSMIC on Wayland, the monitor is connected through a
DisplayLink dock or adapter, and `top -H -p "$(pgrep -x cosmic-comp)"` shows busy
`llvmpipe-*` threads while the DisplayLink monitor is laggy. `tools/measure.sh` prints
the same information. Monitors connected directly (HDMI, DisplayPort, USB-C alt mode,
Thunderbolt) are not affected by this issue.

**Does lowering the refresh rate or switching to X11 help?**
Lowering the refresh rate (e.g. 100 → 60 Hz) only reduces the amount of CPU work. COSMIC
has no X11 session. The issue is in how the compositor renders evdi outputs, so neither
setting nor driver option fixes it without patching cosmic-comp.

**Does it work with GNOME or KDE Plasma?**
This repository only patches cosmic-comp. GNOME (mutter) and KDE Plasma (KWin) have
their own multi-GPU code paths for DisplayLink.

**Do I need the NVIDIA/AMD dGPU?**
No. The DisplayLink output is rendered on the compositor's primary GPU, typically the
integrated GPU that drives the built-in panel.

**What happens on `pacman -Syu`?**
Nothing changes for the compositor; see
[Updating to a new COSMIC release](#updating-to-a-new-cosmic-release).

## Related upstream reports

- [pop-os/cosmic-comp#1728](https://github.com/pop-os/cosmic-comp/issues/1728) — High CPU
  usage when moving cursor with DisplayLink dock
- [pop-os/cosmic-comp#2443](https://github.com/pop-os/cosmic-comp/issues/2443) — Glitches
  and mouse stuttering under DisplayLink
- [pop-os/cosmic-comp#2109](https://github.com/pop-os/cosmic-comp/pull/2109) — fix: high
  CPU usage (200–600%) on EVDI/DisplayLink outputs (closed)

## License

The patches modify cosmic-comp and are distributed under the same license,
[GPL-3.0-only](https://github.com/pop-os/cosmic-comp/blob/master/LICENSE). The PKGBUILD
is derived from the Arch Linux `cosmic-comp` package.
