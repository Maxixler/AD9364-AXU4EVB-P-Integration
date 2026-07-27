if {![info exists ::env(FPGA_PROFEN_ROOT)]} {
  error "FPGA_PROFEN_ROOT is required."
}

set workspace_root [file normalize $::env(FPGA_PROFEN_ROOT)]
set project_script [file normalize [file join [pwd] system_project.tcl]]

proc require_true {label condition} {
  if {!$condition} {
    error "FFT block-design inspection failed: $label"
  }
  puts "PASS: $label"
}

proc require_equal {label actual expected} {
  if {$actual ne $expected} {
    error "FFT block-design inspection failed: $label expected '$expected', got '$actual'"
  }
  puts "PASS: $label = $actual"
}

proc require_one {label objects} {
  require_equal $label [llength $objects] 1
  return [lindex $objects 0]
}

proc sorted_pin_paths_on_net {pin_path} {
  set pin [require_one "pin $pin_path exists" [get_bd_pins -quiet $pin_path]]
  set net [require_one "pin $pin_path has one net" [get_bd_nets -quiet -of_objects $pin]]
  return [lsort [get_property PATH [get_bd_pins -quiet -of_objects $net]]]
}

proc require_pin_net {label pin_path expected_paths} {
  require_equal $label [sorted_pin_paths_on_net $pin_path] [lsort $expected_paths]
}

proc require_pin_net_contains {label pin_path required_paths} {
  set actual [sorted_pin_paths_on_net $pin_path]
  foreach required $required_paths {
    require_true "$label contains $required" [expr {[lsearch -exact $actual $required] >= 0}]
  }
}

proc sorted_intf_paths_on_net {pin_path} {
  set pin [require_one "interface pin $pin_path exists" [get_bd_intf_pins -quiet $pin_path]]
  set net [require_one "interface pin $pin_path has one net" [get_bd_intf_nets -quiet -of_objects $pin]]
  return [lsort [get_property PATH [get_bd_intf_pins -quiet -of_objects $net]]]
}

proc require_intf_net {label pin_path expected_paths} {
  require_equal $label [sorted_intf_paths_on_net $pin_path] [lsort $expected_paths]
}

proc require_addr_seg {segment_name expected_offset expected_range} {
  set segment [require_one "address segment $segment_name exists" \
    [get_bd_addr_segs -quiet sys_ps8/Data/$segment_name]]
  require_equal "$segment_name offset" [format 0x%08X [get_property OFFSET $segment]] $expected_offset
  require_equal "$segment_name range" [format 0x%08X [get_property RANGE $segment]] $expected_range
}

proc require_pin_width {label pin_path expected_width} {
  set pin [require_one "pin $pin_path exists" [get_bd_pins -quiet $pin_path]]
  set actual_width [expr {[get_property LEFT $pin] - [get_property RIGHT $pin] + 1}]
  require_equal $label $actual_width $expected_width
}

require_true "candidate project script exists" [file exists $project_script]
# Structural inspection needs the validated BD graph, not generated HDL/IP
# products. Keep the disposable gate fast and avoid target-generation side
# effects; the Candidate bitstream gate exercises real target generation.
rename generate_target fft_structural_real_generate_target
proc generate_target args {
  puts "INFO: structural gate skipped generate_target $args"
}
rename make_wrapper fft_structural_real_make_wrapper
proc make_wrapper args {
  puts "INFO: structural gate skipped make_wrapper $args"
}
rename import_files fft_structural_real_import_files
proc import_files args {
  puts "INFO: structural gate skipped import_files $args"
}
source $project_script

require_equal "current block design" [current_bd_design] system
set fft_capture [require_one "FFT capture instance" \
  [get_bd_cells -quiet axi_ad9364_fft_capture]]
require_equal "FFT capture SPECTRUM_BANK_DATA_WIDTH configuration" \
  [get_property CONFIG.SPECTRUM_BANK_DATA_WIDTH $fft_capture] 64
