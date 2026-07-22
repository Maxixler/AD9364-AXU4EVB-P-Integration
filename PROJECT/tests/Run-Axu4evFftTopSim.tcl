if {$argc != 2} {
  error "Usage: Run-Axu4evFftTopSim.tcl <repository-root> <temporary-work-directory>"
}

set root [file normalize [lindex $argv 0]]
set work [file normalize [lindex $argv 1]]
set rtl_root [file join $root Related-Docs hdl-main library axi_ad9364_fft_capture]
set tb_root [file join $root PROJECT verification fft rtl]
set vector_root [file join $root PROJECT verification fft vectors]

create_project fft_top_sim [file join $work project] -part xczu4ev-sfvc784-1-i -force
set_property target_simulator XSim [current_project]
source [file join $rtl_root fft_v9_1_config.tcl]
generate_target simulation [get_ips ad9364_fft_2048]

add_files -norecurse [list \
  [file join $rtl_root axi_ad9364_fft_capture.v] \
  [file join $rtl_root adc_frame_capture.v] \
  [file join $rtl_root adc_frame_replay.v] \
  [file join $rtl_root magnitude_peak.v] \
  [file join $rtl_root spectrum_pingpong.v] \
  [file join $rtl_root fft_command_cdc.v] \
  [file join $rtl_root fft_result_cdc.v] \
  [file join $rtl_root axi_ad9364_fft_regs.v]]
add_files -fileset sim_1 -norecurse [file join $tb_root tb_axi_ad9364_fft_capture.sv]
foreach vector_file [glob -nocomplain [file join $vector_root *.hex]] {
  add_files -fileset sim_1 -norecurse $vector_file
  set_property FILE_TYPE {Memory Initialization Files} [get_files $vector_file]
}
set_property top tb_axi_ad9364_fft_capture [get_filesets sim_1]
set_property -name {xsim.simulate.runtime} -value {all} -objects [get_filesets sim_1]
set_property -name {xsim.elaborate.debug_level} -value {off} -objects [get_filesets sim_1]

puts "TOP_SIM_STAGE: generating XSIM scripts"
launch_simulation -simset sim_1 -mode behavioral -scripts_only
puts "TOP_SIM_STAGE: XSIM scripts ready"
close_project
