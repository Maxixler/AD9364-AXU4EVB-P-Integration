# ALINX AXU4EVB-P FMC LPC Pin Mapping for AD9361/AD9364 (FMCOMMS2/3/4)
# -------------------------------------------------------------------------
# BANK 65 & 66 Constraints
# IMPORTANT: Jumper J43 must be set to pins 1-2 to provide 1.8V to BANK 65!

# -------------------------------------------------------------------------
# RX Data Path (ADC) - LVDS
# -------------------------------------------------------------------------
# DATA_CLK (LA00_CC)
set_property -dict {PACKAGE_PIN L3 IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports rx_clk_in_p]
set_property -dict {PACKAGE_PIN L2 IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports rx_clk_in_n]

# RX_FRAME (LA01_CC)
set_property -dict {PACKAGE_PIN L7 IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports rx_frame_in_p]
set_property -dict {PACKAGE_PIN L6 IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports rx_frame_in_n]

# RX_DATA [5:0]
set_property -dict {PACKAGE_PIN H4 IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {rx_data_in_p[0]}] ;# LA02_P
set_property -dict {PACKAGE_PIN H3 IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {rx_data_in_n[0]}] ;# LA02_N
set_property -dict {PACKAGE_PIN R8 IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {rx_data_in_p[1]}] ;# LA03_P
set_property -dict {PACKAGE_PIN T8 IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {rx_data_in_n[1]}] ;# LA03_N
set_property -dict {PACKAGE_PIN L1 IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {rx_data_in_p[2]}] ;# LA04_P
set_property -dict {PACKAGE_PIN K1 IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {rx_data_in_n[2]}] ;# LA04_N
set_property -dict {PACKAGE_PIN J6 IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {rx_data_in_p[3]}] ;# LA05_P
set_property -dict {PACKAGE_PIN H6 IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {rx_data_in_n[3]}] ;# LA05_N
set_property -dict {PACKAGE_PIN K8 IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {rx_data_in_p[4]}] ;# LA06_P
set_property -dict {PACKAGE_PIN K7 IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {rx_data_in_n[4]}] ;# LA06_N
set_property -dict {PACKAGE_PIN P7 IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {rx_data_in_p[5]}] ;# LA07_P
set_property -dict {PACKAGE_PIN P6 IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {rx_data_in_n[5]}] ;# LA07_N

# -------------------------------------------------------------------------
# TX Data Path (DAC) - LVDS
# -------------------------------------------------------------------------
# FB_CLK (LA08)
set_property -dict {PACKAGE_PIN N7 IOSTANDARD LVDS} [get_ports tx_clk_out_p]
set_property -dict {PACKAGE_PIN N6 IOSTANDARD LVDS} [get_ports tx_clk_out_n]

# TX_FRAME (LA09)
set_property -dict {PACKAGE_PIN N9 IOSTANDARD LVDS} [get_ports tx_frame_out_p]
set_property -dict {PACKAGE_PIN N8 IOSTANDARD LVDS} [get_ports tx_frame_out_n]

# TX_DATA [5:0]
set_property -dict {PACKAGE_PIN R7 IOSTANDARD LVDS} [get_ports {tx_data_out_p[0]}] ;# LA11_P
set_property -dict {PACKAGE_PIN T7 IOSTANDARD LVDS} [get_ports {tx_data_out_n[0]}] ;# LA11_N
set_property -dict {PACKAGE_PIN K2 IOSTANDARD LVDS} [get_ports {tx_data_out_p[1]}] ;# LA12_P
set_property -dict {PACKAGE_PIN J2 IOSTANDARD LVDS} [get_ports {tx_data_out_n[1]}] ;# LA12_N
set_property -dict {PACKAGE_PIN J7 IOSTANDARD LVDS} [get_ports {tx_data_out_p[2]}] ;# LA13_P
set_property -dict {PACKAGE_PIN H7 IOSTANDARD LVDS} [get_ports {tx_data_out_n[2]}] ;# LA13_N
set_property -dict {PACKAGE_PIN R6 IOSTANDARD LVDS} [get_ports {tx_data_out_p[3]}] ;# LA10_P
set_property -dict {PACKAGE_PIN T6 IOSTANDARD LVDS} [get_ports {tx_data_out_n[3]}] ;# LA10_N
set_property -dict {PACKAGE_PIN J5 IOSTANDARD LVDS} [get_ports {tx_data_out_p[4]}] ;# LA14_P
set_property -dict {PACKAGE_PIN J4 IOSTANDARD LVDS} [get_ports {tx_data_out_n[4]}] ;# LA14_N
set_property -dict {PACKAGE_PIN M8 IOSTANDARD LVDS} [get_ports {tx_data_out_p[5]}] ;# LA15_P
set_property -dict {PACKAGE_PIN L8 IOSTANDARD LVDS} [get_ports {tx_data_out_n[5]}] ;# LA15_N

