# Implementation notes

English | [日本語](IMPLEMENTATION_ja.md)

A record of the design and decisions behind implementing Touch Bar brightness control to match Omarchy quattro's brightness behavior.

## Overview

```
Keys (CTRL+brightness) ─ bindings.lua ─┐
Bar (kazu.touchbar) ──── Panel.qml ────┼─► omarchy-brightness-touchbar ─► brightnessctl ─► /sys/class/backlight/<touchbar>
                                       │        ├─► omarchy-osd (󰌓)
                                       │        └─► omarchy-hw-touchbar (device detection)
systemd --user                         │
  omarchy-brightness-touchbar-sync ────┘  checks every second: kbd_backlight / ALS / DPMS / lid
  omarchy-brightness-touchbar-sync-mode ─► touchbar-sync.env + systemctl
```

Every entry point (keys, slider, IPC, sync service) ends up going through the same command and sysfs file. That is what makes manual change detection (below) work.

## Commands

### `omarchy-hw-touchbar`

Shaped like `omarchy-hw-display`: it prints the device name on one line, or exits 1 if none is found. `OMARCHY_BACKLIGHT_PATH` overrides the directory it searches.

1. `appletb_backlight` (T2 Macs, registered by `hid-appletb-bl`)
2. A backlight whose device tree compatible contains `apple,summit` (Apple Silicon, e.g. `228600000.dsi.0`)

Matching on compatible rather than on name order means the display backlight (`apple-panel-bl`) is never picked by mistake. In the other direction, `omarchy-hw-display` excludes `appletb_backlight` and prefers `apple-panel-bl`, so the two scripts never pick the same device.

### `omarchy-brightness-touchbar`

Follows the same spec as `omarchy-brightness-display`.

| Item | Details |
|---|---|
| Arguments | `[--no-osd] [+N%\|N%-\|N%\|off\|on]`. With no argument, prints the current % |
| Locking | `flock -n`. When a held key starts overlapping runs, the later ones are dropped |
| `+5%` / `5%-` | 1% steps at 5% and below. Otherwise the target % is computed and set as an absolute value: the Touch Bar backlight only has 0-255 steps, and relative changes would accumulate rounding errors |
| Minimum | 1%. 0 is only set by `off` |
| `off` / `on` | The display version uses DPMS; the Touch Bar version sets 0 with `brightnessctl --save` and comes back with `--restore` |
| OSD | `omarchy-osd -i <glyph> -p <%>`. `iconFor()` in `OsdModel.js` shows an unknown name as literal text, so a Nerd Font glyph (󰌓) is passed directly. It is a different glyph from the keyboard backlight OSD (󰌌) |

### `omarchy-brightness-touchbar-sync`

Built like `omarchy-brightness-keyboard-auto` (`--once`, `--available`, and a start check through `ExecCondition`). LED and backlight `brightness` files send no notification (uevent or inotify) when they change, so they are read every second.

Each check (`tick`) works like this:

1. **Blackout**: if every internal panel (eDP/LVDS/DSI) in `hyprctl monitors -j` has `dpmsStatus=false`, or `omarchy-hw-laptop-closed` is true, save the current value and set 0.
   - This covers the lock screen blanking (`omarchy-brightness-display off` in `lock/Service.qml`), a closed lid, and running on external monitors only.
2. **Wake**: when the blackout ends, restore the saved value. This pairs with `display on` in `omarchy-system-wake`.
3. **Manual change detection**: if the current value differs from what the service last wrote (`last_set`), someone changed it by hand, so syncing pauses. The source value at that moment is saved as `pause_value`.
   - The same idea as keyboard auto-brightness (`keyboard-auto`) pausing when it sees a manual write.
4. **Resume**: in keyboard mode, syncing resumes when the source moves away from `pause_value`. In ambient mode it resumes past the same threshold as `keyboard-auto` (the larger of ±20 lux or ±40%). If the Touch Bar was turned off by hand, it does not resume.
5. **Apply the target**: keyboard mode uses `min + kbd% × (100 − min)`. Ambient mode maps 8-400 lux linearly onto floor-100%, ignoring differences under 4% to avoid flicker.

The sync service never writes the keyboard LED, so it never interferes with `keyboard-auto`'s pause detection or with `omarchy-brightness-keyboard off/restore`.

### `omarchy-brightness-touchbar-sync-mode`

`~/.config/omarchy/touchbar-sync.env` is the single source of settings. `keyboard` / `ambient` rewrites only that line and runs `enable` + `restart` on the service. `off` runs `disable --now`. With no argument, it prints the current mode from the service state and the settings file.

### `omarchy-brightness-touchbar-setup`

`omarchy plugin add` only clones, validates and enables (no hooks, no sudo). This command does the rest.

- **Commands**: symlinked into `~/.local/bin`, so `omarchy plugin update` (a fast-forward pull) is enough to update them. `omarchy plugin validate` rejects symlinks **inside** the plugin folder, so the links always point outward (`~/.local/bin` → plugin).
- **systemd unit**: copied, not linked. systemd treats a link to a unit outside its search path as a "linked unit", which behaves differently. Quattro avoids `~/.config/systemd/user` for units shipped by packages; a unit the user creates there is fine.
- **Key bindings**: appended between `-- >>> kazu.touchbar bindings >>>` and `<<<` markers. `uninstall` removes only that range. Bindings already written by hand are left alone.
- **tiny-dfr** (`tiny-dfr [--check|--revert]`): the only step that needs root, so it is a separate subcommand rather than part of `install`. See the next section.

