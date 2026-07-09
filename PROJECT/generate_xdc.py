import re

fmc_zed = """
set_property  -dict {PACKAGE_PIN  M19  IOSTANDARD LVDS_25 DIFF_TERM TRUE} [get_ports rx_clk_in_p]        ; ## G6   FMC_LPC_LA00_CC_P
set_property  -dict {PACKAGE_PIN  M20  IOSTANDARD LVDS_25 DIFF_TERM TRUE} [get_ports rx_clk_in_n]        ; ## G7   FMC_LPC_LA00_CC_N
set_property  -dict {PACKAGE_PIN  N19  IOSTANDARD LVDS_25 DIFF_TERM TRUE} [get_ports rx_frame_in_p]      ; ## D8   FMC_LPC_LA01_CC_P
set_property  -dict {PACKAGE_PIN  N20  IOSTANDARD LVDS_25 DIFF_TERM TRUE} [get_ports rx_frame_in_n]      ; ## D9   FMC_LPC_LA01_CC_N
set_property  -dict {PACKAGE_PIN  P17  IOSTANDARD LVDS_25 DIFF_TERM TRUE} [get_ports rx_data_in_p[0]]    ; ## H7   FMC_LPC_LA02_P
set_property  -dict {PACKAGE_PIN  P18  IOSTANDARD LVDS_25 DIFF_TERM TRUE} [get_ports rx_data_in_n[0]]    ; ## H8   FMC_LPC_LA02_N
set_property  -dict {PACKAGE_PIN  N22  IOSTANDARD LVDS_25 DIFF_TERM TRUE} [get_ports rx_data_in_p[1]]    ; ## G9   FMC_LPC_LA03_P
set_property  -dict {PACKAGE_PIN  P22  IOSTANDARD LVDS_25 DIFF_TERM TRUE} [get_ports rx_data_in_n[1]]    ; ## G10  FMC_LPC_LA03_N
set_property  -dict {PACKAGE_PIN  M21  IOSTANDARD LVDS_25 DIFF_TERM TRUE} [get_ports rx_data_in_p[2]]    ; ## H10  FMC_LPC_LA04_P
set_property  -dict {PACKAGE_PIN  M22  IOSTANDARD LVDS_25 DIFF_TERM TRUE} [get_ports rx_data_in_n[2]]    ; ## H11  FMC_LPC_LA04_N
set_property  -dict {PACKAGE_PIN  J18  IOSTANDARD LVDS_25 DIFF_TERM TRUE} [get_ports rx_data_in_p[3]]    ; ## D11  FMC_LPC_LA05_P
set_property  -dict {PACKAGE_PIN  K18  IOSTANDARD LVDS_25 DIFF_TERM TRUE} [get_ports rx_data_in_n[3]]    ; ## D12  FMC_LPC_LA05_N
set_property  -dict {PACKAGE_PIN  L21  IOSTANDARD LVDS_25 DIFF_TERM TRUE} [get_ports rx_data_in_p[4]]    ; ## C10  FMC_LPC_LA06_P
set_property  -dict {PACKAGE_PIN  L22  IOSTANDARD LVDS_25 DIFF_TERM TRUE} [get_ports rx_data_in_n[4]]    ; ## C11  FMC_LPC_LA06_N
set_property  -dict {PACKAGE_PIN  T16  IOSTANDARD LVDS_25 DIFF_TERM TRUE} [get_ports rx_data_in_p[5]]    ; ## H13  FMC_LPC_LA07_P
set_property  -dict {PACKAGE_PIN  T17  IOSTANDARD LVDS_25 DIFF_TERM TRUE} [get_ports rx_data_in_n[5]]    ; ## H14  FMC_LPC_LA07_N
set_property  -dict {PACKAGE_PIN  J21  IOSTANDARD LVDS_25} [get_ports tx_clk_out_p]                      ; ## G12  FMC_LPC_LA08_P
set_property  -dict {PACKAGE_PIN  J22  IOSTANDARD LVDS_25} [get_ports tx_clk_out_n]                      ; ## G13  FMC_LPC_LA08_N
set_property  -dict {PACKAGE_PIN  R20  IOSTANDARD LVDS_25} [get_ports tx_frame_out_p]                    ; ## D14  FMC_LPC_LA09_P
set_property  -dict {PACKAGE_PIN  R21  IOSTANDARD LVDS_25} [get_ports tx_frame_out_n]                    ; ## D15  FMC_LPC_LA09_N
set_property  -dict {PACKAGE_PIN  N17  IOSTANDARD LVDS_25} [get_ports tx_data_out_p[0]]                  ; ## H16  FMC_LPC_LA11_P
set_property  -dict {PACKAGE_PIN  N18  IOSTANDARD LVDS_25} [get_ports tx_data_out_n[0]]                  ; ## H17  FMC_LPC_LA11_N
set_property  -dict {PACKAGE_PIN  P20  IOSTANDARD LVDS_25} [get_ports tx_data_out_p[1]]                  ; ## G15  FMC_LPC_LA12_P
set_property  -dict {PACKAGE_PIN  P21  IOSTANDARD LVDS_25} [get_ports tx_data_out_n[1]]                  ; ## G16  FMC_LPC_LA12_N
set_property  -dict {PACKAGE_PIN  L17  IOSTANDARD LVDS_25} [get_ports tx_data_out_p[2]]                  ; ## D17  FMC_LPC_LA13_P
set_property  -dict {PACKAGE_PIN  M17  IOSTANDARD LVDS_25} [get_ports tx_data_out_n[2]]                  ; ## D18  FMC_LPC_LA13_N
set_property  -dict {PACKAGE_PIN  R19  IOSTANDARD LVDS_25} [get_ports tx_data_out_p[3]]                  ; ## C14  FMC_LPC_LA10_P
set_property  -dict {PACKAGE_PIN  T19  IOSTANDARD LVDS_25} [get_ports tx_data_out_n[3]]                  ; ## C15  FMC_LPC_LA10_N
set_property  -dict {PACKAGE_PIN  K19  IOSTANDARD LVDS_25} [get_ports tx_data_out_p[4]]                  ; ## C18  FMC_LPC_LA14_P
set_property  -dict {PACKAGE_PIN  K20  IOSTANDARD LVDS_25} [get_ports tx_data_out_n[4]]                  ; ## C19  FMC_LPC_LA14_N
set_property  -dict {PACKAGE_PIN  J16  IOSTANDARD LVDS_25} [get_ports tx_data_out_p[5]]                  ; ## H19  FMC_LPC_LA15_P
set_property  -dict {PACKAGE_PIN  J17  IOSTANDARD LVDS_25} [get_ports tx_data_out_n[5]]                  ; ## H20  FMC_LPC_LA15_N

set_property  -dict {PACKAGE_PIN  G20  IOSTANDARD LVCMOS25} [get_ports gpio_status[0]]                   ; ## G21  FMC_LPC_LA20_P
set_property  -dict {PACKAGE_PIN  G21  IOSTANDARD LVCMOS25} [get_ports gpio_status[1]]                   ; ## G22  FMC_LPC_LA20_N
set_property  -dict {PACKAGE_PIN  E19  IOSTANDARD LVCMOS25} [get_ports gpio_status[2]]                   ; ## H25  FMC_LPC_LA21_P
set_property  -dict {PACKAGE_PIN  E20  IOSTANDARD LVCMOS25} [get_ports gpio_status[3]]                   ; ## H26  FMC_LPC_LA21_N
set_property  -dict {PACKAGE_PIN  G19  IOSTANDARD LVCMOS25} [get_ports gpio_status[4]]                   ; ## G24  FMC_LPC_LA22_P
set_property  -dict {PACKAGE_PIN  F19  IOSTANDARD LVCMOS25} [get_ports gpio_status[5]]                   ; ## G25  FMC_LPC_LA22_N
set_property  -dict {PACKAGE_PIN  E15  IOSTANDARD LVCMOS25} [get_ports gpio_status[6]]                   ; ## D23  FMC_LPC_LA23_P
set_property  -dict {PACKAGE_PIN  D15  IOSTANDARD LVCMOS25} [get_ports gpio_status[7]]                   ; ## D24  FMC_LPC_LA23_N
set_property  -dict {PACKAGE_PIN  A18  IOSTANDARD LVCMOS25} [get_ports gpio_ctl[0]]                      ; ## H28  FMC_LPC_LA24_P
set_property  -dict {PACKAGE_PIN  A19  IOSTANDARD LVCMOS25} [get_ports gpio_ctl[1]]                      ; ## H29  FMC_LPC_LA24_N
set_property  -dict {PACKAGE_PIN  D22  IOSTANDARD LVCMOS25} [get_ports gpio_ctl[2]]                      ; ## G27  FMC_LPC_LA25_P
set_property  -dict {PACKAGE_PIN  C22  IOSTANDARD LVCMOS25} [get_ports gpio_ctl[3]]                      ; ## G28  FMC_LPC_LA25_N
set_property  -dict {PACKAGE_PIN  G15  IOSTANDARD LVCMOS25} [get_ports gpio_en_agc]                      ; ## H22  FMC_LPC_LA19_P
set_property  -dict {PACKAGE_PIN  G16  IOSTANDARD LVCMOS25} [get_ports gpio_sync]                        ; ## H23  FMC_LPC_LA19_N
set_property  -dict {PACKAGE_PIN  A16  IOSTANDARD LVCMOS25} [get_ports gpio_resetb]                      ; ## H31  FMC_LPC_LA28_P
set_property  -dict {PACKAGE_PIN  J20  IOSTANDARD LVCMOS25} [get_ports enable]                           ; ## G18  FMC_LPC_LA16_P
set_property  -dict {PACKAGE_PIN  K21  IOSTANDARD LVCMOS25} [get_ports txnrx]                            ; ## G19  FMC_LPC_LA16_N

set_property  -dict {PACKAGE_PIN  F18  IOSTANDARD LVCMOS25  PULLTYPE PULLUP} [get_ports spi_csn]         ; ## D26  FMC_LPC_LA26_P
set_property  -dict {PACKAGE_PIN  E18  IOSTANDARD LVCMOS25} [get_ports spi_clk]                          ; ## D27  FMC_LPC_LA26_N
set_property  -dict {PACKAGE_PIN  E21  IOSTANDARD LVCMOS25} [get_ports spi_mosi]                         ; ## C26  FMC_LPC_LA27_P
set_property  -dict {PACKAGE_PIN  D21  IOSTANDARD LVCMOS25} [get_ports spi_miso]                         ; ## C27  FMC_LPC_LA27_N
"""

