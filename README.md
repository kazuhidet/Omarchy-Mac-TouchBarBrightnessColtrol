# Touch Bar Brightness for Omarchy

English | [日本語](README_ja.md)

Touch Bar brightness control for Apple Silicon and T2 MacBook Pros, built to work the same way as Omarchy quattro's own brightness controls. It ships as an Omarchy shell plugin (`kazu.touchbar`) that can be installed from the Omarchy menu by its Git URL.

- **Status bar widget**: looks like the built-in Display widget, with a brightness slider and a sync mode switch
- **Keys**: CTRL+brightness keys for ±5%, CTRL+ALT+brightness keys for ±1% (the same pattern as brightness / ALT+brightness for the display)
- **Automatic sync**: follows the keyboard backlight (or the ambient light sensor), and goes dark with the display on the lock screen or when the lid is closed
- **OSD**: brightness changes show on the Omarchy OSD (icon 󰌓)

## Requirements

| Item | Details |
|---|---|
| OS | Omarchy quattro (Hyprland with the Lua config, Quickshell-based `omarchy-shell`) |
| Hardware | MacBook Pro with a Touch Bar<br>Apple Silicon (Asahi Linux, `apple,summit` DSI backlight) or T2 Mac (`appletb_backlight`) |
| Commands | `brightnessctl`, `jq`, `hyprctl` (all included in Omarchy) |
| Ambient sync (optional) | An IIO light sensor (`aop-sensors-als` on Apple Silicon) |

## Installation

### 1. Add the plugin

**From the menu:** open the Omarchy menu → **Setup → Plugins → Add Plugin** and enter this URL:

```
https://github.com/kazuhidet/Omarchy-Mac-TouchBarBrightnessColtrol
```

Answer Yes to "Enable now?" and choose `right` as the position.

**From the command line:**

```bash
omarchy plugin add https://github.com/kazuhidet/Omarchy-Mac-TouchBarBrightnessColtrol --enable
omarchy bar move kazu.touchbar --after omarchy.monitor   # place it right after Display
```

The plugin is cloned to `~/.config/omarchy/plugins/kazu.touchbar/`. The icon appears in the status bar right away and the slider already works.

### 2. Run the setup

For security, `omarchy plugin add` never runs scripts from a plugin. Set up the sync service, commands and key bindings separately, in one of two ways:

- Open the Touch Bar panel in the status bar and press **Set up sync service and keys** (it runs in a terminal), or
- Run this in a terminal:

```bash
~/.config/omarchy/plugins/kazu.touchbar/bin/omarchy-brightness-touchbar-setup install --bindings
```

The setup installs:

| What | Where |
|---|---|
| Command symlinks | `~/.local/bin/omarchy-*touchbar*` → the plugin's `bin/` |
| Sync service (enabled and started) | `~/.config/systemd/user/omarchy-brightness-touchbar-sync.service` |
| Key bindings (with `--bindings`) | Appended to the end of `~/.config/hypr/bindings.lua`, between markers |

Without `--bindings`, no key bindings are added. They are also skipped if `bindings.lua` already binds `omarchy-brightness-touchbar`.

Check the result with `omarchy-brightness-touchbar-setup status`.

### 3. Turn off tiny-dfr adaptive brightness (recommended)

