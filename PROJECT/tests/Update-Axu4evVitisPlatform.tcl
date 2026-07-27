if {![info exists ::env(FPGA_PROFEN_ROOT)]} {
  error "FPGA_PROFEN_ROOT environment variable is required."
}

set workspace_root [string map {\\ /} $::env(FPGA_PROFEN_ROOT)]
set workspace [file join $workspace_root "Vitis" "workspace"]
set platform_name "fmcomms2_axu4ev_hw"
set platform_file [file join $workspace $platform_name "platform.spr"]
set xsa_file [file join $workspace_root "Related-Docs" "hdl-main" "projects" "fmcomms2" "axu4ev" "fmcomms2_axu4ev.sdk" "system_top.xsa"]

if {![file exists $xsa_file]} {
  error "Verified XSA handoff is missing at '$xsa_file'."
}
if {![file exists $platform_file]} {
  error "Existing Vitis platform definition is missing at '$platform_file'."
}

if {[catch {
  setws $workspace
  platform read $platform_file
  platform active $platform_name
  platform config -updatehw $xsa_file

  set fsbl_flags [platform config -extra-compiler-flags fsbl]
  if {[string first "-ffunction-sections" $fsbl_flags] < 0} {
    platform config -extra-compiler-flags fsbl \
      "-ffunction-sections -fdata-sections $fsbl_flags"
  }

  platform generate
} result options]} {
  puts stderr "FAIL: Vitis platform update failed: $result"
  exit 1
}

puts "PASS: Updated and generated Vitis platform '$platform_name' from '$xsa_file'."
exit 0
