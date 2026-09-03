# PeaversMiniMap

[![AddonSentry](https://addonsentry.io/api/public/repos/peavers-warcraft/PeaversMiniMap/badge.svg)](https://addonsentry.io/dashboard/peavers-warcraft/PeaversMiniMap)
[![Ultra Performance](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/peavers-warcraft/PeaversMiniMap/master/.github/badges/perf.json)](#performance)

A World of Warcraft addon that turns the minimap into a clean square pinned to a corner of your screen, and gathers every addon button that scatters itself around the edge into one tidy grid.

## Features

<!-- peavers:features -->
- Square minimap, pinned to whichever screen corner you choose
- Addon buttons collected into a grid that they cannot wander out of
- Zone name, tracking, mail, difficulty and the expansion button moved onto the square's own corners
- Adjustable size, scale and border, with the zoom buttons hidden by default
- Fully reversible: turning it off restores Blizzard's minimap exactly, with no reload
- Runs nothing per frame and nothing on a timer
<!-- /peavers:features -->

## Usage

<!-- peavers:usage -->
The addon squares and repositions the minimap as soon as you log in. Everything else is optional.

### Slash Commands

- `/pmm` - Open the settings
- `/pmm size N` - Set the square's edge length in pixels (100-400)
- `/pmm scan` - Look for addon buttons that appeared late
- `/pmm buttons` - List every collected button
- `/pmm enable` / `/pmm disable` - Turn the addon on, or restore Blizzard's minimap
- `/pmm info` - Print minimap diagnostics

### The button grid

Buttons are identified by exclusion rather than by a list of known addons, so a button from an addon released tomorrow is collected too. Once a button is in the grid it cannot move itself again - that is the whole point, and it is why buttons stop scattering across the corners of a square map.

Any button you would rather leave alone can be excluded from the **Buttons** page in the settings; excluded buttons go straight back to wherever their own addon put them.

The grid can sit below, above or to either side of the map, and can be shown always, only while the pointer is over the minimap, or behind a small button on the map's corner.
<!-- /peavers:usage -->

## Performance

PeaversMiniMap is part of the Ultra Performance programme: it declares a budget, and the build fails when a measurement exceeds it. Nothing below is an estimate - every number is regenerated from the real source on every push.

The claim this addon makes is a negative one. It lays the minimap out once and then gets out of the way: no `OnUpdate` handler anywhere, no repeating ticker, and no queued work left over once login has settled. Layout runs when something actually changes, and several changes in the same frame are coalesced into a single pass.

It also takes work away. Collected buttons lose their drag handlers, which is what a LibDBIcon button uses to run an `OnUpdate` for as long as you hold it, and a button parked in a hidden grid is not ticked by the client at all.

<!-- perf:begin -->

> Measured on every push by the Ultra Performance harness. The build fails if any number here exceeds the budget in `perf/budget.json`.

| Check | Measured | Budget | |
|---|---:|---:|:--:|
| Packaged size | 61.5 KB | 80 KB | pass |
| Bundled libraries | 0 | 0 | pass |
| Widget calls per frame | 0 | 0 | pass |
| Widget calls per second while idle | 0 | 0 | pass |

Scenarios driven against the real addon source, outside the game:

| Scenario | Calls/frame | Notes |
|---|---:|---|
| login: square applied, 30 buttons collected | 0.00 | 666 client calls, one-off |
| 10 addons register buttons in one frame | 0.00 | 319 client calls, 1 coalesced layout pass, 40 buttons in the grid |
| steady state, 144fps | 0.00 | 0 OnUpdate handler(s) across 144 frames; 0 tick(s) |
| steady state, 60fps | 0.00 | 0 OnUpdate handler(s) across 60 frames; 0 tick(s) |
| idle, one second at 144fps | 0.00 | 0 handler(s), 0 queued timer(s) |
| disable and restore Blizzard's minimap | 0.00 | 442 client calls, one-off |

<sub>1,751 lines of Lua · 61.5 KB packaged · no bundled libraries</sub>

<!-- perf:end -->

## Installation

### Recommended: PeaversUpdater

Download and install [PeaversUpdater](https://github.com/peavers-warcraft/PeaversUpdater/releases/latest), the desktop updater for the whole Peavers collection. It installs PeaversMiniMap together with its required dependencies and delivers updates before they reach CurseForge.

### Alternative: CurseForge

1. Download from [CurseForge](https://www.curseforge.com/wow/addons/peaversminimap)
2. Ensure [PeaversCommons](https://www.curseforge.com/wow/addons/peaverscommons) is also installed
3. Ensure [PeaversConfig](https://www.curseforge.com/wow/addons/peaversconfig) is also installed
4. Enable the addon on the character selection screen

---

*Part of the [Peavers](https://peavers.io) addon collection · [Report an issue](https://github.com/peavers-warcraft/PeaversMiniMap/issues) · [Support development on Patreon](https://www.patreon.com/Peavers)*