user_mapping = """
H4 FMC_CLK0_P B65_L11_P K4 FMC参考第1路参考时钟P
H5 FMC_CLK0_N B65_L11_N K3 FMC参考第1路参考时钟N
G2 FMC_CLK1_P B65_L14_P M6 FMC参考第2路参考时钟P
G3 FMC_CLK1_N B65_L14_N L5 FMC参考第2路参考时钟N
G6 FMC_LA00_CC_P B65_L12_P L3 FMC参考第0路数据（时钟）P
G7 FMC_LA00_CC_N B65_L12_N L2 FMC参考第0路数据（时钟）N
D8 FMC_LA01_CC_P B65_L13_P L7 FMC参考第1路数据（时钟）P
D9 FMC_LA01_CC_N B65_L13_N L6 FMC参考第1路数据（时钟）N
H7 FMC_LA02_P B65_L10_P H4 FMC参考第2路数据P
H8 FMC_LA02_N B65_L10_N H3 FMC参考第2路数据N
G9 FMC_LA03_P B65_L4_P R8 FMC参考第3路数据P
G10 FMC_LA03_N B65_L4_N T8 FMC参考第3路数据N
H10 FMC_LA04_P B65_L7_P L1 FMC参考第4路数据P
H11 FMC_LA04_N B65_L7_N K1 FMC参考第4路数据NAXU4EVB-P 用户手册
D11 FMC_LA05_P B65_L20_P J6 FMC参考第5路数据P
D12 FMC_LA05_N B65_L20_N H6 FMC参考第5路数据N
C10 FMC_LA06_P B65_L22_P K8 FMC参考第6路数据P
C11 FMC_LA06_N B65_L22_N K7 FMC参考第6路数据N
H13 FMC_LA07_P B65_L16_P P7 FMC参考第7路数据P
H14 FMC_LA07_N B65_L16_N P6 FMC参考第7路数据N
G12 FMC_LA08_P B65_L15_P N7 FMC参考第8路数据P
G13 FMC_LA08_N B65_L15_N N6 FMC参考第8路数据N
D14 FMC_LA09_P B65_L17_P N9 FMC参考第9路数据P
D15 FMC_LA09_N B65_L17_N N8 FMC参考第9路数据N
C14 FMC_LA10_P B65_L6_P R6 FMC参考第10路数据P
C15 FMC_LA10_N B65_L6_N T6 FMC参考第10路数据N
H16 FMC_LA11_P B65_L5_P R7 FMC参考第11路数据P
H17 FMC_LA11_N B65_L5_N T7 FMC参考第11路数据N
G15 FMC_LA12_P B65_L9_P K2 FMC参考第12路数据P
G16 FMC_LA12_N B65_L9_N J2 FMC参考第12路数据N
D17 FMC_LA13_P B65_L21_P J7 FMC参考第13路数据P
D18 FMC_LA13_N B65_L21_N H7 FMC参考第13路数据N
C18 FMC_LA14_P B65_L19_P J5 FMC参考第14路数据P
C19 FMC_LA14_N B65_L19_N J4 FMC参考第14路数据N
H19 FMC_LA15_P B65_L18_P M8 FMC参考第15路数据P
H20 FMC_LA15_N B65_L18_N L8 FMC参考第15路数据N
G18 FMC_LA16_P B65_L23_P K9 FMC参考第16路数据P
G19 FMC_LA16_N B65_L23_N J9 FMC参考第16路数据N
D20 FMC_LA17_CC_P B66_L11_P D4 FMC参考第17路数据（时钟）P
D21 FMC_LA17_CC_N B66_L11_N C4 FMC参考第17路数据（时钟）N
C22 FMC_LA18_CC_P B66_L12_P C3 FMC参考第18路数据（时钟）P
C23 FMC_LA18_CC_N B66_L12_N C2 FMC参考第18路数据（时钟）N
H22 FMC_LA19_P B66_L3_P F2 FMC参考第19路数据P
H23 FMC_LA19_N B66_L3_N E2 FMC参考第19路数据N
G21 FMC_LA20_P B66_L2_P E1 FMC参考第20路数据P
G22 FMC_LA20_N B66_L2_N D1 FMC参考第20路数据NAXU4EVB-P 用户手册
H25 FMC_LA21_P B66_L15_P G6 FMC参考第21路数据P
H26 FMC_LA21_N B66_L15_N F6 FMC参考第21路数据N
G24 FMC_LA22_P B66_L1_P G1 FMC参考第22路数据P
G25 FMC_LA22_N B66_L1_N F1 FMC参考第22路数据N
D23 FMC_LA23_P B66_L5_P E4 FMC参考第23路数据P
D24 FMC_LA23_N B66_L5_N E3 FMC参考第23路数据N
H28 FMC_LA24_P B66_L20_P C6 FMC参考第24路数据P
H29 FMC_LA24_N B66_L20_N B6 FMC参考第24路数据N
G27 FMC_LA25_P B66_L4_P G3 FMC参考第25路数据P
G28 FMC_LA25_N B66_L4_N F3 FMC参考第25路数据N
D26 FMC_LA26_P B66_L16_P G8 FMC参考第26路数据P
D27 FMC_LA26_N B66_L16_N F7 FMC参考第26路数据N
C26 FMC_LA27_P B66_L6_P G5 FMC参考第27路数据P
C27 FMC_LA27_N B66_L6_N F5 FMC参考第27路数据N
H31 FMC_LA28_P B66_L10_P B4 FMC参考第28路数据P
H32 FMC_LA28_N B66_L10_N A4 FMC参考第28路数据N
G30 FMC_LA29_P B66_L7_P C1 FMC参考第29路数据P
G31 FMC_LA29_N B66_L7_N B1 FMC参考第29路数据N
H34 FMC_LA30_P B66_L13_P D7 FMC参考第30路数据P
H35 FMC_LA30_N B66_L13_N D6 FMC参考第30路数据N
G33 FMC_LA31_P B66_L9_P B3 FMC参考第31路数据P
G34 FMC_LA31_N B66_L9_N A3 FMC参考第31路数据N
H37 FMC_LA32_P B65_L24_P H9 FMC参考第32路数据P
H38 FMC_LA32_N B65_L24_N H8 FMC参考第32路数据N
G36 FMC_LA33_P B66_L8_P A2 FMC参考第33路数据P
G37 FMC_LA33_N B66_L8_N A1 FMC参考第33路数据N
"""