tiny-dfr, the daemon that draws the Touch Bar, by default sets the Touch Bar brightness to follow the display brightness (see [Conflict with tiny-dfr](#conflict-with-tiny-dfr)). Left as is, every display brightness change overrides the slider and the sync service.

If the panel shows a **TINY-DFR** section, press **Turn off tiny-dfr adaptive brightness**, or run the following in a terminal. It needs root, so `sudo` asks for your password.

```bash
~/.config/omarchy/plugins/kazu.touchbar/bin/omarchy-brightness-touchbar-setup tiny-dfr
```

The command does the following:

- Writes `AdaptiveBrightness = false` to `/etc/tiny-dfr/config.toml`
  - If the file does not exist, it creates one with just that line. tiny-dfr merges it key by key over `/usr/share/tiny-dfr/config.toml`, so the button layout and other settings stay unchanged.
  - If the file exists, it is backed up to `config.toml.bak.<time>`, the line is added at the top between markers, and the original `AdaptiveBrightness` line is commented out.
- Restarts tiny-dfr and the sync service

To undo it, run `omarchy-brightness-touchbar-setup tiny-dfr --revert` (`uninstall` also undoes it). To do it by hand, put the single line `AdaptiveBrightness = false` in `/etc/tiny-dfr/config.toml` and run `sudo systemctl restart tiny-dfr`.

## Usage

### Status bar

󰌓 appears next to the Display widget.

- **Click**: open or close the panel
- **Wheel**: ±5% (shows the OSD)
- **Panel**
  - BRIGHTNESS slider: Touch Bar brightness
  - SYNC: switch between Keyboard / Ambient / Manual
  - Keyboard: j/k to move between sections, h/l to change the value or selection, Enter to confirm, Tab to the next panel

### Keys

| Keys | Action |
|---|---|
| Brightness / ALT+brightness | Display brightness ±5% / ±1% (Omarchy default) |
| SHIFT+brightness | Keyboard backlight (Omarchy default). In Keyboard mode the Touch Bar follows it |
| CTRL+brightness | Touch Bar ±5% |
| CTRL+ALT+brightness | Touch Bar ±1% |

### Sync modes

| Mode | Behavior |
|---|---|
| Keyboard (default) | `Touch Bar % = floor + keyboard% × (100 − floor)`. Even when keyboard auto-brightness turns the keys off in a bright room, the Touch Bar stays at the floor (30% by default) |
| Ambient | Follows the light sensor: the floor at 8 lux or less, 100% at 400 lux or more, linear in between |
| Manual | The sync service is stopped. Only the keys and the slider change the brightness |

In both sync modes:

- **Blackout**: when the internal display goes dark (lock screen idle, DPMS off) or the lid is closed, the Touch Bar goes to 0, and it comes back to its previous level afterwards.
- **Manual changes win**: adjusting with the keys or the slider pauses syncing. It resumes when the keyboard backlight (or, in Ambient, the room light) changes.
- **Manual off**: after `omarchy-brightness-touchbar off`, the Touch Bar stays off until you turn it back `on`.

### Commands

```bash
omarchy-brightness-touchbar               # print the current brightness (%)
omarchy-brightness-touchbar +5% | 5%- | 50%
omarchy-brightness-touchbar --no-osd 40%
omarchy-brightness-touchbar off | on

omarchy-brightness-touchbar-sync-mode     # print keyboard / ambient / off
omarchy-brightness-touchbar-sync-mode ambient

omarchy-hw-touchbar                       # name of the detected Touch Bar backlight device

omarchy-shell kazu.touchbar state         # shell IPC (brightness <N> / syncMode <mode> / open / close / toggle)
```

`omarchy brightness touchbar` does not work: the `omarchy` dispatcher only runs commands shipped in the Omarchy package.

### Settings

`~/.config/omarchy/touchbar-sync.env` (also written by the panel and the `sync-mode` command):

```sh
OMARCHY_TOUCHBAR_SYNC_MODE=keyboard   # keyboard / ambient
OMARCHY_TOUCHBAR_SYNC_MIN=30          # floor in % while syncing (0-100)
```

After editing it by hand, run `systemctl --user restart omarchy-brightness-touchbar-sync`.

The OSD icon can be changed with the `OMARCHY_TOUCHBAR_OSD_ICON` environment variable (a Nerd Font glyph).

## Updating

```bash
omarchy plugin update kazu.touchbar
```

The commands are symlinks, so they update automatically. If the service file changed, run `omarchy-brightness-touchbar-setup install` again. If QML changes do not show up, run `omarchy restart shell`.

## Uninstalling

```bash
omarchy-brightness-touchbar-setup uninstall   # removes the service, links and added key bindings, and reverts the tiny-dfr change
omarchy plugin remove kazu.touchbar
```

`touchbar-sync.env` and the backups made before editing (`*.bak.<time>`) are kept.

## Troubleshooting

| Symptom | What to check |
|---|---|
| The panel says "NO TOUCH BAR FOUND" | `omarchy-hw-touchbar` prints nothing. Check that `ls /sys/class/backlight` lists `appletb_backlight` or `*.dsi.*` |
| Sync does nothing | `omarchy-brightness-touchbar-setup status`, `journalctl --user -u omarchy-brightness-touchbar-sync` |
| Choosing Ambient falls back to Manual | No light sensor was found, so the service's start condition stopped it. Check `ls /sys/bus/iio/devices/*/in_illuminance*` |
| Icon or QML changes do not show up | `omarchy restart shell` |
| Changing the display brightness also changes the Touch Bar | tiny-dfr adaptive brightness is on. If `omarchy-brightness-touchbar-setup tiny-dfr --check` prints `adaptive`, follow [step 3](#3-turn-off-tiny-dfr-adaptive-brightness-recommended) |

## Conflict with tiny-dfr

With its default settings (`AdaptiveBrightness = true` in `/usr/share/tiny-dfr/config.toml`), `tiny-dfr` **rewrites the Touch Bar brightness to match the display every time the display brightness changes**. In testing, the Touch Bar value changed 1-2 seconds after the display brightness changed.

As a result, changing the display brightness:

- sets the Touch Bar to tiny-dfr's computed value, and
- makes the sync service treat that as a manual change and pause until the keyboard brightness next changes.

Turning off tiny-dfr adaptive brightness with `omarchy-brightness-touchbar-setup tiny-dfr` ([step 3](#3-turn-off-tiny-dfr-adaptive-brightness-recommended)) leaves this tool as the only writer of the Touch Bar brightness.

`omarchy plugin add` never runs plugin scripts, so this change is never made automatically. It is the only step that needs root, so it runs only when you choose it.

## Repository layout

```
manifest.json      Omarchy shell plugin manifest (kind: bar-widget)
Panel.qml          Status bar widget and panel
bin/               Touch Bar commands (linked into ~/.local/bin by the setup)
systemd/           Sync service unit file
docs/              Implementation notes
```

See [docs/IMPLEMENTATION.md](docs/IMPLEMENTATION.md) for implementation details.
