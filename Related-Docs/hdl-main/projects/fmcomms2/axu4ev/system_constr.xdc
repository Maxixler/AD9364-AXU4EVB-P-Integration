###############################################################################
## ALINX AXU4EVB-P FMCOMMS Constraint File
## Auto-generated from user pin mapping
###############################################################################


set_property  -dict {PACKAGE_PIN  L3   IOSTANDARD LVDS     DIFF_TERM TRUE} [get_ports rx_clk_in_p] ; ## FMC_LA00_CC_P
set_property  -dict {PACKAGE_PIN  L2   IOSTANDARD LVDS     DIFF_TERM TRUE} [get_ports rx_clk_in_n] ; ## FMC_LA00_CC_N
set_property  -dict {PACKAGE_PIN  L7   IOSTANDARD LVDS     DIFF_TERM TRUE} [get_ports rx_frame_in_p] ; ## FMC_LA01_CC_P
set_property  -dict {PACKAGE_PIN  L6   IOSTANDARD LVDS     DIFF_TERM TRUE} [get_ports rx_frame_in_n] ; ## FMC_LA01_CC_N
set_property  -dict {PACKAGE_PIN  H4   IOSTANDARD LVDS     DIFF_TERM TRUE} [get_ports rx_data_in_p[0]] ; ## FMC_LA02_P
set_property  -dict {PACKAGE_PIN  H3   IOSTANDARD LVDS     DIFF_TERM TRUE} [get_ports rx_data_in_n[0]] ; ## FMC_LA02_N
set_property  -dict {PACKAGE_PIN  R8   IOSTANDARD LVDS     DIFF_TERM TRUE} [get_ports rx_data_in_p[1]] ; ## FMC_LA03_P
set_property  -dict {PACKAGE_PIN  T8   IOSTANDARD LVDS     DIFF_TERM TRUE} [get_ports rx_data_in_n[1]] ; ## FMC_LA03_N
set_property  -dict {PACKAGE_PIN  L1   IOSTANDARD LVDS     DIFF_TERM TRUE} [get_ports rx_data_in_p[2]] ; ## FMC_LA04_P
set_property  -dict {PACKAGE_PIN  K1   IOSTANDARD LVDS     DIFF_TERM TRUE} [get_ports rx_data_in_n[2]] ; ## FMC_LA04_N
set_property  -dict {PACKAGE_PIN  J6   IOSTANDARD LVDS     DIFF_TERM TRUE} [get_ports rx_data_in_p[3]] ; ## FMC_LA05_P
set_property  -dict {PACKAGE_PIN  H6   IOSTANDARD LVDS     DIFF_TERM TRUE} [get_ports rx_data_in_n[3]] ; ## FMC_LA05_N
set_property  -dict {PACKAGE_PIN  K8   IOSTANDARD LVDS     DIFF_TERM TRUE} [get_ports rx_data_in_p[4]] ; ## FMC_LA06_P
set_property  -dict {PACKAGE_PIN  K7   IOSTANDARD LVDS     DIFF_TERM TRUE} [get_ports rx_data_in_n[4]] ; ## FMC_LA06_N
set_property  -dict {PACKAGE_PIN  P7   IOSTANDARD LVDS     DIFF_TERM TRUE} [get_ports rx_data_in_p[5]] ; ## FMC_LA07_P
set_property  -dict {PACKAGE_PIN  P6   IOSTANDARD LVDS     DIFF_TERM TRUE} [get_ports rx_data_in_n[5]] ; ## FMC_LA07_N
set_property  -dict {PACKAGE_PIN  N7   IOSTANDARD LVDS    } [get_ports tx_clk_out_p] ; ## FMC_LA08_P
set_property  -dict {PACKAGE_PIN  N6   IOSTANDARD LVDS    } [get_ports tx_clk_out_n] ; ## FMC_LA08_N
set_property  -dict {PACKAGE_PIN  N9   IOSTANDARD LVDS    } [get_ports tx_frame_out_p] ; ## FMC_LA09_P
set_property  -dict {PACKAGE_PIN  N8   IOSTANDARD LVDS    } [get_ports tx_frame_out_n] ; ## FMC_LA09_N
set_property  -dict {PACKAGE_PIN  R7   IOSTANDARD LVDS    } [get_ports tx_data_out_p[0]] ; ## FMC_LA11_P
set_property  -dict {PACKAGE_PIN  T7   IOSTANDARD LVDS    } [get_ports tx_data_out_n[0]] ; ## FMC_LA11_N
set_property  -dict {PACKAGE_PIN  K2   IOSTANDARD LVDS    } [get_ports tx_data_out_p[1]] ; ## FMC_LA12_P
set_property  -dict {PACKAGE_PIN  J2   IOSTANDARD LVDS    } [get_ports tx_data_out_n[1]] ; ## FMC_LA12_N
set_property  -dict {PACKAGE_PIN  J7   IOSTANDARD LVDS    } [get_ports tx_data_out_p[2]] ; ## FMC_LA13_P
set_property  -dict {PACKAGE_PIN  H7   IOSTANDARD LVDS    } [get_ports tx_data_out_n[2]] ; ## FMC_LA13_N
set_property  -dict {PACKAGE_PIN  R6   IOSTANDARD LVDS    } [get_ports tx_data_out_p[3]] ; ## FMC_LA10_P
set_property  -dict {PACKAGE_PIN  T6   IOSTANDARD LVDS    } [get_ports tx_data_out_n[3]] ; ## FMC_LA10_N
set_property  -dict {PACKAGE_PIN  J5   IOSTANDARD LVDS    } [get_ports tx_data_out_p[4]] ; ## FMC_LA14_P
set_property  -dict {PACKAGE_PIN  J4   IOSTANDARD LVDS    } [get_ports tx_data_out_n[4]] ; ## FMC_LA14_N
set_property  -dict {PACKAGE_PIN  M8   IOSTANDARD LVDS    } [get_ports tx_data_out_p[5]] ; ## FMC_LA15_P
set_property  -dict {PACKAGE_PIN  L8   IOSTANDARD LVDS    } [get_ports tx_data_out_n[5]] ; ## FMC_LA15_N

