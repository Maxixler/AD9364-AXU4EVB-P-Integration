###############################################################################
## Copyright (C) 2014-2023, 2025 Analog Devices, Inc. All rights reserved.
### SPDX short identifier: ADIBSD
###############################################################################

source ../../../scripts/adi_env.tcl
source $ad_hdl_dir/projects/scripts/adi_project_xilinx.tcl
source $ad_hdl_dir/projects/scripts/adi_board.tcl
set ADI_POST_ROUTE_SCRIPT [file normalize $ad_hdl_dir/projects/scripts/auto_timing_fix_xilinx.tcl]
set BOARD_NAME axu4ev

# Candidate-only FFT integration. The wrapper must prepare the custom core in
# a disposable ADI_GHDL_DIR before project creation; normal/Golden AXU4EV and
# every other FMCOMMS2 carrier keep their original block design.
set ::AXU4EV_FFT_SHADOW_PATH [expr {
  [info exists ::env(AXU4EV_FFT_SHADOW_PATH)] &&
  $::env(AXU4EV_FFT_SHADOW_PATH) eq "1"}]
if {$::AXU4EV_FFT_SHADOW_PATH} {
  if {![info exists ::env(ADI_GHDL_DIR)] ||
      ![file exists [file join $::env(ADI_GHDL_DIR) library axi_ad9364_fft_capture component.xml]]} {
    error "AXU4EV FFT Candidate requires a disposable ADI_GHDL_DIR containing library/axi_ad9364_fft_capture/component.xml."
  }
}

adi_project fmcomms2_${BOARD_NAME}
adi_project_files fmcomms2_${BOARD_NAME} [list \
  "system_top.v" \
  "system_constr.xdc"\
  "$ad_hdl_dir/library/common/ad_iobuf.v" \
  "$ad_hdl_dir/projects/common/${BOARD_NAME}/${BOARD_NAME}_system_constr.xdc" ]

## fmcomms2 design is presenting hold time violations on some paths
## set the strategy to spread logic and help with hold time fixes
set_property strategy Congestion_SpreadLogic_high [get_runs impl_1]

adi_project_run fmcomms2_${BOARD_NAME}
source $ad_hdl_dir/library/axi_ad9361/axi_ad9361_delay.tcl

