###############################################################################
## Copyright (C) 2017-2023 Analog Devices, Inc. All rights reserved.
### SPDX short identifier: ADIBSD
###############################################################################

set_clock_groups -quiet \
  -group [get_clocks -quiet -of_objects [get_pins -quiet clk_divide_sel_0/O]] \
  -group [get_clocks -quiet -of_objects [get_pins -quiet clk_divide_sel_1/O]] \
  -logically_exclusive
set_false_path -quiet -to [get_pins -quiet i_div_clk_gbuf/S*]
