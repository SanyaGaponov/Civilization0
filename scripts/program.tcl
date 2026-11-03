# Upload the bitstream to the first FPGA found on USB.
set root [file normalize [file join [file dirname [info script]] ..]]
set bit  [file join $root build game_top.bit]

open_hw_manager
connect_hw_server
open_hw_target
set dev [lindex [get_hw_devices] 0]
current_hw_device $dev
set_property PROGRAM.FILE $bit $dev
program_hw_devices $dev
puts "Programmed $dev with $bit"
close_hw_manager
