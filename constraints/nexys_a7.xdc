## nexys_a7.xdc - pin constraints for the Digilent Nexys A7 (100T and 50T share pins).
## Only the pins this design uses. Names must match game_top ports exactly.

set_property CFGBVS VCCO        [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

## 100 MHz board clock
set_property -dict { PACKAGE_PIN E3  IOSTANDARD LVCMOS33 } [get_ports CLK100MHZ]
create_clock -name sys_clk -period 10.00 [get_ports CLK100MHZ]

## Reset button (red, "CPU RESET"), active low
set_property -dict { PACKAGE_PIN C12 IOSTANDARD LVCMOS33 } [get_ports CPU_RESETN]

## VGA (slide 3)
set_property -dict { PACKAGE_PIN A3  IOSTANDARD LVCMOS33 } [get_ports {VGA_R[0]}]
set_property -dict { PACKAGE_PIN B4  IOSTANDARD LVCMOS33 } [get_ports {VGA_R[1]}]
set_property -dict { PACKAGE_PIN C5  IOSTANDARD LVCMOS33 } [get_ports {VGA_R[2]}]
set_property -dict { PACKAGE_PIN A4  IOSTANDARD LVCMOS33 } [get_ports {VGA_R[3]}]
set_property -dict { PACKAGE_PIN C6  IOSTANDARD LVCMOS33 } [get_ports {VGA_G[0]}]
set_property -dict { PACKAGE_PIN A5  IOSTANDARD LVCMOS33 } [get_ports {VGA_G[1]}]
set_property -dict { PACKAGE_PIN B6  IOSTANDARD LVCMOS33 } [get_ports {VGA_G[2]}]
set_property -dict { PACKAGE_PIN A6  IOSTANDARD LVCMOS33 } [get_ports {VGA_G[3]}]
set_property -dict { PACKAGE_PIN B7  IOSTANDARD LVCMOS33 } [get_ports {VGA_B[0]}]
set_property -dict { PACKAGE_PIN C7  IOSTANDARD LVCMOS33 } [get_ports {VGA_B[1]}]
set_property -dict { PACKAGE_PIN D7  IOSTANDARD LVCMOS33 } [get_ports {VGA_B[2]}]
set_property -dict { PACKAGE_PIN D8  IOSTANDARD LVCMOS33 } [get_ports {VGA_B[3]}]
set_property -dict { PACKAGE_PIN B11 IOSTANDARD LVCMOS33 } [get_ports VGA_HS]
set_property -dict { PACKAGE_PIN B12 IOSTANDARD LVCMOS33 } [get_ports VGA_VS]

## LEDs
set_property -dict { PACKAGE_PIN H17 IOSTANDARD LVCMOS33 } [get_ports {LED[0]}]
set_property -dict { PACKAGE_PIN K15 IOSTANDARD LVCMOS33 } [get_ports {LED[1]}]

## The reset button is asynchronous; it goes through a 2-FF synchronizer.
set_false_path -from [get_ports CPU_RESETN]
