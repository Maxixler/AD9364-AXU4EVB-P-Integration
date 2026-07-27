if {![info exists ::env(FPGA_PROFEN_ROOT)] ||
    ![info exists ::env(FFT_PACKAGE_OUTPUT_DIR)]} {
  error "FPGA_PROFEN_ROOT and FFT_PACKAGE_OUTPUT_DIR are required."
}

set root [file normalize $::env(FPGA_PROFEN_ROOT)]
set output_dir [file normalize $::env(FFT_PACKAGE_OUTPUT_DIR)]
set library_dir [file join $root Related-Docs hdl-main library axi_ad9364_fft_capture]
set config_tcl [file join $library_dir fft_v9_1_config.tcl]
set package_tcl [file join $library_dir axi_ad9364_fft_capture_ip.tcl]

proc require_true {label condition} {
  if {!$condition} { error "Positive package inspection failed: $label" }
  puts "PASS: $label"
}

create_project fft_package_seed [file join $output_dir seed] -part xczu4ev-sfvc784-1-i -force
source $config_tcl
generate_target all [get_ips ad9364_fft_2048]

# Candidate builds must remain usable after the source worktree is gone. ADI's
# helper normally references files in place, so opt into Vivado's import_files
# package mode when the disposable Candidate wrapper requests it.
if {[info exists ::env(FFT_PACKAGE_IMPORT_FILES)] &&
    $::env(FFT_PACKAGE_IMPORT_FILES) eq "1"} {
  rename ipx::package_project ipx::package_project_without_import
  proc ipx::package_project {args} {
    return [uplevel 1 [list ipx::package_project_without_import -import_files {*}$args]]
  }
}
source $package_tcl

set core [ipx::current_core]
require_true "packaged core is open" [expr {$core ne {}}]
foreach bus_name {s_axi spectrum_bank0 spectrum_bank1 irq} {
  require_true "bus interface $bus_name exists" \
    [expr {[llength [ipx::get_bus_interfaces $bus_name -of_objects $core]] == 1}]
}
foreach port_name {adc_valid adc_enable adc_i adc_q rf_state} {
  require_true "discrete ADC port $port_name exists" \
    [expr {[llength [ipx::get_ports $port_name -of_objects $core]] == 1}]
}
require_true "legacy adc_data port is absent" \
  [expr {[llength [ipx::get_ports adc_data -of_objects $core]] == 0}]
set bank_data_width_model [ipx::get_hdl_parameters -of $core \
  SPECTRUM_BANK_DATA_WIDTH]
require_true "SPECTRUM_BANK_DATA_WIDTH model parameter exists" \
  [expr {[llength $bank_data_width_model] == 1}]
require_true "SPECTRUM_BANK_DATA_WIDTH model parameter is 64 bits" \
  [expr {[get_property VALUE $bank_data_width_model] eq "64"}]

foreach bank {0 1} {
  set bus [ipx::get_bus_interfaces spectrum_bank$bank -of_objects $core]
  set mem_width [ipx::get_bus_parameters MEM_WIDTH -of_objects $bus]
  require_true "bank$bank publishes one MEM_WIDTH bus parameter" \
    [expr {[llength $mem_width] == 1}]
  require_true "bank$bank MEM_WIDTH is 64 bits" \
    [expr {[get_property VALUE $mem_width] eq "64"}]
  require_true "bank$bank MEM_WIDTH depends on the model parameter" \
    [expr {[get_property VALUE_RESOLVE_TYPE $mem_width] eq "dependent"}]
  require_true "bank$bank MEM_WIDTH dependency targets SPECTRUM_BANK_DATA_WIDTH" \
    [expr {[string first "MODELPARAM_VALUE.SPECTRUM_BANK_DATA_WIDTH" \
      [get_property VALUE_DEPENDENCY $mem_width]] >= 0}]
  foreach logical_name {EN ADDR DOUT} {
    require_true "bank$bank $logical_name mapping exists" \
      [expr {[llength [ipx::get_port_maps $logical_name -of_objects $bus]] == 1}]
  }
  set addr [ipx::get_ports bank${bank}_bram_addr -of_objects $core]
  set data [ipx::get_ports bank${bank}_bram_rddata -of_objects $core]
  require_true "bank$bank byte address width is 14" \
    [expr {[get_property SIZE_LEFT $addr] + 1 == 14}]
  require_true "bank$bank data width is 64" \
    [expr {[get_property SIZE_LEFT $data] + 1 == 64}]
}

set packaged_files {}
foreach file_group [ipx::get_file_groups -of_objects $core] {
  foreach packaged_file [ipx::get_files -of_objects $file_group] {
    lappend packaged_files [file tail [get_property NAME $packaged_file]]
  }
}
foreach required_file {
  axi_ad9364_fft_capture.v adc_frame_capture.v adc_frame_replay.v
  magnitude_peak.v spectrum_pingpong.v fft_command_cdc.v fft_result_cdc.v
  axi_ad9364_fft_regs.v axi_ad9364_fft_capture_constr.xdc ad9364_fft_2048.xci
} {
  require_true "package file group includes $required_file" \
    [expr {[lsearch -exact $packaged_files $required_file] >= 0}]
}

set constraint_path [file join $library_dir axi_ad9364_fft_capture_constr.xdc]
set constraint_handle [open $constraint_path r]
set constraint_text [read $constraint_handle]
close $constraint_handle
require_true "CDC constraints avoid blanket clock groups" \
  [expr {![regexp {set_clock_groups} $constraint_text]}]
require_true "CDC constraints retain a bundled-data max delay" \
  [regexp {set_max_delay[[:space:]]+8\.000[[:space:]]+-datapath_only} $constraint_text]
require_true "CDC constraints remove only bundled-data hold timing" \
  [regexp {set_false_path[[:space:]]+-hold} $constraint_text]
require_true "CDC constraints target first-stage synchronizer D pins" \
  [expr {[regexp {sync1_reg} $constraint_text] && [regexp {/D\$} $constraint_text]}]
require_true "CDC constraints use only XDC-safe straight-line commands" \
  [expr {![regexp {(^|\n)[[:space:]]*(if|foreach|lappend)[[:space:]]} $constraint_text]}]

set core_root [file normalize [get_property ROOT_DIRECTORY $core]]
require_true "package root is under disposable output" \
  [expr {[string first [string tolower $output_dir] [string tolower $core_root]] == 0}]
puts "PASS: positive disposable FFT package inspection"

if {[llength [info commands ipx::package_project_without_import]] == 1} {
  rename ipx::package_project {}
  rename ipx::package_project_without_import ipx::package_project
}
