set script_dir [file dirname [file normalize [info script]]]
set project_root [file dirname [file dirname $script_dir]]

set workspace [file join $project_root "Vitis" "workspace"]
set pmufw_elf [file join $workspace "fmcomms2_axu4ev_hw" "zynqmp_pmufw" "executable.elf"]
set bitstream [file join $workspace "ad9364app" "_ide" "bitstream" "system_top.bit"]
set fsbl_elf [file join $workspace "fmcomms2_axu4ev_hw" "zynqmp_fsbl" "executable.elf"]
set app_elf [file join $workspace "ad9364app" "Release" "ad9364app.elf"]

foreach {label artifact} [list \
  "PMUFW ELF" $pmufw_elf \
  "bitstream" $bitstream \
  "FSBL ELF" $fsbl_elf \
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

puts "Resetting Cortex-A53 #0 and running FSBL..."
targets -set -filter {name =~ "Cortex-A53 #0"}
rst -processor -clear-registers
dow $fsbl_elf
con
after 5000
stop

puts "Loading and starting the AD9364 application..."
dow $app_elf
con

puts "PASS: PMUFW, FPGA, FSBL and ad9364app were launched over JTAG."
