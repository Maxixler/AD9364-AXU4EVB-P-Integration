if {![info exists ::env(FPGA_PROFEN_ROOT)]} {
  error "FPGA_PROFEN_ROOT environment variable is required."
}

set workspace_root [string map {\\ /} $::env(FPGA_PROFEN_ROOT)]
set workspace [file join $workspace_root "Vitis" "workspace"]
set pmufw_elf [file join $workspace "fmcomms2_axu4ev_hw" "zynqmp_pmufw" "executable.elf"]
set bitstream [file join $workspace "ad9364app" "_ide" "bitstream" "system_top.bit"]
set psuInitTcl [file join $workspace "fmcomms2_axu4ev_hw" "hw" "psu_init.tcl"]
set app_elf ""
foreach configuration {Release Debug} {
  set candidate [file join $workspace "ad9364app" $configuration "ad9364app.elf"]
  if {[file isfile $candidate]} {
    set app_elf $candidate
    break
  }
}

if {$app_elf eq ""} {
  error "Missing AD9364 application ELF under the Release and Debug configurations."
}

foreach {label artifact} [list \
  "PMUFW ELF" $pmufw_elf \
  "bitstream" $bitstream \
  "PS initialization Tcl" $psuInitTcl] {
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
source $psuInitTcl
psu_init
psu_ps_pl_isolation_removal
psu_ps_pl_reset_config

puts "Loading and starting the AD9364 application..."
targets -set -filter {name =~ "Cortex-A53 #0"}
dow $app_elf
configparams force-mem-accesses 0
con

puts "PASS: PMUFW, FPGA, direct PS/DDR/PS-PL initialization and ad9364app were launched over JTAG."
