# Run from the repo root.
#   make mem      maps/map.txt, sprites/*.txt -> mem/*.mem (+ preview PNGs)
#   make lint     Verilator lint
#   make tb       all testbenches
#   make sim      one frame of the whole design -> build/frame.png
#                 press buttons first: make sim KEYS=CRU  (C U D L R)
#   make bit      Vivado: bitstream -> build/game_top.bit (Linux/Windows)
#   make program  Vivado: program the board
#   make format   Verible: format all SystemVerilog files
#   make clean

VERILATOR ?= verilator
PYTHON    ?= python3
VIVADO    ?= vivado
MAP       ?= map
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
       src/io/slide_switch.sv \
       src/io/sevenseg.sv \
       src/io/multidigit.sv \
       src/game/terrain_memory.sv \
       src/game/game_ctrl.sv \
       src/game_top.sv

.PHONY: all mem lint tb tb_button tb_game_ctrl sim bit program format clean

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

tb: tb_button tb_game_ctrl

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

# Formatting (needs Verible)
VERIBLE_FORMAT ?= verible-verilog-format
FORMAT_FLAGS   := --indentation_spaces=2 --wrap_spaces=2 --column_limit=110 \
                  --port_declarations_alignment=align --named_port_alignment=align \
                  --module_net_variable_alignment=align --assignment_statement_alignment=align \
                  --formal_parameters_alignment=align --struct_union_members_alignment=align \
                  --case_items_alignment=align --enum_assignment_statement_alignment=align
format:
	$(VERIBLE_FORMAT) $(FORMAT_FLAGS) --inplace src/*.sv src/*/*.sv sim/*.sv sim/verilator/*.sv

clean:
	rm -rf $(BUILD) .Xil obj_dir
