# build.tcl - Vivado non-project batch build.
#   vivado -mode batch -source scripts/build.tcl     (or: make bit)
# Output: build/game_top.bit plus timing and utilization reports.

# Nexys A7-100T. For the 50T board use: xc7a50ticsg324-1L
set part xc7a100tcsg324-1

set root [file normalize [file join [file dirname [info script]] ..]]
set out  [file join $root build]
file mkdir $out

# ---- sources (package first) ----
read_verilog -sv [list \
  $root/src/game_pkg.sv \
  $root/src/video/clk_gen.sv \
  $root/src/video/vga_out.sv \
  $root/src/video/drawcon.sv \
  $root/src/game/terrain_rom.sv \
  $root/src/game_top.sv \
]
# Memory init files: Vivado finds them by name ("map0.mem") once added here.
read_mem $root/mem/map0.mem
read_xdc $root/constraints/nexys_a7.xdc

# ---- synthesis + implementation ----
synth_design -top game_top -part $part
report_utilization -file $out/utilization_synth.rpt
opt_design
place_design
route_design

report_timing_summary -file $out/timing.rpt
report_utilization    -file $out/utilization.rpt
report_drc            -file $out/drc.rpt

# ---- timing check: negative slack = design may glitch on the board ----
set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
if {$wns < 0} {
  puts "WARNING: timing FAILED, worst negative slack = $wns ns (see build/timing.rpt)"
} else {
  puts "Timing met, worst slack = $wns ns"
}

write_bitstream -force $out/game_top.bit
puts "Bitstream: $out/game_top.bit"