## Conflict with tiny-dfr

With `AdaptiveBrightness = true` (the default), tiny-dfr rewrites the Touch Bar brightness whenever the display brightness changes. In testing, moving `apple-panel-bl` from 5 to 15 took the Touch Bar from 79 to 22, and going back to 5 left it at 13. The sync service cannot tell this apart from a manual change, so tiny-dfr adaptive brightness is turned off and this tool becomes the only writer of the Touch Bar brightness.

How the change is distributed:

| Approach | Used | Reason |
|---|---|---|
| `setup tiny-dfr` writes it with sudo when the user chooses to | Yes | A change that needs root is made once, with the user seeing what it does |
| Write it automatically on `omarchy plugin add` | No | Omarchy's policy is to never run plugin scripts |
| Ship `/etc/tiny-dfr/config.toml` in a package | No | It would clash with a config file the user wrote |
| Always allow it through polkit | No | Hands out standing privileges for a one-time settings change |

- **What is written**: `/etc/tiny-dfr/config.toml` is merged key by key over `/usr/share/tiny-dfr/config.toml`, so the single line `AdaptiveBrightness = false` is enough. A newly created file starts with a `# Created by kazu.touchbar` line, and `--revert` deletes the whole file.
- **When the file already exists**: a `# >>> kazu.touchbar >>>` … `<<<` block is added at the top, and the original `AdaptiveBrightness` line is commented out with a `#kazu.touchbar# ` prefix, because TOML rejects duplicate keys. The block goes at the top so it is read as a top-level key, before any `[table]`. `--revert` removes the block and uncomments the line.
- **Applying it**: after writing, `systemctl try-restart tiny-dfr` runs. tiny-dfr sets the Touch Bar to `ActiveBrightness` when it starts, so the sync service is restarted next to put back the synced value.
- **Panel**: reading state also runs `tiny-dfr --check` (`adaptive` / `static` / `none`). When it is `adaptive`, the TINY-DFR section and button appear. The button runs the command in a terminal so the sudo password can be entered.

## Key binding policy

Omarchy's Mac bindings (`default/hypr/bindings/media.lua`) map SHIFT+brightness to the keyboard backlight. The Touch Bar keys leave that alone and copy the display's modifier pattern instead.

| Modifier | Display | Touch Bar |
|---|---|---|
| None | ±5% | CTRL ±5% |
| ALT | ±1% | CTRL+ALT ±1% |

## Shell plugin (`Panel.qml`)

Follows the structure of the built-in Display widget (`plugins/panels/monitor/Panel.qml`).

- Based on `Panel`, with `manageIpc: false` and its own `IpcHandler` (`brightness` / `syncMode` / `state` / `open` / `close` / `toggle`).
- `BarIconButton`: click opens or closes the panel, the wheel changes ±5%. The OSD is shown with `bar.shell.summon("omarchy.osd", …)`.
- `KeyboardPanel` + `PanelKeyCatcher`: j/k/h/l/Enter cursor movement. There are three sections: `brightness` (the slider, selectedIndex -1), `sync` (three buttons) and `tinydfr` (the fix button, only shown while tiny-dfr is adaptive).
- Like Display, the slider sends values with a 180ms debounce and queues a write while one is running. State is not re-read during a write or a debounce, so the slider never jumps back to a stale value.
- The sync service changes the Touch Bar on its own, so state is re-read every 2 seconds while the panel is open (Display uses 5 seconds).
- Commands run with the plugin's own `bin/` (from `Qt.resolvedUrl("bin")`) first on PATH. The bundled version is used even before setup, and even if an older copy sits in `~/.local/bin`.
- When the sync service unit is missing, the SYNC section shows a setup button instead of the mode buttons. It runs the setup in a terminal through `omarchy-launch-floating-terminal-with-presentation`.

### Hot reload

Saving a file under `~/.config/omarchy/plugins/` logs "Local plugin changed, reloading" and reloads the plugin. However, the QML component cache sometimes kept the old rendering. In that case, run `omarchy restart shell`.

## Testing

- Replace `hyprctl` with a fake: a script first on PATH that returns JSON with DPMS off. This tests blackout and wake without actually turning the display off.
- `OMARCHY_BACKLIGHT_PATH` / `OMARCHY_LEDS_DIR` / `OMARCHY_IIO_DEVICES_DIR`: point sysfs at a fake directory to test device detection.
- `OMARCHY_TINY_DFR_DEFAULT` / `OMARCHY_TINY_DFR_CONF`: move the tiny-dfr config files. With `sudo` and `systemctl` replaced on PATH by fakes that just run their arguments, `tiny-dfr` / `--revert` can be tested without root.
- `omarchy-shell kazu.touchbar state`: prints the panel's state as JSON.

## Future work

- Use tiny-dfr's `backlight_high.svg` (Material Symbols) as the bar and panel icon, by putting an image into `BarIconButton.iconComponent`. The OSD only shows text, so using it there would mean copying the OSD plugin.
