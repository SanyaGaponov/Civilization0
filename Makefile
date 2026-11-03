# Civilization0 - common commands. Run from the repo root.
#
#   make mem      ASCII map -> mem/map0.mem (+ .coe, preview PNG)
#   make lint     Verilator strict lint of all RTL
#   make tb       run all testbenches (vga_out, buttons, game_ctrl)
#   make sim      simulate one frame of the whole design -> build/frame.png
#                 press buttons first:  make sim KEYS=CRU  (C U D L R)
#   make bit      Vivado: synthesize + implement -> build/game_top.bit   (Windows/Linux only)
#   make program  Vivado: upload the bitstream to the board
#   make clean

VERILATOR ?= verilator
PYTHON    ?= python3
VIVADO    ?= vivado
MAP       ?= map0
BUILD     := build

SRC := src/game_pkg.sv \
       src/video/clk_gen.sv \
       src/video/vga_out.sv \
       src/video/drawcon.sv \
       src/io/buttons.sv \
       src/game/terrain_rom.sv \
       src/game/game_ctrl.sv \
       src/game_top.sv

.PHONY: all mem lint tb tb_vga_out tb_buttons tb_game_ctrl sim bit program clean

all: mem lint tb sim

mem: mem/$(MAP).mem

mem/%.mem: maps/%.txt scripts/gen_map.py
	$(PYTHON) scripts/gen_map.py $< mem/$*

lint:
	$(VERILATOR) --lint-only -Wall --top-module game_top $(SRC)
	@echo "lint OK"

TBFLAGS := --binary --timing --timescale 1ns/1ps -Wall

tb: tb_vga_out tb_buttons tb_game_ctrl

tb_vga_out:
	@mkdir -p $(BUILD)
	$(VERILATOR) $(TBFLAGS) --top-module tb_vga_out -Mdir $(BUILD)/tb_vga_out -o tb \
	    src/game_pkg.sv src/video/vga_out.sv sim/tb_vga_out.sv
	$(BUILD)/tb_vga_out/tb

tb_buttons:
	@mkdir -p $(BUILD)
	$(VERILATOR) $(TBFLAGS) --top-module tb_buttons -Mdir $(BUILD)/tb_buttons -o tb \
	    src/io/buttons.sv sim/tb_buttons.sv
	$(BUILD)/tb_buttons/tb

tb_game_ctrl: mem
	@mkdir -p $(BUILD)
	$(VERILATOR) $(TBFLAGS) --top-module tb_game_ctrl -Mdir $(BUILD)/tb_game_ctrl -o tb \
	    -GMAP_FILE='"$(abspath mem/$(MAP).mem)"' \
	    src/game_pkg.sv src/game/terrain_rom.sv src/game/game_ctrl.sv sim/tb_game_ctrl.sv
	$(BUILD)/tb_game_ctrl/tb

sim: mem
	@mkdir -p $(BUILD)
	$(VERILATOR) --cc --exe --build -O2 -Wall --top-module sim_top \
	    -Mdir $(BUILD)/sim -o sim_frame \
	    -GMAP_FILE='"$(abspath mem/$(MAP).mem)"' \
	    $(SRC) sim/verilator/sim_top.sv $(abspath sim/verilator/sim_frame.cpp)
	$(BUILD)/sim/sim_frame $(BUILD)/frame.ppm "$(KEYS)"
	$(PYTHON) scripts/ppm2png.py $(BUILD)/frame.ppm $(BUILD)/frame.png

bit: mem
	$(VIVADO) -mode batch -nojournal -nolog -source scripts/build.tcl

program:
	$(VIVADO) -mode batch -nojournal -nolog -source scripts/program.tcl

clean:
	rm -rf $(BUILD) .Xil obj_dir
