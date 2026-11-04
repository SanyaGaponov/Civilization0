# Civilization0 — a tiny Civ-like game on the Nexys A7 (CS256 project)

SystemVerilog arcade game for the Digilent Nexys A7 (Artix-7) with VGA output.

**Current step:** two human players take turns moving one spearman each across
a fixed map. Each player has one city (building units comes later), and fighting
comes later too.

## How to play

Player 1 is **red** (city in the west), Player 2 is **blue** (city in the east).
The cursor colour and LEDs 14/15 show whose turn it is.

| Situation | Arrow buttons (BTNU/D/L/R) | Centre button (BTNC) |
|---|---|---|
| No unit selected | move the cursor one tile (stops at the map edge) | on **your** unit: select it · on an empty tile: **end your turn** · on a city: nothing yet |
| Unit selected (blinks) | move the unit one tile | deselect |

- A unit can't enter **ocean** or **mountains**, a tile with **another unit**
  (fighting comes later), or the **enemy city**. Blocked moves do nothing.
- Movement points per turn: spearman 1, archer 1, cavalry 2. Every move costs 1.
  Units with no points left are drawn dimmed.
- When all your units are out of points, the turn passes automatically and
  the cursor jumps to the other player's unit.
- The red **CPU RESET** button restarts the game.

Units are drawn as triangles, cities as squares with a white centre.

## Repository layout

```
src/                    synthesizable RTL code (becomes FPGA hardware)
  game_pkg.sv           shared constants and types: map, terrain,
                        players, cities, units, buttons
  game_top.sv           top level (FPGA pins): clock, reset, all modules
  video/vga_out.sv      VGA controller: hcount/vcount -> hsync, vsync,
                        pix_r/g/b, curr_x/curr_y
  video/drawcon.sv      colour of each pixel (combinational): bg = terrain,
                        blk = city / unit / cursor
  io/button.sv          one button: synchronizer, slow look (no bounce) -> 1-clock pulse
  game/terrain_memory.sv
                        64x32 terrain map (2 instant reads), from mem/map0.mem
  game/game_ctrl.sv     game rules: cursor, units, turns, movement
constraints/nexys_a7.xdc  pin assignments
maps/map0.txt           the map, drawn as ASCII (edit this!)
mem/                    generated memory files (committed, so Vivado needs no Python)
scripts/                gen_map.py, build.tcl, program.tcl, PNG helpers
sim/clk_wiz_0.sv        simulation stand-in for the Clocking Wizard IP (never in Vivado)
sim/tb_vga_out.sv       testbench: VGA timing
sim/tb_button.sv        testbench: one button (bouncing, repeated presses)
sim/tb_game_ctrl.sv     testbench: game rules vs a reference model, 20000 random presses
sim/verilator/          "virtual monitor": simulates a full frame -> PNG
```

## Testing on a Mac (no FPGA, no Vivado)

One-time setup:

```sh
brew install verilator        # needs Homebrew: https://brew.sh
```

Then, from the repo root:

```sh
make mem     # maps/map0.txt -> mem/map0.mem (+ .coe + mem/map0_preview.png)
make lint    # strict Verilator lint of all RTL
make tb      # all testbenches (VGA timing, debouncing, game rules)
make sim     # whole design, one frame -> build/frame.png
open build/frame.png
make sim KEYS=CRU   # press Centre, Right, Up first, then take the frame
```

- **`make tb`** runs three self-checking testbenches. `tb_game_ctrl` sends
  20000 random button presses to the game logic and to a simple reference copy
  of the rules, and checks that they agree after every press. A directed part
  walks Player 1's spearman across the map to Player 2's city, to check the
  "blocked by unit" and "blocked by enemy city" rules. Coverage counters at
  the end show that every rule was exercised.
- **`make sim`** acts like a monitor that only sees the VGA pins. It measures
  hsync and vsync, checks that blanking is black, checks that each tile holds
  one terrain colour (a misaligned pipeline would mix two), and checks that
  both players' colours appear. `KEYS` presses buttons before the frame is
  taken (`C` centre, `U` up, `D` down, `L` left, `R` right).

Each prints `PASS` or `FAIL`.

## Building the bitstream (Vivado, Windows/Linux)

Vivado does not run on macOS, so use a lab PC or a Windows/Linux machine.

```sh
module load xilinx    # on the KAUST workstation
make bit       # or: vivado -mode batch -source scripts/build.tcl
make program   # board connected via USB
```

- `build.tcl` first generates the **Clocking Wizard IP** `clk_wiz_0`, as in
  the course README (100 MHz in, 83.46 MHz out, no reset input, `locked`
  output kept), then builds the design. `build/clocks.rpt` shows the exact
  pixel clock it produced.
- Read `build/timing.rpt` and the `Timing met / FAILED` line at the end of the build. Negative slack means the design may glitch.
- For the **50T** board, change `part` at the top of `scripts/build.tcl`.
- You can also **program from the Mac** with a `.bit` file built elsewhere:
  ```sh
  brew install openfpgaloader
  openFPGALoader -b nexys_a7_100 build/game_top.bit
  ```

On the board, **LED0** lights when the pixel clock is stable and **LED1** blinks to show the design is running. **LED14** / **LED15** show whose turn it is (Player 1 / Player 2).

## Video timing

1280×800 at 60 Hz with an 83.46 MHz pixel clock, exactly as in the course
README: `hcount` 0…1679, `vcount` 0…827, visible area x 336…1615 and
y 27…826, hsync low during 0…135, vsync high during 0…2. The numbers live in
`src/video/vga_out.sv`. An HDMI-only monitor needs an *active* VGA→HDMI converter.

Two deliberate differences from the course README:

- **No second, slower "60 Hz" clock for the game logic.** Everything runs on
  `pixclk`, and the buttons produce 1-clock press pulses. A clock made by a
  counter can't be timing-checked by Vivado, and signals would cross between
  two unrelated clocks.
- **The Clocking Wizard's `locked` output is kept.** It holds the design in
  reset until the clock is stable.

## Editing the map

Edit `maps/map0.txt` (40×25 characters = the playable area, exactly one 1280×800 screen) and run `make mem`. Cities are fixed in `src/game_pkg.sv` (`CITY0_X` …) at (4, 15) and (34, 13), with each spearman on the tile next to it, so keep those tiles as land.

| char | terrain  | colour |
|------|----------|--------|
| `~`  | ocean    | `0x15A` |
| `.`  | grass    | `0x4A3` |
| `,`  | plains   | `0xBB5` |
| `f`  | forest   | `0x262` |
| `h`  | hills    | `0x864` |
| `^`  | mountain | `0xAAA` |

A new terrain type must be added in two files: `src/game_pkg.sv` (enum and `terrain_color`) and `scripts/gen_map.py` (`LEGEND`).

## Conventions

- One module per file; the file name is the module name.
- Use `logic` for every signal and port (no `wire` / `reg`). A mistyped signal name is caught by `make lint` (Verilator warning `IMPLICIT`), so run it before every commit.
- Use `always_ff` with `<=` and `always_comb` with `=`. Assign each signal in exactly one block.
- One clock (`pixclk`) for everything. Slow events use a 1-clock pulse or a counter bit, not a new clock.
- `main` must always pass `make lint tb sim`. Develop on branches and tag working board builds.
