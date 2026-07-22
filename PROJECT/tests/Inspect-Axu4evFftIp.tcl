if {![info exists ::env(FPGA_PROFEN_ROOT)]} {
  error "FPGA_PROFEN_ROOT environment variable is required."
}

set workspace_root [string map {\\ /} $::env(FPGA_PROFEN_ROOT)]
set library_dir [file join $workspace_root Related-Docs hdl-main library axi_ad9364_fft_capture]
set fft_config_tcl [file join $library_dir fft_v9_1_config.tcl]
set package_tcl [file join $library_dir axi_ad9364_fft_capture_ip.tcl]

foreach required_file [list $fft_config_tcl $package_tcl] {
  if {![file isfile $required_file]} {
    error "Missing Task 6 production Tcl: '$required_file'."
  }
}

set package_channel [open $package_tcl r]
set package_source [read $package_channel]
close $package_channel
if {![info complete $package_source]} {
  error "Custom-IP package Tcl is not a syntactically complete Tcl script."
}

proc require_equal {label actual expected} {
  if {$actual ne $expected} {
    error "$label mismatch: expected '$expected', got '$actual'."
  }
  puts "PASS: $label = $actual"
}

create_project -in_memory -part xczu4ev-sfvc784-1-i
source $fft_config_tcl

set fft_ips [get_ips -quiet ad9364_fft_2048]
if {[llength $fft_ips] != 1} {
  error "Expected exactly one xFFT IP named 'ad9364_fft_2048'; found [llength $fft_ips]."
}
set fft_ip [lindex $fft_ips 0]

require_equal "xFFT IP definition" [get_property IPDEF $fft_ip] "xilinx.com:ip:xfft:9.1"
require_equal "Transform length" [get_property CONFIG.transform_length $fft_ip] "2048"
require_equal "Architecture" [get_property CONFIG.implementation_options $fft_ip] "pipelined_streaming_io"
require_equal "Data format" [get_property CONFIG.data_format $fft_ip] "fixed_point"
require_equal "Input/output component width" [get_property CONFIG.input_width $fft_ip] "16"
require_equal "Phase factor width" [get_property CONFIG.phase_factor_width $fft_ip] "24"
require_equal "Output ordering" [get_property CONFIG.output_ordering $fft_ip] "natural_order"
require_equal "Rounding mode" [get_property CONFIG.rounding_modes $fft_ip] "convergent_rounding"
require_equal "Scaling arithmetic" [get_property CONFIG.scaling_options $fft_ip] "scaled"
require_equal "Runtime transform length" [get_property CONFIG.run_time_configurable_transform_length $fft_ip] "false"

if {![info exists ::axi_ad9364_fft_capture_fft_axis_config_word]} {
  error "fft_v9_1_config.tcl did not publish the fixed AXIS configuration-word contract."
}
require_equal "AXIS SCALE_SCH" [dict get $::axi_ad9364_fft_capture_fft_axis_config_word SCALE_SCH] "0x6AB"
require_equal "AXIS forward direction" [dict get $::axi_ad9364_fft_capture_fft_axis_config_word FWD_INV] "1"
require_equal "AXIS configuration timing" [dict get $::axi_ad9364_fft_capture_fft_axis_config_word SEND] "once_after_reset_before_first_frame"

set package_status [catch {source $package_tcl} package_error]
if {!$package_status} {
  error "Custom-IP packaging unexpectedly succeeded before the Task 7 top-level exists."
}
if {![string match "*Missing required RTL source*axi_ad9364_fft_capture.v*" $package_error]} {
  error "Custom-IP packaging did not fail fast on the Task 7 top-level: $package_error"
}
puts "PASS: Custom-IP packaging fails fast on the missing Task 7 top-level"

close_project
puts "PASS: FFT v9.1 configuration matches the numerical contract"
