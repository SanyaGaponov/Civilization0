# Run from the repo root.
#   make mem      maps/map0.txt, sprites/*.txt -> mem/*.mem (+ preview PNGs)
#   make lint     Verilator lint
#   make tb       all testbenches
#   make sim      one frame of the whole design -> build/frame.png
#                 press buttons first: make sim KEYS=CRU  (C U D L R)
#   make bit      Vivado: bitstream -> build/game_top.bit (Linux/Windows)
#   make program  Vivado: program the board
#   make clean

VERILATOR ?= verilator
PYTHON    ?= python3
VIVADO    ?= vivado
MAP       ?= map0
BUILD     := build
# Sprite order = unit kind (spearman, archer, cavalry), then the city
SPRITES   := sprites/spearman.txt sprites/archer.txt sprites/cavalry.txt sprites/city.txt

# Design sources + simulation stand-in for the Clocking Wizard
SRC := src/game_pkg.sv \
       sim/clk_wiz_0.sv \
       src/video/vga_out.sv \
       src/video/drawcon.sv \
       src/video/sprite_memory.sv \
       src/io/button.sv \
       src/game/terrain_memory.sv \
       src/game/game_ctrl.sv \
       src/game_top.sv

.PHONY: all mem lint tb tb_vga_out tb_button tb_game_ctrl sim bit program clean

all: mem lint tb sim

mem: mem/$(MAP).mem mem/sprites.mem

mem/sprites.mem: $(SPRITES) scripts/gen_sprites.py
	$(PYTHON) scripts/gen_sprites.py mem/sprites $(SPRITES)

mem/%.mem: maps/%.txt scripts/gen_map.py
	$(PYTHON) scripts/gen_map.py $< mem/$*

lint:
	$(VERILATOR) --lint-only -Wall --top-module game_top $(SRC)
	@echo "lint OK"

TBFLAGS := --binary --timing --timescale 1ns/1ps -Wall

tb: tb_vga_out tb_button tb_game_ctrl

tb_vga_out:
	@mkdir -p $(BUILD)
	$(VERILATOR) $(TBFLAGS) --top-module tb_vga_out -Mdir $(BUILD)/tb_vga_out -o tb \
	    src/game_pkg.sv src/video/vga_out.sv sim/tb_vga_out.sv
	$(BUILD)/tb_vga_out/tb

tb_button:
	@mkdir -p $(BUILD)
	$(VERILATOR) $(TBFLAGS) --top-module tb_button -Mdir $(BUILD)/tb_button -o tb \
	    src/io/button.sv sim/tb_button.sv
	$(BUILD)/tb_button/tb

tb_game_ctrl: mem
	@mkdir -p $(BUILD)
	$(VERILATOR) $(TBFLAGS) --top-module tb_game_ctrl -Mdir $(BUILD)/tb_game_ctrl -o tb \
	    -GMAP_FILE='"$(abspath mem/$(MAP).mem)"' \
	    src/game_pkg.sv src/game/terrain_memory.sv src/game/game_ctrl.sv sim/tb_game_ctrl.sv
	$(BUILD)/tb_game_ctrl/tb

sim: mem
	@mkdir -p $(BUILD)
	$(VERILATOR) --cc --exe --build -O2 -Wall --top-module sim_top \
	    -Mdir $(BUILD)/sim -o sim_frame \
	    -GMAP_FILE='"$(abspath mem/$(MAP).mem)"' \
	    -GSPRITE_FILE='"$(abspath mem/sprites.mem)"' \
	    $(SRC) sim/verilator/sim_top.sv $(abspath sim/verilator/sim_frame.cpp)
	$(BUILD)/sim/sim_frame $(BUILD)/frame.ppm "$(KEYS)"
	$(PYTHON) scripts/ppm2png.py $(BUILD)/frame.ppm $(BUILD)/frame.png

bit: mem
	$(VIVADO) -mode batch -nojournal -nolog -source scripts/build.tcl

program:
	$(VIVADO) -mode batch -nojournal -nolog -source scripts/program.tcl

clean:
	rm -rf $(BUILD) .Xil obj_dir
