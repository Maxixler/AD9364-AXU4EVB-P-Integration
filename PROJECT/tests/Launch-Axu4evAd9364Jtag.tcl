foreach name {AXU4EV_PMUFW_ELF AXU4EV_BITSTREAM AXU4EV_PSU_INIT_TCL AXU4EV_APP_ELF} {
  if {![info exists ::env($name)] || $::env($name) eq ""} {
    error "Missing environment variable: $name"
  }
}

set pmufw_elf [string map {\ /} $::env(AXU4EV_PMUFW_ELF)]
set bitstream [string map {\ /} $::env(AXU4EV_BITSTREAM)]
set psu_init_tcl [string map {\ /} $::env(AXU4EV_PSU_INIT_TCL)]
set app_elf [string map {\ /} $::env(AXU4EV_APP_ELF)]
set ddr_test_address 0x00100000
set ddr_test_value 0xA5A5A5A5

foreach {label artifact} [list \
  "PMUFW ELF" $pmufw_elf \
  "bitstream" $bitstream \
  "PS initialization Tcl" $psu_init_tcl \
  "AD9364 application ELF" $app_elf] {
  if {![file isfile $artifact]} {
    error "Missing $label: $artifact"
  }
}

puts "Connecting to the local hardware server..."
connect

puts "Opening the PMU JTAG security gates..."
targets -set -filter {name =~ "PSU"}
mwr 0xffca0038 0x1ff
after 500

puts "Loading and starting PMU firmware..."
targets -set -filter {name =~ "MicroBlaze PMU"}
dow $pmufw_elf
con
after 500

puts "Programming the verified FPGA bitstream..."
fpga -file $bitstream

puts "Resetting Cortex-A53 #0..."
targets -set -filter {name =~ "Cortex-A53 #0"}
rst -processor -clear-registers

puts "Initializing PS, DDR and the PS-PL boundary directly..."
targets -set -filter {name =~ "PSU"}
configparams force-mem-accesses 1
source $psu_init_tcl
psu_init
psu_ps_pl_isolation_removal
psu_ps_pl_reset_config

puts "Verifying DDR access before application download..."
mwr $ddr_test_address $ddr_test_value
set ddr_readback [mrd $ddr_test_address]
if {![regexp -nocase {([0-9a-f]{8})\s*$} $ddr_readback -> ddr_word]} {
  error "Unable to parse DDR readback: $ddr_readback"
}
if {[string toupper $ddr_word] ne "A5A5A5A5"} {
  error "DDR verification failed at $ddr_test_address: $ddr_word"
}
puts "DDR verification passed: $ddr_word"

puts "Loading and starting the AD9364 application..."
targets -set -filter {name =~ "Cortex-A53 #0"}
dow $app_elf
configparams force-mem-accesses 0
con

puts "PASS: PMUFW, FPGA, direct PS/DDR/PS-PL initialization, DDR gate and ad9364app were launched over JTAG."
