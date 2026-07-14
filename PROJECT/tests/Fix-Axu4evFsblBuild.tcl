if {![info exists ::env(FPGA_PROFEN_ROOT)]} {
  error "FPGA_PROFEN_ROOT environment variable is required."
}

set workspace_root [string map {\\ /} $::env(FPGA_PROFEN_ROOT)]
set workspace [file join $workspace_root "Vitis" "workspace"]
set platform_name "fmcomms2_axu4ev_hw"
set platform_file [file join $workspace $platform_name "platform.spr"]
set fsbl_elf [file join $workspace $platform_name "zynqmp_fsbl" "executable.elf"]

if {[catch {
  setws $workspace
  platform read $platform_file
  platform active $platform_name

  set current_flags [platform config -extra-compiler-flags fsbl]
  if {[string first "-ffunction-sections" $current_flags] < 0} {
    set current_flags "-ffunction-sections -fdata-sections $current_flags"
    platform config -extra-compiler-flags fsbl $current_flags
  }

  # The FSBL links selected routines from BSP driver objects as well as from
  # the application itself.  Give the BSP objects their own sections so the
  # existing --gc-sections linker option can discard unused driver routines.
  domain active zynqmp_fsbl
  set bsp_flags [bsp config extra_compiler_flags]
  if {[string first "-ffunction-sections" $bsp_flags] < 0} {
    bsp config -append extra_compiler_flags "-ffunction-sections -fdata-sections"
  }

  platform generate -domains zynqmp_fsbl
  if {![file exists $fsbl_elf]} {
    error "FSBL build did not produce '$fsbl_elf'."
  }
} result options]} {
  puts stderr "FAIL: FSBL size-closure build failed: $result"
  exit 1
}

puts "PASS: FSBL generated with section-level garbage collection: $fsbl_elf"
exit 0
