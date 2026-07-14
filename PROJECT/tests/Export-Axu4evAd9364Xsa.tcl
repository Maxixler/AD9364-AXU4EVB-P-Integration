if {![info exists ::env(FPGA_PROFEN_ROOT)]} {
  error "FPGA_PROFEN_ROOT environment variable is required."
}

set workspace_root [string map {\\ /} $::env(FPGA_PROFEN_ROOT)]
set project_dir [file join $workspace_root "Related-Docs" "hdl-main" "projects" "fmcomms2" "axu4ev"]
set project_file [file join $project_dir "fmcomms2_axu4ev.xpr"]
set output_xsa [file join $workspace_root "PROJECT" "verification" "vivado" "system_top.xsa"]

open_project $project_file

set impl_status [get_property STATUS [get_runs impl_1]]
if {![string match "*write_bitstream Complete!*" $impl_status]} {
  error "Refusing XSA export because impl_1 is not complete: '$impl_status'."
}

open_run impl_1
if {[llength [get_clocks -quiet rx_clk]] != 1} {
  error "Refusing XSA export because implemented rx_clk is missing."
}

write_hw_platform -fixed -include_bit -force $output_xsa
if {![file exists $output_xsa]} {
  error "XSA export did not create '$output_xsa'."
}

puts "PASS: Exported verified hardware platform = $output_xsa"
close_project
