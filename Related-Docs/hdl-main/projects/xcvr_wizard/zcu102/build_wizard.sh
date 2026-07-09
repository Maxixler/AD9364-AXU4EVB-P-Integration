#!/bin/bash
export PATH="/cygdrive/c/Xilinx/Vivado/2020.1/bin:$PATH"
cd /cygdrive/c/Users/DELL/Desktop/Yazilim/FPGA-Profen/Related-Docs/hdl-main/projects/xcvr_wizard/zcu102
make LANE_RATE=10 REF_CLK=250 PLL_TYPE=QPLL0
