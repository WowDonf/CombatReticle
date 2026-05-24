<!--
CurseForge / Wago "Summary" field (paste into the short summary box on
the project's settings page, not into the description body):

Center-screen reticle for WoW Midnight. 30 textures or any WoW icon, color tinting, size and position controls.
-->

# CombatReticle

Center-screen reticle for WoW Midnight (patch 12.x). One customizable
texture at screen center for third-person / action-cam play.

## Features

- 30 bundled reticle textures: 10 standard shapes (crosshair, brackets,
  target rings, diamond, hexagon, star, triangle, X, double / quad
  arrows), 10 inward-pointing and minimal designs (chevrons, gap
  crosshair, side arrows, small square, filled dot, ring + dot, corner
  arrows), and a modern chevron set (singles, triples, converging
  pairs) with a skull and shamrock icon.
- Use any `Interface\Icons` texture as the reticle instead (e.g.
  `Ability_Mount_RidingHorse`).
- Blizzard color picker for tinting (wheel, RGB, hex, opacity).
- Sliders + stepper buttons for size (16-256 px), opacity, X/Y offset.
- Floating, draggable options window with a 6x5 visual icon grid.
  Doesn't sit on top of the reticle while you configure it.
- Show-only-in-combat (off by default) and hide-on-vehicle toggles.
- Minimap button + addon compartment entry. Left-click opens options,
  right-click toggles combat-only.
- `/cr help` for the full slash command list.

## Compatibility

- WoW Midnight (patch 12.x).
- Embeds LibStub, CallbackHandler-1.0, LibDataBroker-1.1, LibDBIcon-1.0
  for the minimap button. LibStub defers to a newer copy if another
  addon has one loaded.
- No required dependencies, no taint.

## Feedback

Open an issue on [GitHub](https://github.com/WowDonf/CombatReticle) or
comment on the CurseForge / Wago page.