# -------------------------------------------------------------------------
# SPI Control Interface - LVCMOS18
# -------------------------------------------------------------------------
set_property -dict {PACKAGE_PIN G8 IOSTANDARD LVCMOS18 PULLTYPE PULLUP} [get_ports spi_csn]  ;# LA26_P (SPI_ENB)
set_property -dict {PACKAGE_PIN F7 IOSTANDARD LVCMOS18} [get_ports spi_clk]  ;# LA26_N
set_property -dict {PACKAGE_PIN G5 IOSTANDARD LVCMOS18} [get_ports spi_mosi] ;# LA27_P (SPI_DI)
set_property -dict {PACKAGE_PIN F5 IOSTANDARD LVCMOS18} [get_ports spi_miso] ;# LA27_N (SPI_DO)

# -------------------------------------------------------------------------
# Control & State Pins - LVCMOS18
# -------------------------------------------------------------------------
set_property -dict {PACKAGE_PIN K9 IOSTANDARD LVCMOS18} [get_ports enable]   ;# LA16_P
set_property -dict {PACKAGE_PIN J9 IOSTANDARD LVCMOS18} [get_ports txnrx]    ;# LA16_N

# -------------------------------------------------------------------------
# GPIOs (CTRL_IN, CTRL_OUT, EN_AGC, SYNC_IN, RESETB)
# Note: In ADI reference designs, these are usually mapped as a GPIO array.
# Update indices below based on your Block Design's GPIO concatenation.
# -------------------------------------------------------------------------
set_property -dict {PACKAGE_PIN F2 IOSTANDARD LVCMOS18} [get_ports gpio_en_agc] ;# LA19_P (EN_AGC)
set_property -dict {PACKAGE_PIN E2 IOSTANDARD LVCMOS18} [get_ports gpio_sync]   ;# LA19_N (SYNC_IN)
set_property -dict {PACKAGE_PIN B4 IOSTANDARD LVCMOS18} [get_ports gpio_resetb] ;# LA28_P (RESETB)

# CTRL_OUT [7:0]
set_property -dict {PACKAGE_PIN E1 IOSTANDARD LVCMOS18} [get_ports {gpio_status[0]}] ;# LA20_P (CTRL_OUT0)
set_property -dict {PACKAGE_PIN D1 IOSTANDARD LVCMOS18} [get_ports {gpio_status[1]}] ;# LA20_N (CTRL_OUT1)
set_property -dict {PACKAGE_PIN G6 IOSTANDARD LVCMOS18} [get_ports {gpio_status[2]}] ;# LA21_P (CTRL_OUT2)
set_property -dict {PACKAGE_PIN F6 IOSTANDARD LVCMOS18} [get_ports {gpio_status[3]}] ;# LA21_N (CTRL_OUT3)
set_property -dict {PACKAGE_PIN G1 IOSTANDARD LVCMOS18} [get_ports {gpio_status[4]}] ;# LA22_P (CTRL_OUT4)
set_property -dict {PACKAGE_PIN F1 IOSTANDARD LVCMOS18} [get_ports {gpio_status[5]}] ;# LA22_N (CTRL_OUT5)
set_property -dict {PACKAGE_PIN E4 IOSTANDARD LVCMOS18} [get_ports {gpio_status[6]}] ;# LA23_P (CTRL_OUT6)
set_property -dict {PACKAGE_PIN E3 IOSTANDARD LVCMOS18} [get_ports {gpio_status[7]}] ;# LA23_N (CTRL_OUT7)

# CTRL_IN [3:0]
set_property -dict {PACKAGE_PIN C6 IOSTANDARD LVCMOS18} [get_ports {gpio_ctl[0]}] ;# LA24_P (CTRL_IN0)
set_property -dict {PACKAGE_PIN B6 IOSTANDARD LVCMOS18} [get_ports {gpio_ctl[1]}] ;# LA24_N (CTRL_IN1)
set_property -dict {PACKAGE_PIN G3 IOSTANDARD LVCMOS18} [get_ports {gpio_ctl[2]}] ;# LA25_P (CTRL_IN2)
set_property -dict {PACKAGE_PIN F3 IOSTANDARD LVCMOS18} [get_ports {gpio_ctl[3]}] ;# LA25_N (CTRL_IN3)
set_property IOSTANDARD LVCMOS18 [get_ports gpio_*]

# -------------------------------------------------------------------------
# AD9364 receive source-synchronous interface timing
# -------------------------------------------------------------------------
create_clock -name rx_clk -period 4.00 [get_ports rx_clk_in_p]