foreach bank {0 1} {
  set cell [require_one "FFT bank$bank AXI BRAM controller" \
    [get_bd_cells -quiet axi_ad9364_fft_bram$bank]]
  require_true "FFT bank$bank is an AXI BRAM Controller" \
    [string match {xilinx.com:ip:axi_bram_ctrl:*} [get_property VLNV $cell]]
}

# The four additions below are the only legal taps into the ADI FIFO output.
# Their Golden FIFO->pack endpoints remain present and in the same direction.
require_pin_net "I0 valid shadow tap" util_ad9361_adc_fifo/dout_valid_0 {
  /axi_ad9364_fft_capture/adc_valid
  /util_ad9361_adc_fifo/dout_valid_0
  /util_ad9361_adc_pack/fifo_wr_en
}
require_pin_net "I0 enable shadow tap" util_ad9361_adc_fifo/dout_enable_0 {
  /axi_ad9364_fft_capture/adc_enable
  /util_ad9361_adc_fifo/dout_enable_0
  /util_ad9361_adc_pack/enable_0
}
require_pin_net "I0 data shadow tap" util_ad9361_adc_fifo/dout_data_0 {
  /axi_ad9364_fft_capture/adc_i
  /util_ad9361_adc_fifo/dout_data_0
  /util_ad9361_adc_pack/fifo_wr_data_0
}
require_pin_net "Q0 data shadow tap" util_ad9361_adc_fifo/dout_data_1 {
  /axi_ad9364_fft_capture/adc_q
  /util_ad9361_adc_fifo/dout_data_1
  /util_ad9361_adc_pack/fifo_wr_data_1
}

require_pin_net "Q0 enable Golden topology" util_ad9361_adc_fifo/dout_enable_1 {
  /util_ad9361_adc_fifo/dout_enable_1
  /util_ad9361_adc_pack/enable_1
}
foreach channel {2 3} {
  require_pin_net "channel $channel enable Golden topology" \
    util_ad9361_adc_fifo/dout_enable_$channel [list \
      /util_ad9361_adc_fifo/dout_enable_$channel \
      /util_ad9361_adc_pack/enable_$channel]
  require_pin_net "channel $channel data Golden topology" \
    util_ad9361_adc_fifo/dout_data_$channel [list \
      /util_ad9361_adc_fifo/dout_data_$channel \
      /util_ad9361_adc_pack/fifo_wr_data_$channel]
}

require_intf_net "pack-to-DMAC FIFO interface" util_ad9361_adc_pack/packed_fifo_wr {
  /axi_ad9361_adc_dma/fifo_wr
  /util_ad9361_adc_pack/packed_fifo_wr
}
require_pin_net "pack-to-DMAC sync" util_ad9361_adc_pack/packed_sync {
  /axi_ad9361_adc_dma/sync
  /util_ad9361_adc_pack/packed_sync
}

require_pin_net_contains "FFT CPU clock" axi_ad9364_fft_capture/s_axi_aclk {
  /axi_ad9364_fft_bram0/s_axi_aclk
  /axi_ad9364_fft_bram1/s_axi_aclk
  /axi_ad9364_fft_capture/s_axi_aclk
  /sys_ps8/maxihpm0_lpd_aclk
  /sys_ps8/pl_clk0
  /sys_rstgen/slowest_sync_clk
}
require_pin_net_contains "FFT CPU reset" axi_ad9364_fft_capture/s_axi_aresetn {
  /axi_ad9364_fft_bram0/s_axi_aresetn
  /axi_ad9364_fft_bram1/s_axi_aresetn
  /axi_ad9364_fft_capture/s_axi_aresetn
  /sys_rstgen/peripheral_aresetn
}
require_pin_net_contains "FFT ADC clock" axi_ad9364_fft_capture/adc_clk {
  /axi_ad9361_adc_dma/fifo_wr_clk
  /axi_ad9364_fft_capture/adc_clk
  /util_ad9361_adc_fifo/dout_clk
  /util_ad9361_adc_pack/clk
  /util_ad9361_divclk/clk_out
  /util_ad9361_divclk_reset/slowest_sync_clk
}
require_pin_net_contains "FFT ADC reset" axi_ad9364_fft_capture/adc_resetn {
  /axi_ad9364_fft_capture/adc_resetn
  /util_ad9361_adc_fifo/dout_rstn
  /util_ad9361_divclk_reset/peripheral_aresetn
}
require_pin_net "RF state is constant zero" axi_ad9364_fft_capture/rf_state {
  /axi_ad9364_fft_capture/rf_state
  /axi_ad9364_fft_rf_state_zero/dout
}
require_equal "RF state constant width" \
  [get_property CONFIG.CONST_WIDTH [get_bd_cells axi_ad9364_fft_rf_state_zero]] 3