# Parse the user mapping
# Format: D27 FMC_LA26_N B66_L16_N F7
pin_map = {}
for line in user_mapping.split('\n'):
    line = line.strip()
    if not line: continue
    parts = line.split()
    if len(parts) >= 4:
        fmc_pin = parts[0]
        fmc_name = parts[1]
        fpga_pin = parts[3]
        if fmc_name.startswith("FMC_LA") or fmc_name.startswith("FMC_CLK"):
            # Strip _CC if present to match the generic LA name
            fmc_name_clean = fmc_name.replace("_CC", "")
            pin_map[fmc_name_clean] = fpga_pin

output_lines = []
output_lines.append("###############################################################################")
output_lines.append("## ALINX AXU4EVB-P FMCOMMS Constraint File")
output_lines.append("## Auto-generated from user pin mapping")
output_lines.append("###############################################################################")
output_lines.append("")

# Bank 65 and 66 on AXU4EVB-P are 1.8V banks (if jumper set for FMC). We should use LVDS for diff and LVCMOS18 for single ended!
# Wait, AD9361 uses LVDS_25 on ZED because Zed uses 2.5V bank. AXU4EVB-P uses 1.8V bank!
# So IOSTANDARD must be LVDS (since Ultrascale+ uses LVDS for 1.8V).
# And LVCMOS18 for single ended.

