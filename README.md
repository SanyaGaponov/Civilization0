# Civilization0 — a tiny Civ-like game on the Nexys A7 (CS256 project)

SystemVerilog arcade game for the Digilent Nexys A7 (Artix-7) with VGA output.

**Current step:** a fixed terrain map drawn as solid-colour 32×32 tiles.
There are no buttons, cursor or units yet.

![frame](docs/frame_1280x800.png)

## Repository layout

```
src/                    synthesizable RTL code (becomes FPGA hardware)
  game_pkg.sv           shared constants: video mode, map size, terrain types
  game_top.sv           top level: wiring only
  video/clk_gen.sv      MMCM pixel clock + reset synchronizer
  video/vga_out.sv      VGA timing: counters -> hsync, vsync, de, x, y
  video/drawcon.sv      pixel colour: x,y -> map address -> terrain -> colour
  game/terrain_rom.sv   64x32 terrain map, loaded from mem/map0.mem
constraints/nexys_a7.xdc  pin assignments
maps/map0.txt           the map, drawn as ASCII (edit this!)
mem/                    generated memory files (committed, so Vivado needs no Python)
scripts/                gen_map.py, build.tcl, program.tcl, PNG helpers
sim/tb_vga_out.sv       self-checking testbench for vga_out
sim/verilator/          "virtual monitor": simulates a full frame -> PNG
docs/decisions.md       why things are the way they are (feeds the report)
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
make tb      # vga_out testbench: sync periods, pulse widths, x/y counting
make sim     # whole design, one frame -> build/frame.png
open build/frame.png
```

`make sim` acts like a monitor that only sees the VGA pins. It measures hsync and vsync, checks that blanking is black, and checks that every tile is a single colour. If the colour pipeline and the sync signals were misaligned, tile edges would be shifted and this check would fail. It prints `PASS` or `FAIL`.

## Building the bitstream (Vivado, Windows/Linux)

Vivado does not run on macOS, so use a lab PC or a Windows/Linux machine.

```sh
make bit       # or: vivado -mode batch -source scripts/build.tcl
make program   # board connected via USB
```

- Read `build/timing.rpt` and the `Timing met / FAILED` line at the end of the build. Negative slack means the design may glitch.
- For the **50T** board, change `part` at the top of `scripts/build.tcl`.
- You can also **program from the Mac** with a `.bit` file built elsewhere:
  ```sh
  brew install openfpgaloader
  openFPGALoader -b nexys_a7_100 build/game_top.bit
  ```

On the board, **LED0** lights when the pixel clock is stable and **LED1** blinks to show the design is running. Press the red **CPU RESET** button to reset.

## Video mode / monitors

Set this in `src/game_pkg.sv`:

```systemverilog
localparam video_mode_e VIDEO_MODE = MODE_1280x800;   // or MODE_640x480
```

- `MODE_1280x800` uses the course timing (slide 7) with a 106.25 MHz pixel clock, giving about 76 Hz.
- `MODE_640x480` is standard 640×480 at 60 Hz with a 25.2 MHz clock. **Use it if a monitor shows "no signal" or "out of range".** It shows the top-left 20×15 tiles.
- If the monitor still refuses, try flipping `H_POL` / `V_POL` in the same file.
- An HDMI-only monitor needs an *active* VGA→HDMI converter.

## Editing the map

Edit `maps/map0.txt` (up to 64×32 characters; 40×25 are visible at 1280×800) and run `make mem`.

| char | terrain  | colour |
|------|----------|--------|
| `~`  | ocean    | `0x15A` |
| `.`  | grass    | `0x4A3` |
| `,`  | plains   | `0xBB5` |
| `f`  | forest   | `0x262` |
| `h`  | hills    | `0x864` |
| `^`  | mountain | `0xAAA` |

A new terrain type must be added in three places: `game_pkg.sv` (enum), `drawcon.sv` (colour) and `scripts/gen_map.py` (`LEGEND`).

## Conventions

- One module per file; the file name is the module name.
- Every file starts with `` `default_nettype none `` and ends with `` `default_nettype wire ``.
- Use `always_ff` with `<=` and `always_comb` with `=`. Assign each signal in exactly one block.
- One clock (`clk_pix`) for everything. Slow events use a 1-clock enable pulse, not a new clock.
- `main` must always pass `make lint tb sim`. Develop on branches and tag working board builds.
