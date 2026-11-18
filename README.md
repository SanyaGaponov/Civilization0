# Civilization0

A small two-player Civilization-like game in SystemVerilog for the Digilent
Nexys A7-100T, shown on a 1280×800 VGA monitor (32×20-tile map in the centre).

## How to play

Player 1 is **red** (city in the west), Player 2 is **blue** (city in the east).
Each starts with a **spearman ▲**, an **archer ◆** and a **cavalry ▼**.
The cursor colour and LEDs 14/15 show whose turn it is.

| | Arrows | Centre |
|---|---|---|
| No unit selected | move the cursor | own unit: select · empty tile: end turn |
| Unit selected (white) | move, or attack an enemy unit there | deselect |

- Units can't enter ocean, mountains, the enemy city or a tile with your own unit.
- Moves per turn: spearman 2, archer 2, cavalry 4. Units with no moves left are dimmed.
- Attack: the defender loses 3 HP, the attacker 1 HP (archers 0). A unit at 0 HP
  is removed. Attacking uses all remaining moves.
- HP: archers 6, others 10, shown as a bar under the unit (green = left, red = lost),
  and as a number on the seven segment display.
- Flip **SW0** (either way) to jump the cursor to your next unit; flip again
  for the one after that. It only moves the cursor, so press Centre to select.
- The turn ends by itself when no unit has moves left.
- **CPU RESET** restarts the game.

## Layout

```
src/game_pkg.sv               constants, types, unit and map helpers
src/game_top.sv               top level: clock, reset, wiring, LEDs
src/video/vga_out.sv          VGA timing and blanking
src/video/drawcon.sv          pixel colour: terrain, sprites, HP bars, cursor
src/video/sprite_memory.sv    sprite pixels, loaded from mem/sprites.mem
src/io/button.sv              synchronize + debounce one button
src/io/sevenseg.sv            one digit: 4-bit value -> segment pattern
src/io/multidigit.sv          drives the eight shared digits in turn
src/game/terrain_memory.sv    terrain map, loaded from mem/map0.mem
src/game/game_ctrl.sv         game rules
constraints/nexys_a7.xdc      pins
maps/map0.txt                 the map as text
sprites/                      unit and city sprites as text
mem/                          generated memory files
scripts/                      build, program, map and sprite generators
sim/                          testbenches and the frame simulator
```

## Simulate (Mac or Linux)

```sh
brew install verilator   # once
make all                 # map, lint, testbenches, one frame -> build/frame.png
make sim KEYS=CRU        # press Centre, Right, Up before taking the frame
```

Each test prints `PASS` or `FAIL`.

## Build and program (Linux/Windows with Vivado)

```sh
make bit                 # -> build/game_top.bit; check "Timing met" at the end
make program             # or: openFPGALoader -b nexys_a7_100 build/game_top.bit
```

LED0: pixel clock locked.

## Seven segment display

The two right digits show the HP of the unit under the cursor (`00` to `10`,
dark when the cursor is on an empty tile); the leftmost digit shows whose turn
it is (`1` or `2`).

The board drives the segments of all eight digits from the same seven pins and
picks one digit with the (active low) anodes, so `multidigit` shows one digit at
a time and steps to the next one every 2^17 pixel clocks: 637 digits per second,
each digit redrawn 80 times per second, which looks steady to the eye.

## Video

1280×800 at 60 Hz, 83.46 MHz pixel clock from the Clocking Wizard (created by
`scripts/build.tcl`). Timing numbers are in `src/video/vga_out.sv`.
Everything runs on this one clock.

## Map

Edit `maps/map0.txt` (32×20 characters) and run `make mem`. Keep the tiles
around the cities (`src/game_pkg.sv`) as land.

| char | `~` | `.` | `,` | `f` | `h` | `^` |
|---|---|---|---|---|---|---|
| terrain | ocean | grass | plains | forest | hills | mountain |

## Sprites

`sprites/spearman.txt`, `archer.txt`, `cavalry.txt`, `city.txt`: 16×16
characters each, drawn at 2× in a 32×32 tile. Leave the outer row/column free
for the cursor and the two rows above the bottom one free for the HP bar.
Run `make mem` after editing; check `mem/sprites_preview.png`.

| char | `.` | `k` | `P` | `p` | `w` | `s` | `b` | `d` | `g` | `G` |
|---|---|---|---|---|---|---|---|---|---|---|
| colour | transparent | outline | owner | dark owner | white | skin | wood | dark wood | steel | dark steel |

## Conventions

- One module per file, named like the module.
- `logic` only; `always_ff` with `<=`, `always_comb` with `=`.
- One clock; slow events use enable pulses, not new clocks.
- Run `make all` before every commit.
