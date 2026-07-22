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

foreach bank {0 1} {
  set bus [ipx::get_bus_interfaces spectrum_bank$bank -of_objects $core]
  foreach logical_name {EN ADDR DOUT} {
    require_true "bank$bank $logical_name mapping exists" \
      [expr {[llength [ipx::get_port_maps $logical_name -of_objects $bus]] == 1}]
  }
  set addr [ipx::get_ports bank${bank}_bram_addr -of_objects $core]
  set data [ipx::get_ports bank${bank}_bram_rddata -of_objects $core]
  require_true "bank$bank address width is 11" \
    [expr {[get_property SIZE_LEFT $addr] + 1 == 11}]
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
  axi_ad9364_fft_regs.v ad9364_fft_2048.xci
} {
  require_true "package file group includes $required_file" \
    [expr {[lsearch -exact $packaged_files $required_file] >= 0}]
}

set core_root [file normalize [get_property ROOT_DIRECTORY $core]]
require_true "package root is under disposable output" \
  [expr {[string first [string tolower $output_dir] [string tolower $core_root]] == 0}]
puts "PASS: positive disposable FFT package inspection"