set_property  -dict {PACKAGE_PIN  E1   IOSTANDARD LVCMOS18} [get_ports gpio_status[0]] ; ## FMC_LA20_P
set_property  -dict {PACKAGE_PIN  D1   IOSTANDARD LVCMOS18} [get_ports gpio_status[1]] ; ## FMC_LA20_N
set_property  -dict {PACKAGE_PIN  G6   IOSTANDARD LVCMOS18} [get_ports gpio_status[2]] ; ## FMC_LA21_P
set_property  -dict {PACKAGE_PIN  F6   IOSTANDARD LVCMOS18} [get_ports gpio_status[3]] ; ## FMC_LA21_N
set_property  -dict {PACKAGE_PIN  G1   IOSTANDARD LVCMOS18} [get_ports gpio_status[4]] ; ## FMC_LA22_P
set_property  -dict {PACKAGE_PIN  F1   IOSTANDARD LVCMOS18} [get_ports gpio_status[5]] ; ## FMC_LA22_N
set_property  -dict {PACKAGE_PIN  E4   IOSTANDARD LVCMOS18} [get_ports gpio_status[6]] ; ## FMC_LA23_P
set_property  -dict {PACKAGE_PIN  E3   IOSTANDARD LVCMOS18} [get_ports gpio_status[7]] ; ## FMC_LA23_N
set_property  -dict {PACKAGE_PIN  C6   IOSTANDARD LVCMOS18} [get_ports gpio_ctl[0]] ; ## FMC_LA24_P
set_property  -dict {PACKAGE_PIN  B6   IOSTANDARD LVCMOS18} [get_ports gpio_ctl[1]] ; ## FMC_LA24_N
set_property  -dict {PACKAGE_PIN  G3   IOSTANDARD LVCMOS18} [get_ports gpio_ctl[2]] ; ## FMC_LA25_P
set_property  -dict {PACKAGE_PIN  F3   IOSTANDARD LVCMOS18} [get_ports gpio_ctl[3]] ; ## FMC_LA25_N
set_property  -dict {PACKAGE_PIN  F2   IOSTANDARD LVCMOS18} [get_ports gpio_en_agc] ; ## FMC_LA19_P
set_property  -dict {PACKAGE_PIN  E2   IOSTANDARD LVCMOS18} [get_ports gpio_sync] ; ## FMC_LA19_N
set_property  -dict {PACKAGE_PIN  B4   IOSTANDARD LVCMOS18} [get_ports gpio_resetb] ; ## FMC_LA28_P
set_property  -dict {PACKAGE_PIN  K9   IOSTANDARD LVCMOS18} [get_ports enable] ; ## FMC_LA16_P
set_property  -dict {PACKAGE_PIN  J9   IOSTANDARD LVCMOS18} [get_ports txnrx] ; ## FMC_LA16_N

set_property  -dict {PACKAGE_PIN  G8   IOSTANDARD LVCMOS18  PULLTYPE PULLUP} [get_ports spi_csn] ; ## FMC_LA26_P
set_property  -dict {PACKAGE_PIN  F7   IOSTANDARD LVCMOS18} [get_ports spi_clk] ; ## FMC_LA26_N
set_property  -dict {PACKAGE_PIN  G5   IOSTANDARD LVCMOS18} [get_ports spi_mosi] ; ## FMC_LA27_P
set_property  -dict {PACKAGE_PIN  F5   IOSTANDARD LVCMOS18} [get_ports spi_miso] ; ## FMC_LA27_N
create_clock -name rx_clk -period 4.00 [get_ports rx_clk_in_p]