require_equal "RF state constant value" \
  [get_property CONFIG.CONST_VAL [get_bd_cells axi_ad9364_fft_rf_state_zero]] 0

require_intf_net "FFT control AXI" axi_ad9364_fft_capture/s_axi {
  /axi_ad9364_fft_capture/s_axi
  /axi_hpm0_lpd_interconnect/M04_AXI
}
foreach bank {0 1} {
  require_intf_net "FFT bank$bank AXI" axi_ad9364_fft_bram$bank/S_AXI [list \
    /axi_ad9364_fft_bram$bank/S_AXI \
    /axi_hpm0_lpd_interconnect/M0[expr {$bank + 5}]_AXI]
  require_intf_net "FFT bank$bank native BRAM" \
    axi_ad9364_fft_bram$bank/BRAM_PORTA [list \
      /axi_ad9364_fft_bram$bank/BRAM_PORTA \
      /axi_ad9364_fft_capture/spectrum_bank$bank]
  require_equal "FFT bank$bank controller protocol" \
    [get_property CONFIG.PROTOCOL [get_bd_cells axi_ad9364_fft_bram$bank]] AXI4
  require_equal "FFT bank$bank controller data width" \
    [get_property CONFIG.DATA_WIDTH [get_bd_cells axi_ad9364_fft_bram$bank]] 64
  require_pin_width "FFT bank$bank BRAM byte address width" \
    axi_ad9364_fft_bram$bank/bram_addr_a 14
  require_pin_width "FFT bank$bank BRAM read data width" \
    axi_ad9364_fft_bram$bank/bram_rddata_a 64
  require_pin_width "FFT bank$bank custom BRAM byte address width" \
    axi_ad9364_fft_capture/bank${bank}_bram_addr 14
  require_pin_width "FFT bank$bank custom BRAM read data width" \
    axi_ad9364_fft_capture/bank${bank}_bram_rddata 64
}

require_addr_seg SEG_data_axi_ad9364_fft_capture_s_axi 0x9C440000 0x00001000
require_addr_seg SEG_data_axi_ad9364_fft_bram0_S_AXI 0x9D000000 0x00004000
require_addr_seg SEG_data_axi_ad9364_fft_bram1_S_AXI 0x9D010000 0x00004000

# AXU4EV PS IRQ slots 13/12 remain ADC/DAC DMA. Slot 11 is the FFT addition.
require_pin_net "ADC DMA IRQ slot 13 unchanged" sys_concat_intc_1/In5 {
  /axi_ad9361_adc_dma/irq
  /sys_concat_intc_1/In5
}
require_pin_net "DAC DMA IRQ slot 12 unchanged" sys_concat_intc_1/In4 {
  /axi_ad9361_dac_dma/irq
  /sys_concat_intc_1/In4
}
require_pin_net "FFT IRQ uses previously unused slot 11" sys_concat_intc_1/In3 {
  /axi_ad9364_fft_capture/irq
  /sys_concat_intc_1/In3
}

validate_bd_design
puts "PASS: FFT shadow path is present and the Golden DMA topology is unchanged"
close_project
