if {![info exists ::env(FPGA_PROFEN_ROOT)]} {
  error "FPGA_PROFEN_ROOT environment variable is required."
}

set workspace_root [string map {\\ /} $::env(FPGA_PROFEN_ROOT)]
set project_dir [file join $workspace_root "Related-Docs" "hdl-main" "projects" "fmcomms2" "axu4ev"]
set project_file [file join $project_dir "fmcomms2_axu4ev.xpr"]
set target_xdc [file join $project_dir "system_constr.xdc"]
set report_dir [file join $workspace_root "PROJECT" "verification" "vivado"]
set bitstream_file [file join $project_dir "fmcomms2_axu4ev.runs" "impl_1" "system_top.bit"]
set verify_only [expr {[info exists ::env(FPGA_PROFEN_VERIFY_ONLY)] && $::env(FPGA_PROFEN_VERIFY_ONLY) eq "1"}]

proc require_equal {label actual expected} {
  if {$actual ne $expected} {
    error "$label mismatch: expected '$expected', got '$actual'"
  }
  puts "PASS: $label = $actual"
}

proc require_port_property {port_name property_name expected} {
  set port [get_ports -quiet $port_name]
  if {[llength $port] != 1} {
    error "Expected one implemented port named '$port_name'; found [llength $port]."
  }
  require_equal "$port_name $property_name" [get_property $property_name $port] $expected
}

if {![file exists $project_file]} {
  error "Vivado project does not exist at '$project_file'."
}
file mkdir $report_dir

open_project $project_file
require_equal "Part" [get_property PART [current_project]] "xczu4ev-sfvc784-1-i"
require_equal "Top" [get_property TOP [current_fileset]] "system_top"

set active_xdc [get_files -quiet $target_xdc]
if {[llength $active_xdc] != 1} {
  error "Expected active XDC '$target_xdc'; found [llength $active_xdc]."
}
require_equal "XDC used in synthesis" [get_property USED_IN_SYNTHESIS $active_xdc] "1"
require_equal "XDC used in implementation" [get_property USED_IN_IMPLEMENTATION $active_xdc] "1"

set locked_ips [get_ips -quiet -filter {IS_LOCKED == 1}]
if {[llength $locked_ips] > 0} {
  report_ip_status -file [file join $report_dir "ip_status_before_build.rpt"] -force
  error "Locked IP detected before build: $locked_ips"
}

if {!$verify_only} {
  puts "INFO: Resetting synth_1 so the edited XDC is guaranteed to be consumed."
  reset_runs synth_1
  launch_runs impl_1 -to_step write_bitstream -jobs 4
  wait_on_run impl_1
} else {
  puts "INFO: Verify-only mode; preserving the completed implementation run."
}

set impl_status [get_property STATUS [get_runs impl_1]]
set impl_progress [get_property PROGRESS [get_runs impl_1]]
puts "INFO: impl_1 status='$impl_status' progress='$impl_progress'"
if {![string match "*write_bitstream Complete!*" $impl_status]} {
  error "Implementation did not complete write_bitstream: status='$impl_status', progress='$impl_progress'."
}
if {![file exists $bitstream_file]} {
  error "Bitstream is missing after a completed run: '$bitstream_file'."
}

open_run impl_1

report_drc -file [file join $report_dir "system_top_drc.rpt"] -force
report_timing_summary -delay_type min_max -report_unconstrained -max_paths 20 -file [file join $report_dir "system_top_timing_summary.rpt"]
check_timing -verbose -file [file join $report_dir "system_top_check_timing.rpt"]
report_clock_interaction -delay_type min_max -file [file join $report_dir "system_top_clock_interaction.rpt"]
report_clocks -file [file join $report_dir "system_top_clocks.rpt"]
report_io -file [file join $report_dir "system_top_io.rpt"]

set rx_clocks [get_clocks -quiet rx_clk]
if {[llength $rx_clocks] != 1} {
  error "Expected exactly one implemented rx_clk; found [llength $rx_clocks]."
}
require_equal "rx_clk period" [format "%.3f" [get_property PERIOD $rx_clocks]] "4.000"

foreach {port pin} {
  rx_frame_in_p L7
  rx_frame_in_n L6
  tx_clk_out_p N7
  tx_clk_out_n N6
} {
  require_port_property $port PACKAGE_PIN $pin
}

set rx_ports {rx_clk_in_p rx_clk_in_n rx_frame_in_p rx_frame_in_n}
for {set index 0} {$index < 6} {incr index} {
  lappend rx_ports "rx_data_in_p\[$index\]"
  lappend rx_ports "rx_data_in_n\[$index\]"
}
foreach port $rx_ports {
  require_port_property $port DIFF_TERM_ADV TERM_100
}
require_port_property spi_csn PULLTYPE PULLUP

set drc_errors [get_drc_violations -quiet -filter {SEVERITY == Error}]
if {[llength $drc_errors] > 0} {
  error "DRC error violations remain after implementation: $drc_errors"
}

puts "PASS: Bitstream = $bitstream_file"
puts "PASS: Vivado implementation evidence = $report_dir"
close_project
