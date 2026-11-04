# Vivado batch build: bitstream plus timing and utilization reports.

# Nexys A7-100T. For the 50T board use: xc7a50ticsg324-1L
set part xc7a100tcsg324-1

set root  [file normalize [file join [file dirname [info script]] ..]]
set out   [file join $root build]
set ipdir [file join $out ip]
file mkdir $out
file delete -force $ipdir

create_project -in_memory -part $part

# ---- pixel clock: Clocking Wizard IP, 100 MHz -> 83.46 MHz, no reset, locked kept ----
create_ip -name clk_wiz -vendor xilinx.com -library ip -version 6.0 \
          -module_name clk_wiz_0 -dir $ipdir
set_property -dict [list \
  CONFIG.PRIM_IN_FREQ                {100.000} \
  CONFIG.CLKOUT1_REQUESTED_OUT_FREQ  {83.46}   \
  CONFIG.USE_RESET                   {false}   \
  CONFIG.USE_LOCKED                  {true}    \
] [get_ips clk_wiz_0]
generate_target all [get_ips clk_wiz_0]
synth_ip [get_ips clk_wiz_0]

# ---- our sources (package first) ----
read_verilog -sv [list \
  $root/src/game_pkg.sv \
  $root/src/video/vga_out.sv \
  $root/src/video/drawcon.sv \
  $root/src/io/button.sv \
  $root/src/game/terrain_memory.sv \
  $root/src/game/game_ctrl.sv \
  $root/src/game_top.sv \
]
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
report_clocks         -file $out/clocks.rpt
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
puts "Pixel clock actually generated: see build/clocks.rpt (should be ~83.46 MHz)"
