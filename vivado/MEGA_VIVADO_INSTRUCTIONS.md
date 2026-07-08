# MEGA VIVADO INSTRUCTIONS — ALINX AXU4EVB-P Development Board

> **Purpose**: This document is the **single source of truth** for all technical details about the ALINX AXU4EVB-P (also referenced as AXU4EV-P) FPGA development board. It is designed to be consumed by an AI assistant (Claude) to provide accurate, board-specific guidance for Vivado FPGA/SoC development during an internship project.

---

## TABLE OF CONTENTS

1. [Board Overview](#1-board-overview)
2. [FPGA/SoC Chip Specifications — XCZU4EV-SFVC784-1-I](#2-fpgasoc-chip-specifications--xczu4ev-sfvc784-1-i)
3. [Zynq UltraScale+ Architecture — PS and PL](#3-zynq-ultrascale-architecture--ps-and-pl)
4. [PS-PL Interconnection — AXI Bus Architecture](#4-ps-pl-interconnection--axi-bus-architecture)
5. [Core Board (ACU4EV) Hardware Details](#5-core-board-acu4ev-hardware-details)
6. [Carrier Board (Baseboard) Peripheral Interfaces](#6-carrier-board-baseboard-peripheral-interfaces)
7. [Complete Pin Assignment Reference](#7-complete-pin-assignment-reference)
8. [Clock Architecture](#8-clock-architecture)
9. [Memory Subsystem](#9-memory-subsystem)
10. [Boot Mode Configuration](#10-boot-mode-configuration)
11. [Power Supply Architecture](#11-power-supply-architecture)
12. [Vivado Project Setup — Step-by-Step](#12-vivado-project-setup--step-by-step)
13. [Constraint File (XDC) Reference](#13-constraint-file-xdc-reference)
14. [Block Design — PS Configuration](#14-block-design--ps-configuration)
15. [Common IP Cores and Usage](#15-common-ip-cores-and-usage)
16. [Bitstream Generation and Hardware Export](#16-bitstream-generation-and-hardware-export)
17. [JTAG Programming and Debug](#17-jtag-programming-and-debug)
18. [Key Xilinx Documentation References](#18-key-xilinx-documentation-references)
19. [Common Pitfalls and Troubleshooting](#19-common-pitfalls-and-troubleshooting)

---

## 1. Board Overview

### Board Identity
| Parameter | Value |
|---|---|
| **Board Model** | AXU4EVB-P (also referenced as AXU4EV-P) |
| **Manufacturer** | ALINX (Xinyi Electronic Technology, Shanghai) |
| **Architecture** | Core Board + Carrier Board (Baseboard) |
| **Core Board Model** | ACU4EV |
| **FPGA/SoC Chip** | Xilinx Zynq UltraScale+ MPSoC XCZU4EV-SFVC784-1-I |
| **Core Board Dimensions** | 80 × 60 mm |
| **Power Input** | DC 12V |

### Board Architecture
The development platform uses a **core board + expansion board (carrier board)** architecture connected via four high-speed 120-pin board-to-board connectors (J29, J30, J31, J32). This design facilitates secondary development and reuse of the core board.

### Peripheral Summary

| Category | Interfaces |
|---|---|
| **High-Speed Serial** | 2× SFP+ fiber optic, PCIe Gen3 x4 (PL) / PCIe x2 (PS), M.2 SSD |
| **Video** | 1× HDMI Output (ADV7511), 1× HDMI Input (ADV7611), 1× Mini DP Output, 1× MIPI Camera |
| **Networking** | 2× Gigabit Ethernet (1 PS-side, 1 PL-side, JL2121 PHY) |
| **USB** | 4× USB 3.0 (Host mode, via USB3320C) |
| **Serial Comms** | 2× UART (USB-to-UART), 2× CAN Bus (SN65HVD232C), 2× RS485 (MAX3485) |
| **Storage** | 1× Micro SD card slot, 32GB eMMC, 256Mb QSPI Flash |
| **Expansion** | 1× FMC LPC connector, 2× 40-pin expansion headers |
| **Sensors** | 1× Temperature sensor (LM75, I2C), 1× EEPROM (24LC04, I2C) |
| **User I/O** | 2× User buttons (1 PS, 1 PL), 2× User LEDs (1 PS, 1 PL) |
| **Debug** | 1× JTAG (10-pin 2.54mm), RTC with battery backup |
| **Cooling** | Active fan (PL-controlled via MOSFET, BANK44 pin AG14) |

---

## 2. FPGA/SoC Chip Specifications — XCZU4EV-SFVC784-1-I

### Device Identity
| Parameter | Value |
|---|---|
| **Full Part Number** | XCZU4EV-SFVC784-1-I |
| **Family** | Zynq UltraScale+ MPSoC EV |
| **Speed Grade** | -1 |
| **Temperature Grade** | Industrial (-40°C to +100°C) |
| **Package** | SFVC784 (784-pin FCBGA, 23×23 mm) |
| **Process Node** | 20nm FinFET |
| **Vivado Part String** | `xczu4ev-sfvc784-1-i` |

### Processing System (PS) Resources
| Component | Specification |
|---|---|
| **Application Processor (APU)** | Quad-core ARM Cortex-A53 @ up to 1.5 GHz |
| **Real-Time Processor (RPU)** | Dual-core ARM Cortex-R5F @ up to 600 MHz |
| **GPU** | ARM Mali-400 MP2 @ up to 677 MHz |
| **Video Codec Unit (VCU)** | H.264/H.265 encode/decode (EV-series exclusive) |
| **L2 Cache** | Yes (APU) |
| **PS DDR Support** | DDR4, LPDDR4, DDR3, DDR3L, LPDDR3 (32-bit or 64-bit) |
| **PS High-Speed Interfaces** | PCIe Gen2, USB 3.0, SATA 3.1, DisplayPort v1.2a |
| **PS Low-Speed Interfaces** | USB 2.0, GbE (GEM), SD/SDIO, I2C, CAN, UART, SPI, GPIO |

### Programmable Logic (PL) Resources
| Resource | Quantity |
|---|---|
| **System Logic Cells** | 192,000 (192K) |
| **CLB LUTs** | 88,000 (88K) |
| **CLB Flip-Flops** | 176,000 (176K) |
| **Block RAM (BRAM)** | 4.5 Mb |
| **UltraRAM (URAM)** | 13.5 Mb |
| **DSP Slices (DSP48E2)** | 728 |
| **GTH Transceivers (12.5 Gb/s)** | 4 (available in SFVC784 package) |
| **PCIe Gen3** | 2 hard blocks |

> **CRITICAL**: The SFVC784 package exposes only a subset of the full ZU4EV silicon's I/O and transceivers. Always verify resource availability against the package-specific data in Vivado.

---

## 3. Zynq UltraScale+ Architecture — PS and PL

### Fundamental Concepts

- **PS (Processing System)**: The ARM SoC subsystem — completely independent of FPGA logic. Can operate standalone without configuring the PL.
- **PL (Programmable Logic)**: The FPGA fabric — reconfigurable logic containing LUTs, FFs, BRAM, DSP slices, and transceivers.

### PS Subsystem Components
1. **APU (Application Processing Unit)**: Quad-core Cortex-A53, runs Linux or bare-metal applications
2. **RPU (Real-Time Processing Unit)**: Dual-core Cortex-R5F, for real-time/safety-critical tasks
3. **CCI (Cache Coherent Interconnect)**: Maintains cache coherency between APU and PL
4. **FPD (Full Power Domain)**: Contains APU, high-performance interconnect
5. **LPD (Low Power Domain)**: Contains RPU, low-latency peripherals
6. **Memory Controller**: DDR4 controller on PS side
7. **IOU (I/O Unit)**: Contains all PS peripherals (USB, GbE, SD, I2C, CAN, UART, GPIO, etc.)
8. **Platform Management Unit (PMU)**: Handles boot, power management, security

### PS I/O Banks
| Bank | MIO Range | Typical Voltage | Purpose |
|---|---|---|---|
| **BANK 500** | MIO 0–25 | 1.8V | QSPI Flash, eMMC, I2C |
| **BANK 501** | MIO 26–51 | 1.8V | UART, CAN, SD card, DP, USB |
| **BANK 502** | MIO 52–77 | 1.8V | USB 3.0, GbE |
| **BANK 503** | — | — | PS reference clock, RTC crystal |
| **BANK 504** | — | — | PS DDR4 interface |
| **BANK 505** | — | — | PS MGT transceivers (DP, M.2 PCIe) |

### PL I/O Banks
| Bank | Type | Voltage | Purpose |
|---|---|---|---|
| **BANK 43** | HD (High Density) | 3.3V | UART (PL), RS485, MIPI control, HDMI input control, PCIe reset |
| **BANK 44** | HD (High Density) | 3.3V | HDMI input data, User LED/Button (PL), Fan control, FMC signals |
| **BANK 45** | HD (High Density) | 3.3V | HDMI output (via ADV7511), Fiber optic control, FMC signals |
| **BANK 46** | HD (High Density) | 3.3V | HDMI output data |
| **BANK 64** | HP (High Performance) | 1.8V | PL DDR4 interface, PL system clock (200MHz) |
| **BANK 65** | HP (High Performance) | 1.2V or 1.8V* | FMC LPC signals, MIPI data lanes, GbE (PL-side) |
| **BANK 66** | HP (High Performance) | 1.8V | FMC LPC signals, GbE (PL-side) |
| **BANK 224** | GTH Transceivers | — | SFP+ fiber optic (2 channels), PCIe x2 (PL-side) |

> **⚠ IMPORTANT**: BANK 65 voltage is selectable via jumper J43 on the carrier board:
> - **Pins 2-3**: 1.2V (for MIPI camera)
> - **Pins 1-2**: 1.8V (for FMC connector)
> - **Maximum VCCIO for BANK 65 and BANK 66 MUST NOT exceed 1.8V**

---

## 4. PS-PL Interconnection — AXI Bus Architecture

### AXI Protocol Overview
AXI (Advanced eXtensible Interface) is an ARM AMBA protocol used for all PS-PL communication. Version AXI4 is used in Zynq UltraScale+.

### AXI Interface Types

| Type | Characteristics | Use Cases |
|---|---|---|
| **AXI4-Lite** | Simple, no burst support, 32-bit read/write at a time | Register access, low-speed peripheral control |
| **AXI4 (Full)** | Burst support, memory-mapped, high bandwidth | High-throughput memory access |
| **AXI4-Stream** | No address, continuous data flow (like FIFO) | Video streaming, DSP pipelines, comms protocols |

### AXI4 / AXI4-Lite Channels
1. **Read Address Channel** — Master sends read address
2. **Write Address Channel** — Master sends write address
3. **Read Data Channel** — Slave returns read data
4. **Write Data Channel** — Master sends write data
5. **Write Response Channel** — Slave acknowledges write

### Physical AXI Interfaces on Zynq UltraScale+

#### Master Ports (PS → PL, PS is initiator)
| Interface | Description |
|---|---|
| **M_AXI_HPM0_FPD** | High-performance master, FPD to PL |
| **M_AXI_HPM1_FPD** | High-performance master, FPD to PL |
| **M_AXI_HPM0_LPD** | Low-latency master, LPD to PL (for BRAM, register config) |

#### Slave Ports (PL → PS, PL is initiator)
| Interface | Description |
|---|---|
| **S_AXI_HP0_FPD** | High-performance slave, PL to PS DDR |
| **S_AXI_HP1_FPD** | High-performance slave, PL to PS DDR |
| **S_AXI_HP2_FPD** | High-performance slave, PL to PS DDR |
| **S_AXI_HP3_FPD** | High-performance slave, PL to PS DDR |
| **S_AXI_HPC0_FPD** | High-performance coherent, PL to CCI (L1/L2 cache access) |
| **S_AXI_HPC1_FPD** | High-performance coherent, PL to CCI |
| **S_AXI_LPD** | Low-latency, PL to OCM/TCM and DDR |
| **S_AXI_ACP_FPD** | Accelerator Coherency Port |
| **S_AXI_ACE_FPD** | AXI Coherency Extensions |

> **Design Guidance**:
> - **Most common interfaces**: S_AXI_HP{0:3}_FPD (PL reading/writing PS DDR), M_AXI_HPM{0,1}_FPD (PS controlling PL peripherals), M_AXI_HPM0_LPD (PS configuring PL registers)
> - Use **AXI Interconnect** IP for N-to-M connections (supports up to 16 master / 16 slave per instance)
> - Xilinx provides ready-made IPs: AXI-DMA, AXI-GPIO, AXI-Datamover, AXI-VDMA, AXI-CDMA

### Common AXI IP Cores

| IP Core | Function |
|---|---|
| **AXI-DMA** | PS memory ↔ AXI-Stream (via AXI-HP), CPU-controlled |
| **AXI-FIFO-MM2S** | PS memory ↔ AXI-Stream (via AXI-HPM), general purpose |
| **AXI-Datamover** | PS memory ↔ AXI-Stream (via AXI-HP), PL-controlled (PS passive) |
| **AXI-VDMA** | Video/2D data ↔ AXI-Stream (via AXI-HP), frame buffer support |
| **AXI-CDMA** | Memory-to-memory DMA in PL, no CPU intervention |
| **AXI-GPIO** | General-purpose I/O from PS via AXI |
| **AXI-UART** | UART controller accessible from PS via AXI |
| **AXI-IIC** | I2C controller accessible from PS via AXI |

---

## 5. Core Board (ACU4EV) Hardware Details

### 5.1 DDR4 SDRAM

#### PS-side DDR4 (4 GB)
| Parameter | Value |
|---|---|
| **Chips** | 4× Micron MT40A512M16LY-062E |
| **Capacity** | 4 × 512M × 16-bit = 4 GB total |
| **Data Bus Width** | 64-bit (4 chips × 16-bit) |
| **Max Frequency** | 1200 MHz (2400 Mbps data rate) |
| **Connected to** | PS BANK 504 |

#### PL-side DDR4 (1 GB)
| Parameter | Value |
|---|---|
| **Chips** | 1× Micron MT40A512M16LY-062E |
| **Capacity** | 512M × 16-bit = 1 GB |
| **Data Bus Width** | 16-bit |
| **Max Frequency** | 1066 MHz (2132 Mbps data rate) |
| **Connected to** | PL BANK 64 |

#### PL DDR4 Key Pin Assignments (BANK 64)
| Signal | FPGA Pin | Pin Name |
|---|---|---|
| PL_DDR4_A0 | AD8 | IO_L3P_T0L_N4_AD15P_64 |
| PL_DDR4_A1 | AE6 | IO_L12P_T1U_N10_GC_64 |
| PL_DDR4_A2 | AF8 | IO_L8P_T1L_N2_AD5P_64 |
| PL_DDR4_A3 | AC8 | IO_L3N_T0L_N5_AD15N_64 |
| PL_DDR4_A4 | AF7 | IO_L11P_T1U_N8_GC_64 |
| PL_DDR4_A5 | AD7 | IO_L4P_T0U_N6_DBC_AD7P_64 |
| PL_DDR4_A6 | AH7 | IO_L9N_T1L_N5_AD12N_64 |
| PL_DDR4_A7 | AE9 | IO_L2P_T0L_N2_64 |
| PL_DDR4_A8 | AH8 | IO_L9P_T1L_N4_AD12P_64 |
| PL_DDR4_A9 | AC9 | IO_L1P_T0L_N0_DBC_64 |
| PL_DDR4_A10 | AE7 | IO_L4N_T0U_N7_DBC_AD7N_64 |
| PL_DDR4_A11 | AH9 | IO_L7N_T1L_N1_QBC_AD13N_64 |
| PL_DDR4_A12 | AC6 | IO_L6N_T0U_N11_AD6N_64 |
| PL_DDR4_A13 | AD9 | IO_L1N_T0L_N1_DBC_64 |
| PL_DDR4_BA0 | AH6 | IO_T1U_N12_64 |
| PL_DDR4_BA1 | AC7 | IO_L5N_T0U_N9_AD14N_64 |
| PL_DDR4_RAS_B | AB5 | IO_T2U_N12_64 |
| PL_DDR4_CAS_B | AB7 | IO_L5P_T0U_N8_AD14P_64 |
| PL_DDR4_WE_B | AF6 | IO_L11N_T1U_N9_GC_64 |
| PL_DDR4_ACT_B | AD4 | IO_L13N_T2L_N1_GC_QBC_64 |
| PL_DDR4_CS_B | AB6 | IO_L6P_T0U_N10_AD6P_64 |
| PL_DDR4_BG0 | AE8 | IO_L2N_T0L_N3_64 |
| PL_DDR4_RST | AG9 | IO_L7P_T1L_N0_QBC_AD13P_64 |
| PL_DDR4_CLK_P | AG6 | IO_L10P_T1U_N6_QBC_AD4P_64 |
| PL_DDR4_CLK_N | AG5 | IO_L10N_T1U_N7_QBC_AD4N_64 |
| PL_DDR4_CKE | AE4 | IO_T3U_N12_64 |
| PL_DDR4_OTD | AH4 | IO_L19N_T3L_N1_DBC_AD9N_64 |

### 5.2 QSPI Flash
| Parameter | Value |
|---|---|
| **Chip** | MT25QU256ABA1EW9 (Micron/Winbond) |
| **Capacity** | 256 Mbit (32 MB) |
| **Bus Width** | 8-bit (Quad-SPI) |
| **Voltage** | 1.8V CMOS |
| **Connected to** | PS BANK 500 (MIO 0–5) |
| **Usage** | Boot device — stores FPGA bitstream, ARM firmware, user data |

#### QSPI Pin Assignments
| Signal | Pin Name | Pin Number |
|---|---|---|
| MIO0_QSPI0_SCLK | PS_MIO0_500 | AG15 |
| MIO1_QSPI0_IO1 | PS_MIO1_500 | AG16 |
| MIO2_QSPI0_IO2 | PS_MIO2_500 | AF15 |
| MIO3_QSPI0_IO3 | PS_MIO3_500 | AH15 |
| MIO4_QSPI0_IO0 | PS_MIO4_500 | AH16 |
| MIO5_QSPI0_SS_B | PS_MIO5_500 | AD16 |

### 5.3 eMMC Flash
| Parameter | Value |
|---|---|
| **Chip** | MTFC32GAKAJCN-4M (Micron) |
| **Capacity** | 32 GB |
| **Standard** | JEDEC e-MMC V5.0 |
| **Data Width** | 8-bit |
| **Voltage** | 1.8V or 3.3V |
| **Connected to** | PS BANK 500 (MIO 13–23) |
| **Usage** | Large-capacity storage — OS, file system, user data |

#### eMMC Pin Assignments
| Signal | Pin Name | Pin Number |
|---|---|---|
| MMC_DAT0 | PS_MIO13_500 | AH18 |
| MMC_DAT1 | PS_MIO14_500 | AG18 |
| MMC_DAT2 | PS_MIO15_500 | AE18 |
| MMC_DAT3 | PS_MIO16_500 | AF18 |
| MMC_DAT4 | PS_MIO17_500 | AC18 |
| MMC_DAT5 | PS_MIO18_500 | AC19 |
| MMC_DAT6 | PS_MIO19_500 | AE19 |
| MMC_DAT7 | PS_MIO20_500 | AD19 |
| MMC_CMD | PS_MIO21_500 | AC21 |
| MMC_CCLK | PS_MIO22_500 | AB20 |
| MMC_RSTN | PS_MIO23_500 | AB18 |

### 5.4 Core Board LEDs
| LED | Function | Notes |
|---|---|---|
| **PWR (Red)** | Power indicator | Lights when core board is powered |
| **DONE** | FPGA configuration indicator | Lights when PL is configured |

### 5.5 Core Board Power
- Input voltage: **+12V** (from carrier board via connectors)
- PMIC: **TPS6508641** — generates all required voltages for XCZU4EV
- BANK 65/66 VCCIO supplied by carrier board (selectable, max 1.8V)

---

## 6. Carrier Board (Baseboard) Peripheral Interfaces

### 6.1 M.2 SSD Interface
| Parameter | Value |
|---|---|
| **Type** | PCIe x1 M.2 (M Key) |
| **Protocol** | PCIe only (NOT SATA) |
| **Speed** | Up to 6 Gbps |
| **Connected to** | PS BANK 505 MGT LANE1 |
| **Clock** | 100 MHz from Si5332 chip |

| Signal | Pin Name | Pin Number |
|---|---|---|
| PCIE_TX_P | 505_TX0_P | E25 |
| PCIE_TX_N | 505_TX0_N | E26 |
| PCIE_RX_P | 505_RX0_P | F27 |
| PCIE_RX_N | 505_RX0_N | F28 |
| 505_PCIE_REFCLK_P | 505_CLK0_P | F23 |
| 505_PCIE_REFCLK_N | 505_CLK0_N | F24 |
| PCIE_RSTn_MIO37 | PS_MIO37_501 | J17 |

### 6.2 DisplayPort Output
| Parameter | Value |
|---|---|
| **Standard** | VESA DisplayPort V1.2a |
| **Resolution** | Up to 4K × 2K @ 30 fps |
| **Color Formats** | Y-only, YCbCr444, YCbCr422, YCbCr420, RGB |
| **Color Depth** | 6, 8, 10, or 12 bits per color |
| **Connected to** | PS BANK 505 MGT LANE2 + LANE3 (TX) |

| Signal | Pin Name | Pin Number | Note |
|---|---|---|---|
| GT0_DP_TX_P | 505_TX3_P | B23 | DP low lane TX+ |
| GT0_DP_TX_N | 505_TX3_N | B24 | DP low lane TX- |
| GT1_DP_TX_P | 505_TX2_P | C25 | DP high lane TX+ |
| GT1_DP_TX_N | 505_TX2_N | C26 | DP high lane TX- |
| 505_CLK1_P | 505_CLK2_P | C21 | DP reference clock+ |
| 505_CLK1_N | 505_CLK2_N | C22 | DP reference clock- |
| DP_AUX_OUT | PS_MIO27 | J15 | Auxiliary data output |
| DP_AUX_IN | PS_MIO30 | F16 | Auxiliary data input |
| DP_OE | PS_MIO29 | G16 | Auxiliary output enable |
| DP_HPD | PS_MIO28 | K15 | Hot-plug detect |

### 6.3 USB 3.0 (4 Ports)
| Parameter | Value |
|---|---|
| **Ports** | 4× USB Type-A (Host mode) |
| **Speed** | Up to 5.0 Gbps (USB 3.0) |
| **USB 3.0** | Connected via PIPE3 interface |
| **USB 2.0** | Via external USB3320C PHY (ULPI interface) |
| **Connected to** | PS BANK 502 (MIO 52–63) |

| Signal | Pin Name | Pin Number | Note |
|---|---|---|---|
| USB_NXT | PS_MIO55 | B16 | USB 2.0 next data signal |
| USB_RESET_N | PS_MIO31 | H16 | USB 2.0 reset signal |

### 6.4 Gigabit Ethernet (2 Ports)

#### Ethernet 1 (PS-side)
| Parameter | Value |
|---|---|
| **PHY Chip** | JL2121 (JLSemi) |
| **Interface** | RGMII |
| **Speed** | 10/100/1000 Mbps (auto-negotiation) |
| **PHY Address** | 001 (binary) |
| **Connected to** | PS BANK 502 |

#### Ethernet 2 (PL-side)
| Parameter | Value |
|---|---|
| **PHY Chip** | JL2121 (JLSemi) |
| **Interface** | RGMII |
| **Speed** | 10/100/1000 Mbps (auto-negotiation) |
| **Connected to** | PL BANK 66 |

##### PL Ethernet Pin Assignments (Ethernet 2)
| Signal | Pin Name | Pin Number | Note |
|---|---|---|---|
| PHY2_RXD0 | B66_L19_N | A5 | RX data bit 0 |
| PHY2_RXD1 | B66_L19_P | B5 | RX data bit 1 |
| PHY2_RXD2 | B66_L17_P | F8 | RX data bit 2 |
| PHY2_RXD3 | B66_L24_P | C9 | RX data bit 3 |
| PHY2_RXCTL | B66_L22_N | B8 | RX data valid |
| PHY2_MDC | B66_L21_N | A6 | MDIO management clock |
| PHY2_MDIO | B66_L22_P | C8 | MDIO management data |
| PHY2_RESET | B66_L14_N | D5 | PHY reset |

#### JL2121 Default Configuration
| Config Pin | Description | Default |
|---|---|---|
| PHYAD[2:0] (RXD3/RXC/RXCTL) | PHY address | 001 |
| RXD1_TXDLY | TX clock 2ns delay | Delayed |
| RXD0_RXDLY | RX clock 2ns delay | Delayed |

### 6.5 UART Interfaces (2 Ports)
| Signal | Pin Name | Pin Number | Note |
|---|---|---|---|
| PS_UART0_TX | PS_MIO43 | K19 | PS UART data output |
| PS_UART0_RX | PS_MIO42 | L18 | PS UART data input |
| PL_UART_TX | B43_L9_P | AA11 | PL UART data output |
| PL_UART_RX | B43_L9_N | AA10 | PL UART data input |

### 6.6 SD Card Slot
| Parameter | Value |
|---|---|
| **Type** | Micro SD |
| **Connected to** | PS BANK 501 (MIO 45–51) |
| **Level Shifter** | TXS02612 (1.8V PS ↔ 3.3V SD) |
| **Usage** | Boot device, Linux kernel, file system |

| Signal | Pin Name | Pin Number | Note |
|---|---|---|---|
| SD_CLK | PS_MIO51 | L21 | SD clock |
| SD_CMD | PS_MIO50 | M19 | SD command |
| SD_D0 | PS_MIO46 | L20 | SD data 0 |
| SD_D1 | PS_MIO47 | H21 | SD data 1 |
| SD_D2 | PS_MIO48 | J21 | SD data 2 |
| SD_D3 | PS_MIO49 | M18 | SD data 3 |
| SD_CD | PS_MIO45 | K20 | Card detect |

### 6.7 HDMI Output
| Parameter | Value |
|---|---|
| **Encoder Chip** | ADV7511 (Analog Devices) |
| **Max Resolution** | 1080P @ 60 Hz |
| **3D Support** | Yes |
| **Connected to** | PL BANK 45, 46 (video + I2C) |

| Signal | Pin Name | Pin Number | Note |
|---|---|---|---|
| HDMI_D17 | B35_L15_P | F17 | Video data 17 |
| HDMI_D18 | B35_L7_N | G16 | Video data 18 |
| HDMI_D19 | B35_L7_P | G17 | Video data 19 |
| HDMI_D20 | B35_L6_N | H16 | Video data 20 |
| HDMI_D21 | B35_L6_P | J16 | Video data 21 |
| HDMI_D22 | B35_L17_P | C17 | Video data 22 |
| HDMI_D23 | B35_L17_N | B16 | Video data 23 |
| HDMI_SCL | B35_L13_N | E15 | I2C clock (config) |
| HDMI_SDA | B35_L13_P | E16 | I2C data (config) |

### 6.8 HDMI Input
| Parameter | Value |
|---|---|
| **Decoder Chip** | ADV7611 (Analog Devices) |
| **Max Resolution** | 1080P @ 60 Hz |
| **Connected to** | PL BANK 43, 44 (video + I2C) |

| Signal | Pin Name | Pin Number | Note |
|---|---|---|---|
| HDMI_IN_D15 | B43_L10_P | W10 | Input video data 15 |
| HDMI_IN_D16 | B44_L11_N | W11 | Input video data 16 |
| HDMI_IN_D17 | B44_L11_P | W12 | Input video data 17 |
| HDMI_IN_D18 | B44_L9_N | W13 | Input video data 18 |
| HDMI_IN_D19 | B44_L9_P | W14 | Input video data 19 |
| HDMI_IN_D20 | B44_L8_P | AB15 | Input video data 20 |
| HDMI_IN_D21 | B44_L8_N | AB14 | Input video data 21 |
| HDMI_IN_D22 | B43_L2_N | AG11 | Input video data 22 |
| HDMI_IN_SDA | B43_L5_P | AE12 | ADV7611 I2C data |
| HDMI_IN_SCL | B43_L5_N | AF12 | ADV7611 I2C clock |
| HDMI_DSCL | B45_L5_N | F10 | EDID I2C clock |
| HDMI_DSDA | B45_L5_P | G11 | EDID I2C data |

### 6.9 SFP+ Fiber Optic (2 Channels)
| Parameter | Value |
|---|---|
| **Channels** | 2× SFP+ cages |
| **Data Rate** | Up to 12.5 Gb/s per channel |
| **Connected to** | PL BANK 224 GTH transceivers |
| **Reference Clock** | 125 MHz differential (from core board) |

| Signal | Pin Name | Pin Number | Note |
|---|---|---|---|
| SFP1_TX_P | 224_TX0_P | W4 | SFP1 TX+ |
| SFP1_TX_N | 224_TX0_N | W3 | SFP1 TX- |
| SFP1_RX_P | 224_RX0_P | Y2 | SFP1 RX+ |
| SFP1_RX_N | 224_RX0_N | Y1 | SFP1 RX- |
| SFP2_TX_P | 224_TX1_P | U4 | SFP2 TX+ |
| SFP2_TX_N | 224_TX1_N | U3 | SFP2 TX- |
| SFP2_RX_P | 224_RX1_P | V2 | SFP2 RX+ |
| SFP2_RX_N | 224_RX1_N | V1 | SFP2 RX- |
| SFP_TX_DIS | B45_L12_P | D12 | TX disable (active high) |
| SFP1_LOSS | B45_L9_N | B10 | SFP1 RX loss detect |
| SFP2_LOSS | B45_L9_P | C11 | SFP2 RX loss detect |

### 6.10 PCIe x2 Slot (PL-side)
| Parameter | Value |
|---|---|
| **Standard** | PCIe 3.0 (compatible with 2.0) |
| **Lanes** | 2 (x2) |
| **Max Bandwidth** | 8 Gb/s per lane |
| **Connected to** | PL BANK 224 GTH transceivers |

| Signal | Pin Name | Pin Number | Note |
|---|---|---|---|
| PCIE_RX0_P | 224_RX2_P | T2 | Channel 0 RX+ |
| PCIE_RX0_N | 224_RX2_N | T1 | Channel 0 RX- |
| PCIE_RX1_P | 224_RX3_P | P2 | Channel 1 RX+ |
| PCIE_RX1_N | 224_RX3_N | P1 | Channel 1 RX- |
| PCIE_TX0_P | 224_TX2_P | R4 | Channel 0 TX+ |
| PCIE_TX0_N | 224_TX2_N | R3 | Channel 0 TX- |
| PCIE_TX1_P | 224_TX3_P | N4 | Channel 1 TX+ |
| PCIE_TX1_N | 224_TX3_N | N3 | Channel 1 TX- |
| PCIE_PERST | B43_L8_N | AC11 | PCIe reset |

### 6.11 CAN Bus (2 Channels)
| Parameter | Value |
|---|---|
| **Transceiver** | SN65HVD232C (TI) |
| **Connected to** | PS BANK 501 |

| Signal | Pin Name | Pin Number |
|---|---|---|
| PS_CAN1_TX | PS_MIO32 | J16 |
| PS_CAN1_RX | PS_MIO33 | L16 |
| PS_CAN2_TX | PS_MIO39 | H19 |
| PS_CAN2_RX | PS_MIO38 | H18 |

### 6.12 RS485 (2 Channels)
| Parameter | Value |
|---|---|
| **Transceiver** | MAX3485 (Maxim) |
| **Connected to** | PL BANK 43, 45 |

| Signal | Pin Name | Pin Number | Note |
|---|---|---|---|
| PL_485_TXD1 | B43_L1_P | AG10 | Channel 1 TX |
| PL_485_RXD1 | B43_L1_N | AH10 | Channel 1 RX |
| PL_485_DE1 | B45_L10_N | A10 | Channel 1 TX enable |
| PL_485_TXD2 | B43_L3_N | AH11 | Channel 2 TX |
| PL_485_RXD2 | B43_L3_P | AH12 | Channel 2 RX |
| PL_485_DE2 | B45_L10_P | B11 | Channel 2 TX enable |

### 6.13 MIPI Camera Interface
| Parameter | Value |
|---|---|
| **Connector** | 15-pin FPC |
| **Lanes** | 2 data lanes + 1 clock pair |
| **Compatible Camera** | MIPI OV5640 module (AN5641) |
| **Data Pins** | PL BANK 65 (1.2V IOSTANDARD) |
| **Control Pins** | PL BANK 43 (3.3V) |

> **⚠ IMPORTANT**: For MIPI camera use, jumper J43 must connect PIN2-PIN3 (1.2V for BANK 65)

| Signal | Pin Name | Pin Number | Note |
|---|---|---|---|
| MIPI_CLK_P | B65_L1_P | W8 | MIPI clock+ |
| MIPI_CLK_N | B65_L1_N | Y8 | MIPI clock- |
| MIPI_LAN0_P | B65_L2_P | U9 | MIPI data lane 0+ |
| MIPI_LAN0_N | B65_L2_N | V9 | MIPI data lane 0- |
| MIPI_LAN1_P | B65_L3_P | U8 | MIPI data lane 1+ |
| MIPI_LAN1_N | B65_L3_N | V8 | MIPI data lane 1- |
| CAM_GPIO | B43_L4_P | AE10 | Camera GPIO control |
| CAM_CLK | B43_L4_N | AF10 | Camera clock input |
| CAM_SCL | B43_L11_P | Y9 | Camera I2C clock |
| CAM_SDA | B43_L11_N | AA8 | Camera I2C data |

### 6.14 FMC LPC Connector
| Parameter | Value |
|---|---|
| **Type** | Standard FMC LPC |
| **Differential Pairs** | 36 pairs |
| **Connected to** | PL BANK 65, 66 |
| **IO Standard** | 1.8V (supports LVDS) |

> **⚠ IMPORTANT**: For FMC use, jumper J43 must connect PIN1-PIN2 (1.8V for BANK 65)

#### FMC Pin Assignments (Selected)
| Signal | Pin Name | Pin Number | Note |
|---|---|---|---|
| FMC_LA30_P | B66_L13_P | D7 | FMC channel 30 P |
| FMC_LA30_N | B66_L13_N | D6 | FMC channel 30 N |
| FMC_LA31_P | B66_L9_P | B3 | FMC channel 31 P |
| FMC_LA31_N | B66_L9_N | A3 | FMC channel 31 N |
| FMC_LA32_P | B65_L24_P | H9 | FMC channel 32 P |
| FMC_LA32_N | B65_L24_N | H8 | FMC channel 32 N |
| FMC_LA33_P | B66_L8_P | A2 | FMC channel 33 P |
| FMC_LA33_N | B66_L8_N | A1 | FMC channel 33 N |
| FMC_PRSNT | B45_L12_N | C12 | FMC present signal |
| PWRGD | B44_L2_N | AH14 | FMC power good |

### 6.15 User LEDs
| Signal | Pin Name | Pin Number | Note |
|---|---|---|---|
| PS_LED1 | PS_MIO40 | K18 | PS-controlled LED |
| PL_LED1 | B44_L1_P | AE15 | PL-controlled LED |

> LED behavior: High = ON, Low = OFF

### 6.16 User Buttons
| Signal | Pin Name | Pin Number | Note |
|---|---|---|---|
| PS_KEY1 | PS_MIO26 | L15 | PS button (active low) |
| PL_KEY1 | B44_L1_N | AE14 | PL button (active low) |

> Both buttons are **active LOW** (pressed = logic 0)

### 6.17 EEPROM and Temperature Sensor
| Component | Chip | Interface | Connected to |
|---|---|---|---|
| EEPROM | 24LC04 (4Kbit) | I2C | PS BANK 500 (MIO 24–25) |
| Temperature Sensor | LM75 (ON Semi) | I2C | PS BANK 500 (MIO 24–25) |

| Signal | Pin Name | Pin Number |
|---|---|---|
| PS_IIC1_SCL | PS_MIO24 | AB19 |
| PS_IIC1_SDA | PS_MIO25 | AB21 |

> Temperature accuracy: 0.5°C

### 6.18 Fan Control
| Signal | Pin Name | Pin Number | Note |
|---|---|---|---|
| FAN_CTRL | B44 IO | AG14 | High = Fan ON, Low = Fan OFF |

> The fan is controlled via a MOSFET gate driven by PL BANK 44 pin AG14.

### 6.19 Expansion Board Features
The AXU4EVB-P supports an optional expansion board (referenced in documentation as "Adsız doküman (2)") that provides additional interface capabilities when mounted to the carrier board:

#### Expansion Board Interfaces
| Interface | Quantity | Details |
|---|---|---|
| **M.2 Interface** | 1 channel | PCIe x1 for NVMe/SSD storage |
| **DisplayPort Output** | 1 channel | Standard DP 1.2 output |
| **USB 3.0 Host** | 4 channels | Type A connectors |
| **Gigabit Ethernet** | 2 channels | RJ45 with magnetics |
| **USB UART** | 2 channels | Micro-USB for debug/serial |
| **Micro SD Card Holder** | 1 channel | Storage/boot option |
| **MIPI Camera Interface** | 1 channel | CSI-2 for image sensors |
| **HDMI Video Output** | 1 channel | ADV7511 encoder |
| **HDMI Video Input** | 1 channel | ADV7611 decoder |
| **FMC Expansion Port** | 1 channel | VITA 57.1 LPC |
| **CAN Communication** | 2 channels | SN65HVD232 transceivers |
| **RS485 Communication** | 2 channels | MAX3485 transceivers |
| **JTAG Debug Port** | 1 channel | 10-pin 0.1" header |
| **Temperature Sensor** | 1 channel | LM75 or similar I2C sensor |
| **EEPROM** | 1 channel | 24LC04 or similar I2C EEPROM (4Kbit) |
| **Real-Time Clock** | 1 channel | Built-in RTC with battery backup |
| **User LEDs** | 3 channels | GPIO-controlled |
| **User Buttons** | 3 channels | GPIO-controlled with pull-resistors |

#### Key Expansion Board Features:
- **Power Input**: +12V DC (barrel jack or alternative)
- **Fan Control**: PWM or GPIO-controlled cooling fan (header J42)
- **Voltage Selection**: Jumper J43 selects BANK65 voltage (1.2V for MIPI, 1.8V for FMC)
- **Industrial Components**: Extended temperature rated components where applicable

---

## 7. Complete Pin Assignment Reference

### PS MIO Master Map

| MIO | Function | Bank | Pin |
|---|---|---|---|
| MIO 0 | QSPI0_SCLK | 500 | AG15 |
| MIO 1 | QSPI0_IO1 | 500 | AG16 |
| MIO 2 | QSPI0_IO2 | 500 | AF15 |
| MIO 3 | QSPI0_IO3 | 500 | AH15 |
| MIO 4 | QSPI0_IO0 | 500 | AH16 |
| MIO 5 | QSPI0_SS_B | 500 | AD16 |
| MIO 6–12 | (Reserved/Various) | 500 | — |
| MIO 13 | MMC_DAT0 | 500 | AH18 |
| MIO 14 | MMC_DAT1 | 500 | AG18 |
| MIO 15 | MMC_DAT2 | 500 | AE18 |
| MIO 16 | MMC_DAT3 | 500 | AF18 |
| MIO 17 | MMC_DAT4 | 500 | AC18 |
| MIO 18 | MMC_DAT5 | 500 | AC19 |
| MIO 19 | MMC_DAT6 | 500 | AE19 |
| MIO 20 | MMC_DAT7 | 500 | AD19 |
| MIO 21 | MMC_CMD | 500 | AC21 |
| MIO 22 | MMC_CCLK | 500 | AB20 |
| MIO 23 | MMC_RSTN | 500 | AB18 |
| MIO 24 | I2C1_SCL (EEPROM/Temp) | 500 | AB19 |
| MIO 25 | I2C1_SDA (EEPROM/Temp) | 500 | AB21 |
| MIO 26 | PS_KEY1 (User Button) | 501 | L15 |
| MIO 27 | DP_AUX_OUT | 501 | J15 |
| MIO 28 | DP_HPD | 501 | K15 |
| MIO 29 | DP_OE | 501 | G16 |
| MIO 30 | DP_AUX_IN | 501 | F16 |
| MIO 31 | USB_RESET_N | 501 | H16 |
| MIO 32 | CAN1_TX | 501 | J16 |
| MIO 33 | CAN1_RX | 501 | L16 |
| MIO 34 | (Various) | 501 | L17 |
| MIO 37 | PCIE_RSTn (M.2) | 501 | J17 |
| MIO 38 | CAN2_RX | 501 | H18 |
| MIO 39 | CAN2_TX | 501 | H19 |
| MIO 40 | PS_LED1 | 501 | K18 |
| MIO 42 | UART0_RX | 501 | L18 |
| MIO 43 | UART0_TX | 501 | K19 |
| MIO 45 | SD_CD | 501 | K20 |
| MIO 46 | SD_D0 | 501 | L20 |
| MIO 47 | SD_D1 | 501 | H21 |
| MIO 48 | SD_D2 | 501 | J21 |
| MIO 49 | SD_D3 | 501 | M18 |
| MIO 50 | SD_CMD | 501 | M19 |
| MIO 51 | SD_CLK | 501 | L21 |
| MIO 52–63 | USB 3.0 / GbE (PS) | 502 | Various |
| MIO 55 | USB_NXT | 502 | B16 |

---

## 8. Clock Architecture

### Clock Sources Summary
| Clock | Frequency | Type | Connected to | FPGA Pin |
|---|---|---|---|---|
| **PS Reference Clock** | 33.333 MHz | Active crystal oscillator (X1) | PS BANK 503, PS_REF_CLK_503 | R16 |
| **PS RTC Clock** | 32.768 KHz | Passive crystal (Y2) | PS BANK 503 (PS_PADI_503/PS_PADO_503) | N17 (PADI), N18 (PADO) |
| **PL System Clock** | 200 MHz | Differential active oscillator | PL BANK 64 (MRCC) | AE5 (PL_CLK0_P), AF5 (PL_CLK0_N) |
| **SFP Reference Clock** | 125 MHz | Differential (from core board) | PL BANK 224 GTH | — |
| **M.2 PCIe Reference Clock** | 100 MHz | From Si5332 chip | PS BANK 505 | F23 (P), F24 (N) |
| **DP Reference Clock** | — | From Si5332 chip | PS BANK 505 | C21 (P), C22 (N) |

### PL Clock Details
The 200 MHz differential PL clock connects to the MRCC (Multi-Region Clock Capable) pins of BANK 64. This clock serves as:
- Reference clock for the PL-side DDR4 MIG controller
- General-purpose clock source for user PL logic

```
# XDC Constraint for PL System Clock
set_property PACKAGE_PIN AE5 [get_ports sys_clk_p]
set_property PACKAGE_PIN AF5 [get_ports sys_clk_n]
set_property IOSTANDARD DIFF_SSTL12 [get_ports sys_clk_p]
set_property IOSTANDARD DIFF_SSTL12 [get_ports sys_clk_n]
create_clock -period 5.000 -name sys_clk [get_ports sys_clk_p]
```

### PS Clock Configuration (in Vivado Block Design)
When configuring the Zynq UltraScale+ PS block:
- **Input Reference Clock**: 33.333 MHz (set in Clock Configuration → Input Clocks)
- **CPU Frequency**: Up to 1.3 GHz (APU Cortex-A53)
- **PL Fabric Clocks**: Can generate pl_clk0, pl_clk1, pl_clk2, pl_clk3 from PS PLL (configurable frequencies)

---

## 9. Memory Subsystem

### Memory Map Overview
```
┌──────────────────────────────────────────────┐
│                PS DDR4 (4 GB)                │
│  Address: 0x0000_0000 — 0x0000_FFFF_FFFF     │
│  (BANK 504, 64-bit, 2400 Mbps)              │
├──────────────────────────────────────────────┤
│              PL DDR4 (1 GB)                  │
│  (BANK 64, 16-bit, 2132 Mbps)               │
│  Accessible via MIG IP in PL                 │
├──────────────────────────────────────────────┤
│            QSPI Flash (32 MB)                │
│  Boot device, non-volatile                   │
│  (PS BANK 500, MIO 0–5)                      │
├──────────────────────────────────────────────┤
│            eMMC Flash (32 GB)                │
│  Large storage, non-volatile                 │
│  (PS BANK 500, MIO 13–23)                    │
├──────────────────────────────────────────────┤
│            OCM (On-Chip Memory)              │
│  256 KB, low-latency                         │
├──────────────────────────────────────────────┤
│            TCM (Tightly Coupled Memory)      │
│  Per R5 core, low-latency                    │
└──────────────────────────────────────────────┘
```

### Detailed Memory Subsystem Specifications

#### 9.1 DDR4 SDRAM

##### PS-side DDR4 (4 GB)
| Parameter | Value |
|---|---|
| **Chips** | 4× Micron MT40A512M16LY-062E |
| **Capacity** | 4 × 512M × 16-bit = 4 GB total |
| **Data Bus Width** | 64-bit (4 chips × 16-bit) |
| **Max Frequency** | 1200 MHz (2400 Mbps data rate) |
| **Connected to** | PS BANK 504 |

##### PL-side DDR4 (1 GB)
| Parameter | Value |
|---|---|
| **Chip** | 1× Micron MT40A512M16LY-062E |
| **Capacity** | 512M × 16-bit = 1 GB |
| **Data Bus Width** | 16-bit |
| **Max Frequency** | 1066 MHz (2132 Mbps data rate) |
| **Connected to** | PL BANK 64 |

#### 9.2 QSPI Flash
| Parameter | Value |
|---|---|
| **Chip** | Winbond MT25QU256ABA1EW9 |
| **Capacity** | 256 Mbit (32 MB) |
| **Interface** | Quad-SPI (1-bit, 2-bit, or 4-bit modes) |
| **Voltage** | 1.8V CMOS |
| **Connected to** | PS BANK 500 (MIO 0–5) |
| **Usage** | Boot device — stores FPGA bitstream, ARM firmware, user data, boot scripts |
| **Reference Designator** | U5 |

#### 9.3 eMMC Flash
| Parameter | Value |
|---|---|
| **Chip** | Micron MTFC32GAKAJCN-4M |
| **Capacity** | 32 GB |
| **Interface** | HS-MMC (JEDEC e-MMC V5.0 standard) |
| **Data Bus Width** | 8-bit |
| **Voltage** | Dual voltage (1.8V or 3.3V) |
| **Connected to** | PS BANK 500 (MIO 0–5, shared with QSPI via pinmux) |
| **Usage** | Large-capacity storage — OS image, file system, user data, application logs |
| **Reference Designator** | U19 |

### Storage Subsystem Notes
- **QSPI and eMMC Sharing**: Both devices share the same MIO pins (BANK 500, MIO 0–5) but use different pin functions. Only one can be active at a time based on boot mode selection via PS_MIO register configuration.
- **Boot Priority**: When multiple boot devices are present, the bootROM checks in order: QSPI → SD Card → eMMC → USB
- **Write Protection**: QSPI flash features hardware write protection via WP# pin (not connected on this board, software protection only)

---

## 10. Boot Mode Configuration

### DIP Switch SW1 Settings
The 4-bit DIP switch SW1 on the carrier board configures the boot mode. After power-on, the ZU4EV reads PS_MODE[3:0] to determine the boot source.

| DIP Position (1,2,3,4) | ON=0, OFF=1 | BOOT[3:0] | Boot Mode | Active Boot Device |
|---|---|---|---|---|
| ON, ON, ON, ON | 0,0,0,0 | 0000 | **JTAG Boot** | JTAG interface only (no auto-boot) |
| ON, ON, OFF, ON | 0,0,1,0 | 0010 | **QSPI Boot** | QSPI Flash (U5) |
| ON, OFF, ON, OFF | 0,1,0,1 | 0101 | **SD Card Boot** | Micro SD Card Slot |
| ON, OFF, OFF, ON | 0,1,1,0 | 0110 | **eMMC Boot** | eMMC Flash (U19) |
| ON, ON, ON, OFF | 0,0,0,1 | 0001 | **USB Boot** | USB OTG (Host/Device) |
| All other combinations | - | - | Reserved | Default to JTAG |

### Boot Mode Details
- **JTAG Mode (0000)**: Used for development and debugging. The FPGA is configured directly via JTAG, and no automatic boot from flash storage occurs.
- **QSPI Mode (0010)**: Boots from the 256MB QSPI flash (U5). Typical for storing golden bitstream and basic bootloader.
- **SD Card Mode (0101)**: Boots from the FAT32-formatted Micro SD card. Common for Linux development and frequent image updates.
- **eMMC Mode (0110)**: Boots from the 32GB eMMC flash (U19). Used for production deployments requiring large storage capacity.
- **USB Mode (0001)**: Boot via USB OTG interface (requires USB boot capable host).

> **For Development**: Use **JTAG mode** (all switches ON) during active development to load bitstreams directly from Vivado. Switch to QSPI/SD/eMMC for standalone deployment testing.
> 
> **Boot Image Requirements**: 
> - QSPI/SD/eMMC: Requires a properly formatted BOOT.BIN containing FSBL + bitstream + optional application
> - SD Card: Must be FAT32 formatted with BOOT.BIN in root directory
> - USB: Requires USB boot capable host system

---

## 11. Power Supply Architecture

### Carrier Board Power
| Voltage Rail | Generation IC | Purpose |
|---|---|---|
| **+12V** | DC input (barrel jack or alternative) | Main input, feeds core board and DC/DC converters |
| **+5.0V** | DC/DC (ETA1471) | USB power supply, general 5V rail |
| **+3.3V** | DC/DC (ETA8156) | Ethernet, USB 2.0, SD card, DP, CAN, RS485, general 3.3V rail |
| **+1.8V** | DC/DC (ETA8156) | Ethernet, USB 2.0, core board BANK 66 (fixed) |
| **+1.2V** | LDO | Core board BANK 65 (selectable via J43 jumper for MIPI/FMC) |

### Core Board Power (ACU4EV)
| Voltage Rail | Generation | Purpose |
|---|---|---|
| **All ZU4EV core voltages** | PMIC (TPS6508641) from +12V | VCC_INT (0.85V), VCC_AUX (1.8V), VCC_BRAM (0.85V), VCC_PSINTFP (0.85V), VCC_PSINTLP (0.85V), VCC_PSAUX (1.0V), VCC_PSDDR (1.2V) |
| **BANK 65 VCCIO** | From carrier board (LDO) | 1.2V (MIPI mode) or 1.8V (FMC mode) — selectable via J43 jumper |
| **BANK 66 VCCIO** | From carrier board (ETA8156 DC/DC) | Fixed 1.8V |

### Power Supply Details
- **Core Board PMIC**: Texas Instruments TPS6508641
  - Generates all required power rails for XCZU4EV Zynq UltraScale+ MPSoC
  - Includes power sequencing and monitoring
  - Input: +12V from carrier board
- **Carrier Board Regulators**:
  - ETA1471: DC/DC converter for 5V rail
  - ETA8156 (×2): DC/DC converter for 3.3V and 1.8V rails
  - LDO: For adjustable 1.2V rail (BANK 65 selection via J43 jumper)
- **Fan Control**:
  - Controlled by PL pin AG14 (BANK 44, HD I/O)
  - MOSFET driver circuit: HIGH (3.3V) = Fan ON, LOW (0V) = Fan OFF
  - Power connector: J42 (Red = +12V, Black = Ground)
  - Default state: Fan enabled at power-on for thermal management

---

## 12. Vivado Project Setup — Step-by-Step

### Prerequisites
- **Vivado Design Suite** version **2020.1** or compatible (check ALINX documentation for exact version)
- Board definition files from ALINX (recommended but optional)
- ALINX demo projects from GitHub: search `alinxalinx AXU4EV` or `AXU4EV-P_AXU5EV-P`

### Method A: Create from ALINX Demo Project (Recommended)
1. Download the demo project archive from ALINX GitHub
2. Extract and navigate to `vivado/auto_create_project/`
3. **TCL Console method**:
   ```tcl
   cd {path/to/auto_create_project}
   source ./create_project.tcl
   ```
4. **Batch file method**: Edit `create_project.bat` to point to your Vivado installation, then execute it

### Method B: Create New Project from Scratch
1. **Launch Vivado** → Click **Create Project**
2. **Project Name & Location**: Choose descriptive name, keep path SHORT (Windows path length limits!)
3. **Project Type**: Select **RTL Project**
4. **Default Part**: 
   - Click **Parts** tab (not Boards, unless you have board files installed)
   - Search for: `xczu4ev-sfvc784-1-i`
   - Select the matching part
5. Click **Finish**

### Installing Board Files (Optional but Recommended)
If ALINX provides board definition files:
1. Copy board files to: `<Vivado_Install>/data/boards/board_files/`
2. Restart Vivado
3. When creating new projects, select from the **Boards** tab for automatic preset configuration

---

## 13. Constraint File (XDC) Reference

### Critical XDC Constraints for AXU4EVB-P

```tcl
# ==============================================================================
# AXU4EVB-P Master Constraints File
# Board: ALINX AXU4EVB-P
# FPGA:  XCZU4EV-SFVC784-1-I
# ==============================================================================

# ------------------------------------------------------------------------------
# PL System Clock (200 MHz Differential, BANK 64)
# ------------------------------------------------------------------------------
set_property PACKAGE_PIN AE5 [get_ports sys_clk_p]
set_property PACKAGE_PIN AF5 [get_ports sys_clk_n]
set_property IOSTANDARD DIFF_SSTL12 [get_ports sys_clk_p]
set_property IOSTANDARD DIFF_SSTL12 [get_ports sys_clk_n]
create_clock -period 5.000 -name sys_clk [get_ports sys_clk_p]

# ------------------------------------------------------------------------------
# PL User LED (BANK 44, 3.3V)
# ------------------------------------------------------------------------------
set_property PACKAGE_PIN AE15 [get_ports pl_led]
set_property IOSTANDARD LVCMOS33 [get_ports pl_led]

# ------------------------------------------------------------------------------
# PL User Button (BANK 44, 3.3V, Active Low)
# ------------------------------------------------------------------------------
set_property PACKAGE_PIN AE14 [get_ports pl_key]
set_property IOSTANDARD LVCMOS33 [get_ports pl_key]

# ------------------------------------------------------------------------------
# PL UART (BANK 43, 3.3V)
# ------------------------------------------------------------------------------
set_property PACKAGE_PIN AA11 [get_ports pl_uart_tx]
set_property IOSTANDARD LVCMOS33 [get_ports pl_uart_tx]
set_property PACKAGE_PIN AA10 [get_ports pl_uart_rx]
set_property IOSTANDARD LVCMOS33 [get_ports pl_uart_rx]

# ------------------------------------------------------------------------------
# Fan Control (BANK 44, 3.3V)
# ------------------------------------------------------------------------------
set_property PACKAGE_PIN AG14 [get_ports fan_ctrl]
set_property IOSTANDARD LVCMOS33 [get_ports fan_ctrl]

# ------------------------------------------------------------------------------
# RS485 Channel 1 (BANK 43/45, 3.3V)
# ------------------------------------------------------------------------------
set_property PACKAGE_PIN AG10 [get_ports rs485_txd1]
set_property IOSTANDARD LVCMOS33 [get_ports rs485_txd1]
set_property PACKAGE_PIN AH10 [get_ports rs485_rxd1]
set_property IOSTANDARD LVCMOS33 [get_ports rs485_rxd1]
set_property PACKAGE_PIN A10 [get_ports rs485_de1]
set_property IOSTANDARD LVCMOS33 [get_ports rs485_de1]

# ------------------------------------------------------------------------------
# RS485 Channel 2 (BANK 43, 3.3V)
# ------------------------------------------------------------------------------
set_property PACKAGE_PIN AH11 [get_ports rs485_txd2]
set_property IOSTANDARD LVCMOS33 [get_ports rs485_txd2]
set_property PACKAGE_PIN AH12 [get_ports rs485_rxd2]
set_property IOSTANDARD LVCMOS33 [get_ports rs485_rxd2]
set_property PACKAGE_PIN B11 [get_ports rs485_de2]
set_property IOSTANDARD LVCMOS33 [get_ports rs485_de2]

# ------------------------------------------------------------------------------
# PCIe Reset (BANK 43, 3.3V)
# ------------------------------------------------------------------------------
set_property PACKAGE_PIN AC11 [get_ports pcie_perst]
set_property IOSTANDARD LVCMOS33 [get_ports pcie_perst]

# ------------------------------------------------------------------------------
# MIPI Camera (BANK 65 = 1.2V for data, BANK 43 = 3.3V for control)
# NOTE: Jumper J43 must be set to PIN2-PIN3 for 1.2V BANK 65
# ------------------------------------------------------------------------------
set_property PACKAGE_PIN W8  [get_ports mipi_clk_p]
set_property PACKAGE_PIN Y8  [get_ports mipi_clk_n]
set_property IOSTANDARD LVDS [get_ports mipi_clk_p]
set_property IOSTANDARD LVDS [get_ports mipi_clk_n]

set_property PACKAGE_PIN U9  [get_ports mipi_lan0_p]
set_property PACKAGE_PIN V9  [get_ports mipi_lan0_n]
set_property IOSTANDARD LVDS [get_ports mipi_lan0_p]
set_property IOSTANDARD LVDS [get_ports mipi_lan0_n]

set_property PACKAGE_PIN U8  [get_ports mipi_lan1_p]
set_property PACKAGE_PIN V8  [get_ports mipi_lan1_n]
set_property IOSTANDARD LVDS [get_ports mipi_lan1_p]
set_property IOSTANDARD LVDS [get_ports mipi_lan1_n]

set_property PACKAGE_PIN AE10 [get_ports cam_gpio]
set_property IOSTANDARD LVCMOS33 [get_ports cam_gpio]
set_property PACKAGE_PIN AF10 [get_ports cam_clk]
set_property IOSTANDARD LVCMOS33 [get_ports cam_clk]
set_property PACKAGE_PIN Y9   [get_ports cam_scl]
set_property IOSTANDARD LVCMOS33 [get_ports cam_scl]
set_property PACKAGE_PIN AA8  [get_ports cam_sda]
set_property IOSTANDARD LVCMOS33 [get_ports cam_sda]

# ------------------------------------------------------------------------------
# SFP+ Fiber Control Signals (BANK 45, 3.3V)
# (GTH transceiver pins are auto-assigned in IP configuration)
# ------------------------------------------------------------------------------
set_property PACKAGE_PIN D12 [get_ports sfp_tx_dis]
set_property IOSTANDARD LVCMOS33 [get_ports sfp_tx_dis]
set_property PACKAGE_PIN B10 [get_ports sfp1_loss]
set_property IOSTANDARD LVCMOS33 [get_ports sfp1_loss]
set_property PACKAGE_PIN C11 [get_ports sfp2_loss]
set_property IOSTANDARD LVCMOS33 [get_ports sfp2_loss]
```

### IOSTANDARD Reference per Bank
| Bank | Voltage | IOSTANDARD (Single-ended) | IOSTANDARD (Differential) |
|---|---|---|---|
| BANK 43 | 3.3V | LVCMOS33 | — |
| BANK 44 | 3.3V | LVCMOS33 | — |
| BANK 45 | 3.3V | LVCMOS33 | — |
| BANK 46 | 3.3V | LVCMOS33 | — |
| BANK 64 | 1.8V | LVCMOS18 / SSTL12 | DIFF_SSTL12 |
| BANK 65 | 1.2V* / 1.8V | LVCMOS12 / LVCMOS18 | LVDS / DIFF_SSTL12 |
| BANK 66 | 1.8V | LVCMOS18 | LVDS / DIFF_SSTL12 |

---

## 14. Block Design — PS Configuration

### Step-by-Step PS Block Design

1. **Create Block Design**: Flow Navigator → IP INTEGRATOR → Create Block Design
2. **Add Zynq UltraScale+ MPSoC IP**: Click "+" → search "Zynq UltraScale+ MPSoC"
3. **Run Block Automation**: Click green banner → Check "Apply Board Preset" if using board files
4. **Double-click Zynq block** to configure:

#### PS Configuration Checklist

##### I/O Configuration Tab
Enable and configure the following based on your needs:

| Peripheral | MIO Pins | Notes |
|---|---|---|
| QSPI | MIO 0–5 | Boot flash |
| eMMC (SD1) | MIO 13–23 | 8-bit data |
| I2C 1 | MIO 24–25 | EEPROM + Temp sensor |
| UART 0 | MIO 42–43 | PS serial console |
| CAN 0 | MIO 32–33 | CAN bus 1 |
| CAN 1 | MIO 38–39 | CAN bus 2 |
| SD 1 (SD Card) | MIO 46–51 | SD card slot |
| USB 0 | MIO 52–63 | USB 3.0 |
| GEM 3 (Ethernet) | MIO 64–77 | PS-side GbE |
| GPIO | MIO 26 (Key), MIO 40 (LED) | User I/O |
| DisplayPort | MIO 27–30 (Aux), BANK 505 GTH (lanes) | DP output |

##### Clock Configuration Tab
| Parameter | Value |
|---|---|
| PS Input Reference Clock | 33.333 MHz |
| PL Fabric Clock 0 (pl_clk0) | 100 MHz (typical, adjustable) |
| PL Fabric Clock 1 (pl_clk1) | As needed |
| PL Fabric Clock 2 (pl_clk2) | As needed |
| PL Fabric Clock 3 (pl_clk3) | As needed |

##### DDR Configuration Tab
| Parameter | Value |
|---|---|
| DDR Type | DDR4 |
| Data Width | 64-bit |
| ECC | Disabled (no ECC chip on board) |
| Speed | 2400 Mbps (1200 MHz) |
| Chip Model | MT40A512M16LY-062E |

##### PS-PL Interfaces Tab
Enable interfaces as needed:
- **M_AXI_HPM0_FPD**: For PS to access PL peripherals (high-performance)
- **M_AXI_HPM0_LPD**: For PS to configure PL registers (low-latency)
- **S_AXI_HP0_FPD**: For PL to access PS DDR (high-performance DMA)
- **S_AXI_HPC0_FPD**: For cache-coherent PL access to PS memory

5. **Validate Design**: Click checkmark icon to verify no errors
6. **Create HDL Wrapper**: Right-click .bd file → Create HDL Wrapper → Let Vivado manage

---

## 15. Common IP Cores and Usage

### For PL-side DDR4 Access
- **Memory Interface Generator (MIG)**: Configure for DDR4, 16-bit, BANK 64, 200 MHz reference clock

### For Video Processing
- **Video DMA (AXI-VDMA)**: Frame buffer management for video pipelines
- **Video Timing Controller**: Generate/detect video timing signals
- **AXI4-Stream to Video Out**: Convert AXI-Stream to parallel video
- **Video In to AXI4-Stream**: Convert parallel video to AXI-Stream

### For High-Speed Serial
- **Aurora 64B/66B**: For SFP+ fiber optic communication (BANK 224 GTH)
- **XDMA (DMA/Bridge Subsystem for PCIe)**: For PCIe endpoint/root port

### For Peripheral Access
- **AXI GPIO**: Simple I/O control from PS
- **AXI UART Lite**: Simple UART controller
- **AXI IIC**: I2C master controller
- **AXI Timer**: Hardware timer/counter

### Custom IP Creation
Use **Tools → Create and Package New IP** to create custom AXI peripherals:
- AXI4-Lite slave (for register-based control)
- AXI4-Stream master/slave (for data streaming)
- AXI4 Full master (for memory-mapped DMA)

---

## 16. Bitstream Generation and Hardware Export

### Generate Bitstream
1. Flow Navigator → **Generate Bitstream**
2. Vivado automatically runs: Synthesis → Implementation → Bitstream generation
3. Review timing reports — ensure no timing violations (WNS > 0)

### Export Hardware
1. **File → Export → Export Hardware**
2. Select **Include bitstream**
3. Output format: `.xsa` (Xilinx Support Archive)
4. Use the `.xsa` file in **Vitis IDE** for software development

### Program FPGA via JTAG
1. Set DIP switch SW1 to JTAG mode (all ON)
2. Connect JTAG cable to the 10-pin JTAG header
3. **Flow Navigator → Open Hardware Manager → Open Target → Auto Connect**
4. Right-click device → **Program Device**
5. Select the `.bit` file → **Program**

---

## 17. JTAG Programming and Debug

### JTAG Header
- **Type**: 10-pin 2.54mm standard JTAG
- **Protection**: Protective diodes on JTAG signals prevent chip damage from hot-plugging
- **Downloader**: Use Xilinx Platform Cable USB II or compatible JTAG debugger

### Programming Modes

| Mode | Description | Use Case |
|---|---|---|
| **JTAG Direct** | Load bitstream directly to PL (volatile) | Active development, debugging |
| **QSPI Flash** | Program bitstream to QSPI (non-volatile) | Standalone deployment |
| **SD Card Boot** | Place BOOT.BIN on SD card | Linux development |
| **eMMC Boot** | Program boot image to eMMC | Production deployment |

### ILA (Integrated Logic Analyzer)
To debug PL designs in real-time:
1. Mark signals for debug in HDL: `(* mark_debug = "true" *)`
2. Or use **Set Up Debug** wizard after synthesis
3. Vivado inserts ILA IP core automatically
4. Use Hardware Manager to capture waveforms at runtime

---

## 18. Key Xilinx Documentation References

| Document | ID | Description |
|---|---|---|
| **Zynq UltraScale+ MPSoC Data Sheet: Overview** | DS891 | Device specifications, resource counts |
| **Zynq UltraScale+ Device Technical Reference Manual** | UG1085 | Comprehensive PS architecture, peripherals, registers |
| **Zynq UltraScale+ Device Packaging and Pinouts** | UG1075 | Package-specific pin maps |
| **Vivado Design Suite User Guide: IP Integrator** | UG994 | Block design workflow |
| **Vivado Design Suite User Guide: Using Constraints** | UG903 | XDC syntax and usage |
| **Vivado Design Suite User Guide: Programming and Debugging** | UG908 | JTAG, ILA, VIO usage |
| **AXI Reference Guide** | UG1037 | AXI protocol details |
| **IBERT LogiCORE IP** | PG173 | GTH transceiver debugging |
| **AXI DMA IP** | PG021 | DMA controller configuration |
| **AXI Video DMA IP** | PG020 | Video DMA configuration |
| **Memory Interface Generator (MIG)** | PG150 | DDR4 controller configuration |

---

## 19. Common Pitfalls and Troubleshooting

### ❌ Wrong IOSTANDARD for Bank Voltage
**Problem**: Setting LVCMOS33 on BANK 65/66 pins (max 1.8V) will damage the FPGA.
**Solution**: Always match IOSTANDARD to physical VCCO voltage:
- BANK 43–46: LVCMOS33
- BANK 64: SSTL12 / DIFF_SSTL12
- BANK 65: LVCMOS12 (MIPI mode) or LVCMOS18 (FMC mode)
- BANK 66: LVCMOS18

### ❌ BANK 65 Jumper Not Set Correctly
**Problem**: MIPI camera not working or FMC signals incorrect.
**Solution**: Check jumper J43:
- MIPI camera: PIN2-PIN3 (1.2V)
- FMC connector: PIN1-PIN2 (1.8V)

### ❌ M.2 SSD Not Detected
**Problem**: Using a SATA M.2 SSD instead of PCIe.
**Solution**: The M.2 slot only supports **PCIe-type** SSDs (M Key, NVMe). SATA M.2 SSDs will NOT work.

### ❌ Timing Violations in DDR4 Design
**Problem**: PL DDR4 MIG shows negative WNS.
**Solution**: 
- Use the 200 MHz PL system clock (AE5/AF5) as MIG reference clock
- Ensure proper pin assignments from the DDR4 pin table above
- Let MIG wizard auto-place the DDR4 controller

### ❌ PS UART Not Responding
**Problem**: No serial output from PS.
**Solution**: 
- Ensure UART0 is enabled in PS configuration (MIO 42–43)
- Check USB-to-UART cable is connected
- Default baud rate: 115200, 8N1

### ❌ Boot Fails from QSPI/SD/eMMC
**Problem**: Board doesn't boot after programming.
**Solution**: 
- Verify DIP switch SW1 matches desired boot mode
- Ensure BOOT.BIN is properly generated (FSBL + Bitstream + Application)
- For SD card: Format as FAT32, place BOOT.BIN in root

### ❌ Fan Not Spinning
**Problem**: Fan appears dead.
**Solution**: 
- Fan is controlled by PL pin AG14 (BANK 44)
- Drive AG14 HIGH to turn on fan
- Check fan power connector J42 (red = +, black = GND)

### ❌ Path Too Long Error in Vivado (Windows)
**Problem**: Vivado fails with path length errors.
**Solution**: Keep project path short (e.g., `C:\vivado_proj\` instead of deep nested directories)

---

## Appendix A: Board-to-Board Connector Pinout (Summary)

The core board connects to the carrier board via four 120-pin connectors: **J29, J30, J31, J32**. These carry:
- All PL I/O (HP: 96 pins, HD: 84 pins)
- PS MIO passthrough (USB, GbE, SD, UART, CAN, I2C, GPIO)
- 4 pairs of PS MGT transceivers (BANK 505)
- 4 GTH transceivers (BANK 224)
- Power (+12V, VCCO_65, VCCO_66, GND)

> **Note**: All differential pairs on the core board have been impedance-matched and length-matched for high-speed signal integrity.

---

## Appendix B: Vivado Tcl Quick Reference

```tcl
# Create project targeting AXU4EVB-P
create_project my_project ./my_project -part xczu4ev-sfvc784-1-i

# Create block design
create_bd_design "system"

# Add Zynq UltraScale+ PS
create_bd_cell -type ip -vlnv xilinx.com:ip:zynq_ultra_ps_e:3.3 zynq_ultra_ps_e_0

# Run block automation
apply_bd_automation -rule xilinx.com:bd_rule:zynq_ultra_ps_e -config {apply_board_preset "1"} [get_bd_cells zynq_ultra_ps_e_0]

# Validate design
validate_bd_design

# Create HDL wrapper
make_wrapper -files [get_files system.bd] -top

# Add wrapper to project
add_files -norecurse ./my_project.gen/sources_1/bd/system/hdl/system_wrapper.v

# Run synthesis
launch_runs synth_1 -jobs 4
wait_on_run synth_1

# Run implementation
launch_runs impl_1 -jobs 4
wait_on_run impl_1

# Generate bitstream
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

# Export hardware (with bitstream)
write_hw_platform -fixed -include_bit -force ./system_wrapper.xsa
```

---

## Appendix C: Verilog/VHDL Port Template

### Simple PL Design Template (Verilog)
```verilog
module top_level (
    // PL System Clock (200 MHz differential)
    input  wire sys_clk_p,
    input  wire sys_clk_n,
    
    // PL User LED
    output wire pl_led,
    
    // PL User Button (active low)
    input  wire pl_key,
    
    // PL UART
    output wire pl_uart_tx,
    input  wire pl_uart_rx,
    
    // Fan Control
    output wire fan_ctrl,
    
    // RS485 Channel 1
    output wire rs485_txd1,
    input  wire rs485_rxd1,
    output wire rs485_de1
);

    // Differential clock buffer
    wire sys_clk;
    IBUFDS #(
        .DIFF_TERM("FALSE"),
        .IBUF_LOW_PWR("FALSE")
    ) ibufds_clk (
        .O(sys_clk),
        .I(sys_clk_p),
        .IB(sys_clk_n)
    );

    // Your design logic here
    
    // Default: fan ON, LED follows button
    assign fan_ctrl = 1'b1;
    assign pl_led = ~pl_key;  // LED on when button pressed

endmodule
```

---

> **Document Version**: 1.1  
> **Last Updated**: July 2026  
> **Source Documents**: ALINX AXU4EVB-P User Manual, ALINX AXU4EV-P Tutorial Documentation, Expansion Board Documentation (Adsız doküman 2), Xilinx DS891 Datasheet, Xilinx UG1085 Technical Reference Manual  
> **Target Audience**: AI assistant (Claude) for FPGA development guidance during internship project
