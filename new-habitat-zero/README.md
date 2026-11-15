# New Habitat Zero

A 2D top-down pixel-art remake of Habitat Zero, made in Godot 4.7. You live on a moon base for
5 days, picking one task each morning and afternoon and surviving the events (moon dust in the
filters, a space-rock leak, a solar flare and a moonquake).

## Play

Open the folder in Godot 4.7 and press Play (F5).

- **WASD / arrow keys**: move
- **Tab**: open the task board and pick a task
- **E**: use the machine for your task (a yellow arrow points to it), or sleep in a bed

## How it's organized

| Path | What's there |
|---|---|
| `scenes/main.tscn` | The level: `World > Ground / Floors / Walls` tile layers, `Objects > Rooms > <Room> > <Machine>`, and `Outside` |
| `scenes/machine.tscn` | One reusable machine. Set `station_id` (a task station) and `texture` in the Inspector |
| `scenes/player.tscn` | The astronaut |
| `scenes/hud.tscn`, `scenes/campaign.tscn` | Room name, deck map, status panel and task board |
| `scripts/campaign.gd` | The day/slot task rules, all minigames and the NASA links |
| `art/`, `ui/` | Pixel art, tileset, 5x7 pixel font and UI theme |
| `Moonbase/` | Moonbase tileset by TheRealFusion (see its terms file) |
| `tools/` | Scripts that generated the art and the scenes. Re-running `build_scenes.gd` overwrites the scenes |

The game renders at 320x180 and scales up by whole numbers, so every pixel (art and text) is the
same size.
