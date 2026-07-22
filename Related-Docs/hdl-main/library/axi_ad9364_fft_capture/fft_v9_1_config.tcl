# Vivado 2020.1 xFFT v9.1 numerical contract for the AD9364 capture path.
# Task 7 consumes this AXIS configuration contract once after reset, before
# accepting the first frame. FWD_INV=1 fixes the transform direction forward.
if {[version -short] ne "2020.1"} {
  error "fft_v9_1_config.tcl requires Vivado 2020.1; got '[version -short]'."
}

set ::axi_ad9364_fft_capture_fft_axis_config_word [dict create \
  TDATA_VALUE 0x0D57 \
  TDATA_WIDTH 16 \
  FWD_INV 1 \
  FWD_INV_LSB 0 \
  FWD_INV_WIDTH 1 \
  SCALE_SCH 0x6AB \
  SCALE_SCH_LSB 1 \
  SCALE_SCH_WIDTH 12 \
  SEND once_after_reset_before_first_frame]

create_ip -name xfft -vendor xilinx.com -library ip -version 9.1 \
  -module_name ad9364_fft_2048

set fft_ip [get_ips ad9364_fft_2048]
set_property -dict [list \
  CONFIG.transform_length {2048} \
  CONFIG.implementation_options {pipelined_streaming_io} \
  CONFIG.data_format {fixed_point} \
  CONFIG.input_width {16} \
  CONFIG.phase_factor_width {24} \
  CONFIG.output_ordering {natural_order} \
  CONFIG.rounding_modes {convergent_rounding} \
  CONFIG.scaling_options {scaled} \
  CONFIG.run_time_configurable_transform_length {false} \
] $fft_ip
