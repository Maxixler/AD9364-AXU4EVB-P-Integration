if {![info exists ::env(FPGA_PROFEN_ROOT)]} {
  error "FPGA_PROFEN_ROOT environment variable is required."
}

set workspace_root [string map {\\ /} $::env(FPGA_PROFEN_ROOT)]
set library_dir [file join $workspace_root Related-Docs hdl-main library axi_ad9364_fft_capture]
set fft_config_tcl [file join $library_dir fft_v9_1_config.tcl]
foreach required_variable {FFT_PACKAGE_MISSING_SOURCE_TCL FFT_PACKAGE_COMPLETE_TCL} {
  if {![info exists ::env($required_variable)]} {
    error "$required_variable environment variable is required."
  }
}
set missing_source_package_tcl [string map {\\ /} $::env(FFT_PACKAGE_MISSING_SOURCE_TCL)]
set complete_package_tcl [string map {\\ /} $::env(FFT_PACKAGE_COMPLETE_TCL)]

foreach required_file [list $fft_config_tcl $missing_source_package_tcl $complete_package_tcl] {
  if {![file isfile $required_file]} {
    error "Missing Task 6 production Tcl: '$required_file'."
  }
}

set package_channel [open $complete_package_tcl r]
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

proc require_package_failure {label package_tcl expected_pattern} {
  set package_status [catch {source $package_tcl} package_error]
  if {!$package_status} {
    error "$label unexpectedly succeeded."
  }
  if {![string match $expected_pattern $package_error]} {
    error "$label mismatch: expected '$expected_pattern', got '$package_error'."
  }
  puts "PASS: $label = $package_error"
}

require_equal "Vivado version" [version -short] "2020.1"

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
set axis_contract $::axi_ad9364_fft_capture_fft_axis_config_word
foreach contract_key {TDATA_VALUE TDATA_WIDTH FWD_INV FWD_INV_LSB FWD_INV_WIDTH SCALE_SCH SCALE_SCH_LSB SCALE_SCH_WIDTH SEND} {
  if {![dict exists $axis_contract $contract_key]} {
    error "AXIS configuration-word contract is missing '$contract_key'."
  }
}
set axis_tdata [expr {wide([dict get $axis_contract TDATA_VALUE])}]
set fwd_mask [expr {(1 << [dict get $axis_contract FWD_INV_WIDTH]) - 1}]
set scale_mask [expr {(1 << [dict get $axis_contract SCALE_SCH_WIDTH]) - 1}]
require_equal "AXIS TDATA width" [dict get $axis_contract TDATA_WIDTH] "16"
require_equal "AXIS TDATA raw value" [format "0x%04X" $axis_tdata] "0x0D57"
require_equal "AXIS FWD_INV LSB" [dict get $axis_contract FWD_INV_LSB] "0"
require_equal "AXIS FWD_INV width" [dict get $axis_contract FWD_INV_WIDTH] "1"
require_equal "AXIS FWD_INV field value" [dict get $axis_contract FWD_INV] "1"
require_equal "AXIS FWD_INV slice" [expr {($axis_tdata >> [dict get $axis_contract FWD_INV_LSB]) & $fwd_mask}] "1"
require_equal "AXIS SCALE_SCH LSB" [dict get $axis_contract SCALE_SCH_LSB] "1"
require_equal "AXIS SCALE_SCH width" [dict get $axis_contract SCALE_SCH_WIDTH] "12"
require_equal "AXIS SCALE_SCH field value" [dict get $axis_contract SCALE_SCH] "0x6AB"
require_equal "AXIS SCALE_SCH slice" [format "0x%03X" [expr {($axis_tdata >> [dict get $axis_contract SCALE_SCH_LSB]) & $scale_mask}]] "0x6AB"
require_equal "AXIS zero padding" [expr {$axis_tdata >> 13}] "0"
require_equal "AXIS configuration timing" [dict get $::axi_ad9364_fft_capture_fft_axis_config_word SEND] "once_after_reset_before_first_frame"

require_package_failure "Missing-source packaging path" $missing_source_package_tcl \
  "*Missing required RTL source*axi_ad9364_fft_capture.v*"
close_project

create_project -in_memory -part xczu4ev-sfvc784-1-i
require_package_failure "Missing-IP packaging path with future top present" $complete_package_tcl \
  "*Missing required FFT IP 'ad9364_fft_2048'*"
close_project

create_project -in_memory -part xczu4ev-sfvc784-1-i
source $fft_config_tcl
set fft_xci [get_property IP_FILE [get_ips ad9364_fft_2048]]
if {$fft_xci eq {} || ![file isfile $fft_xci]} {
  error "Test setup could not locate the generated xFFT XCI."
}
file delete -force $fft_xci
require_package_failure "Missing-XCI packaging path with future top present" $complete_package_tcl \
  "*Missing required FFT IP artifact for 'ad9364_fft_2048'*"
close_project

puts "PASS: FFT v9.1 configuration matches the numerical contract"
