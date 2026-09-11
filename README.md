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
- `"keepLoaded": true` in `manifest.json` keeps the plugin's background logic
  running for the whole shell session, not just while the picker is open.

## Uninstall

```bash
omarchy plugin remove power-mode
```

## License

MIT