for line in fmc_zed.split('\n'):
    line = line.strip()
    if not line:
        output_lines.append("")
        continue
    
    if line.startswith("#"):
        output_lines.append(line)
        continue
    
    # Parse the ZED line: set_property  -dict {PACKAGE_PIN  M19  IOSTANDARD LVDS_25 DIFF_TERM TRUE} [get_ports rx_clk_in_p]        ; ## G6   FMC_LPC_LA00_CC_P
    match = re.search(r'set_property\s+-dict\s+\{PACKAGE_PIN\s+\w+\s+IOSTANDARD\s+(\w+)(.*?)\}\s+\[get_ports\s+(.+?)\]\s*;\s*##\s*\w+\s+(FMC_LPC_LA\S+)', line)
    if match:
        old_iostandard = match.group(1)
        extra = match.group(2)
        port_name = match.group(3)
        fmc_name = match.group(4).replace("FMC_LPC_", "FMC_")
        
        # New IOSTANDARD
        new_iostandard = "LVDS" if "LVDS" in old_iostandard else "LVCMOS18"
        
        # Look up pin
        new_pin = pin_map.get(fmc_name)
        if new_pin:
            new_line = f"set_property  -dict {{PACKAGE_PIN  {new_pin:<4} IOSTANDARD {new_iostandard:<8}{extra}}} [get_ports {port_name}] ; ## {fmc_name}"
            output_lines.append(new_line)
        else:
            output_lines.append(f"# WARNING: MAPPING NOT FOUND FOR {fmc_name} ({port_name})")
            output_lines.append(f"# {line}")
    else:
        # Check if it's clock definition
        if "create_clock" in line:
            output_lines.append(line)

with open('C:\\Users\\DELL\\Desktop\\Yazilim\\FPGA-Profen\\PROJECT\\axu4ev_fmcomms.xdc', 'w') as f:
    f.write("\n".join(output_lines))

print("XDC Generated successfully.")
