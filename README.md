# Power Mode

An [Omarchy](https://omarchy.org/) shell plugin that switches your display's
refresh rate, resolution, scale, and power-profiles-daemon profile
automatically when you plug in or unplug — with a full picker for editing
the AC/battery presets, reachable from the launcher (`SUPER+SPACE`).

![icon](https://img.shields.io/badge/icon-%F0%9F%94%8C-black)

## Features

- **Automatic switching** — reacts live to AC/battery changes (via
  `UPower.onBattery`), no polling, keeps working in the background whether
  the picker is open or not.
- **Full preset picker**, per power source:
  - Resolution (every mode the monitor actually reports — only shown when
    there's more than one)
  - Refresh rate, scoped to the selected resolution
  - Scale (1x–4x presets, snapped to values Hyprland will actually accept)
  - Power profile (`performance` / `balanced` / `power-saver`, whatever
    `power-profiles-daemon` reports as available)
- **Multi-monitor aware** — a display picker appears when more than one
  output is connected; hidden entirely on a single-monitor setup.
- **Stage, then apply** — picking a preset only saves it; nothing changes
  live until you press **Apply now**, or until the power source actually
  changes (that part is always automatic).
- **No bar icon** — lives entirely in the launcher, not the top bar.
- Self-contained: no external scripts, no dependencies beyond what Omarchy
  already ships (`hyprctl`, `power-profiles-daemon`).

## Install

```bash
omarchy plugin add https://github.com/Emanuel4100/omarchy-power-mode.git --enable
```

Or manually:

```bash
git clone https://github.com/Emanuel4100/omarchy-power-mode.git ~/.config/omarchy/plugins/power-mode
omarchy plugin enable power-mode
```

Add a launcher entry (not automatic — this lives in your own menu config so
it survives plugin updates) by adding this to
`~/.config/omarchy/extensions/omarchy-menu.jsonc`:

```jsonc
"trigger.power-mode": {"icon":"󰂄","label":"Power Mode","action":"omarchy-shell shell toggle power-mode"}
```

Then `SUPER+SPACE` → search "Power Mode".

## How it works

- Presets are stored in `~/.config/omarchy/plugins/power-mode/settings.json`
  (machine-specific, not committed to this repo).
- Applying a mode calls `hyprctl eval` with Hyprland's Lua `hl.monitor(...)`
  helper (falling back to the legacy `hyprctl keyword monitor` form if that
  ever errors), and `omarchy-powerprofiles-set <ac|battery> <profile>` for
  the power profile — the same mechanisms Omarchy's own Display and Power
  panels use.
- A preset that's already live is never re-applied, so there's no needless
  modeset (screen blink) at startup or after a config reload.
- After Hyprland reloads its config or a monitor is (un)plugged, the active
  preset is re-applied once (debounced). If it keeps getting reverted (3
  times within a minute), display switching pauses until the power source
  changes or you press **Apply now**, instead of fighting another tool and
  making the screen flicker.
- `"keepLoaded": true` in `manifest.json` keeps the plugin's background logic
  running for the whole shell session, not just while the picker is open.

## Other monitor managers (hyprmoncfg)

[hyprmoncfg](https://github.com/crmne/hyprmoncfg)'s `hyprmoncfgd` re-applies
its saved layout, refresh rate included, on every config reload. With both
tools setting the refresh rate, the panel bounces between them at boot. So
by default (`"displayControl": "auto"` in `settings.json`) Power Mode leaves
the display alone while `hyprmoncfgd` is running and only switches the
power profile. Let hyprmoncfgd handle AC/battery refresh by running it with
`--power-aware-refresh`:

```bash
systemctl --user edit hyprmoncfgd
# [Service]
# ExecStart=
# ExecStart=/usr/bin/hyprmoncfgd --power-aware-refresh
```

Set `"displayControl": "on"` to always manage the display anyway, or `"off"`
to only ever switch the power profile.

## Uninstall

```bash
omarchy plugin remove power-mode
```

## License

MIT
