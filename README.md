# CombatReticle

Center-screen reticle for WoW Midnight (patch 12.x).

## What it does

Draws one customizable texture at the center of your screen as an aim
point for third-person / action-cam play. 20 bundled designs, or use any
built-in WoW icon.

## Features

- 20 bundled reticle textures: crosshair, brackets, target rings,
  diamond, hexagon, star, triangle, X, plus 12 inward-pointing chevron
  designs.
- Use any `Interface\Icons` texture as the reticle instead.
- Blizzard color picker (wheel, RGB, hex, opacity). Cancel restores the
  previous color.
- Sliders with stepper buttons for size (16-256 px), opacity, and X/Y
  offset. Click steppers to nudge, hold to repeat.
- Floating, draggable options window. Doesn't sit on top of the reticle
  while you configure it.
- Visual 5x4 icon grid for picking a reticle.
- Show-only-in-combat (off by default) and hide-on-vehicle toggles.
- Minimap button + addon compartment entry. Left-click options,
  right-click combat-only toggle.
- `/cr` slash commands.

## Install

Search "CombatReticle" on CurseForge or Wago, or copy the
`CombatReticle` folder into
`World of Warcraft\_retail_\Interface\AddOns\` and `/reload`.

`/cr` opens the options window.

## Slash commands

| Command                  | Effect                                       |
| ------------------------ | -------------------------------------------- |
| `/cr`                    | open the options window                      |
| `/cr reticle <1-20>`     | pick a preset by number                      |
| `/cr icon <name>`        | use `Interface\Icons\<name>` as the reticle  |
| `/cr icon clear`         | revert to the selected preset                |
| `/cr size <n>`           | size in pixels (16-256)                      |
| `/cr color`              | open the color picker                        |
| `/cr combat on` / `off`  | toggle combat-only                           |
| `/cr minimap on` / `off` | show / hide the minimap button               |
| `/cr list`               | list all 20 presets                          |
| `/cr reset`              | reset to defaults (with confirmation)        |
| `/cr help`               | list all commands                            |

## Compatibility

- WoW Midnight (patch 12.x).
- Embeds LibStub, CallbackHandler-1.0, LibDataBroker-1.1, LibDBIcon-1.0
  for the minimap button. LibStub defers to a newer copy if another
  addon has one loaded.
- No required dependencies, no taint.

## Feedback

Open an issue on [GitHub](https://github.com/WowDonf/CombatReticle).

## License

See `LICENSE`. Bundled libraries under `Libs/` are distributed under
their own respective licenses by their original authors.
