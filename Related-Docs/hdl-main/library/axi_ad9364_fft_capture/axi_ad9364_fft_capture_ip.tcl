set script_dir [file dirname [file normalize [info script]]]

# Keep this list explicit: missing production RTL must stop packaging before
# ADI's project/package helpers can create any output in the source tree.
set rtl_sources [list \
  [file join $script_dir axi_ad9364_fft_capture.v] \
  [file join $script_dir adc_frame_capture.v] \
  [file join $script_dir adc_frame_replay.v] \
  [file join $script_dir magnitude_peak.v] \
  [file join $script_dir spectrum_pingpong.v] \
  [file join $script_dir fft_command_cdc.v] \
  [file join $script_dir fft_result_cdc.v] \
  [file join $script_dir axi_ad9364_fft_regs.v]]

foreach source_file $rtl_sources {
  if {![file isfile $source_file]} {
    error "Missing required RTL source '$source_file'. Run the matching implementation task before packaging axi_ad9364_fft_capture."
  }
}

set fft_ips [get_ips -quiet ad9364_fft_2048]
if {[llength $fft_ips] != 1} {
  error "Missing required FFT IP 'ad9364_fft_2048'. Source fft_v9_1_config.tcl in Vivado 2020.1 before packaging."
}

set fft_xci [get_property IP_FILE [lindex $fft_ips 0]]
if {$fft_xci eq {} || ![file isfile $fft_xci]} {
  error "Missing required FFT IP artifact for 'ad9364_fft_2048'; generate its XCI before packaging."
}
set fft_xci [file normalize $fft_xci]

# ADI's helper creates the packaging project, so preserve the generated xFFT
# path and close the generation project only after every fail-fast check passes.
close_project
set REQUIRED_VIVADO_VERSION 2020.1
source [file join $script_dir .. .. scripts adi_env.tcl]
source [file join $ad_hdl_dir library scripts adi_ip_xilinx.tcl]

cd $script_dir
adi_ip_create axi_ad9364_fft_capture
adi_ip_files axi_ad9364_fft_capture [concat $rtl_sources [list $fft_xci]]
adi_ip_properties_lite axi_ad9364_fft_capture

set core [ipx::current_core]
set_property display_name {ADI AD9364 FFT Capture} $core
set_property description {Deterministic AD9364 frame capture, FFT, and dual spectrum-bank readout} $core

proc map_ip_port {bus logical_name physical_name} {
  set port_map [ipx::add_port_map $logical_name $bus]
  set_property physical_name $physical_name $port_map
}

# CPU AXI-Lite control/status interface.
set s_axi [ipx::add_bus_interface s_axi $core]
set_property abstraction_type_vlnv xilinx.com:interface:aximm_rtl:1.0 $s_axi
set_property bus_type_vlnv xilinx.com:interface:aximm:1.0 $s_axi
set_property interface_mode slave $s_axi
foreach mapping {
  {AWADDR s_axi_awaddr} {AWPROT s_axi_awprot} {AWVALID s_axi_awvalid} {AWREADY s_axi_awready}
  {WDATA s_axi_wdata} {WSTRB s_axi_wstrb} {WVALID s_axi_wvalid} {WREADY s_axi_wready}
  {BRESP s_axi_bresp} {BVALID s_axi_bvalid} {BREADY s_axi_bready}
  {ARADDR s_axi_araddr} {ARPROT s_axi_arprot} {ARVALID s_axi_arvalid} {ARREADY s_axi_arready}
  {RDATA s_axi_rdata} {RRESP s_axi_rresp} {RVALID s_axi_rvalid} {RREADY s_axi_rready}
} {
  map_ip_port $s_axi [lindex $mapping 0] [lindex $mapping 1]
}
set s_axi_map [ipx::add_memory_map s_axi $core]
set_property slave_memory_map_ref s_axi $s_axi
set s_axi_regs [ipx::add_address_block registers $s_axi_map]
set_property range 256 $s_axi_regs
set_property width 32 $s_axi_regs

# Two independent read-only BRAM slave ports expose complete spectrum banks.
set spectrum_bank0 [ipx::add_bus_interface spectrum_bank0 $core]
set_property abstraction_type_vlnv xilinx.com:interface:bram_rtl:1.0 $spectrum_bank0
set_property bus_type_vlnv xilinx.com:interface:bram:1.0 $spectrum_bank0
set_property interface_mode slave $spectrum_bank0
foreach mapping {{CLK bank0_bram_clk} {RST bank0_bram_rst} {EN bank0_bram_en} {ADDR bank0_bram_addr} {DOUT bank0_bram_rddata}} {
  map_ip_port $spectrum_bank0 [lindex $mapping 0] [lindex $mapping 1]
}

set spectrum_bank1 [ipx::add_bus_interface spectrum_bank1 $core]
set_property abstraction_type_vlnv xilinx.com:interface:bram_rtl:1.0 $spectrum_bank1
set_property bus_type_vlnv xilinx.com:interface:bram:1.0 $spectrum_bank1
set_property interface_mode slave $spectrum_bank1
foreach mapping {{CLK bank1_bram_clk} {RST bank1_bram_rst} {EN bank1_bram_en} {ADDR bank1_bram_addr} {DOUT bank1_bram_rddata}} {
  map_ip_port $spectrum_bank1 [lindex $mapping 0] [lindex $mapping 1]
}

# AD9364 receive tap: one complex {Q,I} word per valid ADC sample.
set adc_tap [ipx::add_bus_interface adc_tap $core]
set_property abstraction_type_vlnv xilinx.com:interface:axis_rtl:1.0 $adc_tap
set_property bus_type_vlnv xilinx.com:interface:axis:1.0 $adc_tap
set_property interface_mode slave $adc_tap
map_ip_port $adc_tap TDATA adc_data
map_ip_port $adc_tap TVALID adc_valid

# Completion/error interrupt output.
set irq [ipx::add_bus_interface irq $core]
set_property abstraction_type_vlnv xilinx.com:signal:interrupt_rtl:1.0 $irq
set_property bus_type_vlnv xilinx.com:signal:interrupt:1.0 $irq
set_property interface_mode master $irq
map_ip_port $irq INTERRUPT irq

ipx::infer_bus_interface s_axi_aclk xilinx.com:signal:clock_rtl:1.0 $core
ipx::infer_bus_interface s_axi_aresetn xilinx.com:signal:reset_rtl:1.0 $core
ipx::infer_bus_interface adc_clk xilinx.com:signal:clock_rtl:1.0 $core
ipx::infer_bus_interface adc_resetn xilinx.com:signal:reset_rtl:1.0 $core
ipx::associate_bus_interfaces -busif s_axi -clock s_axi_aclk $core
ipx::associate_bus_interfaces -clock s_axi_aclk -reset s_axi_aresetn $core
ipx::associate_bus_interfaces -busif adc_tap -clock adc_clk $core
ipx::associate_bus_interfaces -clock adc_clk -reset adc_resetn $core

ipx::update_checksums $core
ipx::save_core $core
