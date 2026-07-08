# MEGA VITIS INSTRUCTIONS

This document consolidates instructions from the following sources:
- AXU5EV-P User Manual.pdf
- Vitis/sub-docs/Adsız doküman (1).md
- Vitis/sub-docs/Adsız doküman.pdf
- Related-Repos/Board-repo/soms/alinx/ACU5EV.md

Note: Attempts to access the provided Feishu wiki links were unsuccessful due to authentication requirements.

---

## AXU5EV-P User Manual

### Overview
ZYNQ UltraScale+ FPGA Development Board
AXU5EV-P
User Manual

Version Record
- Version Rev 1.0 (2021-06-17)
- Version Rev 2.0 (2025-06-19)
- Released by Rachel Zhou and Fernand Xie
- Description: First Release (Rev 1.0), Modify eMMC Flash and add FMC pin number (Rev 2.0)

This MPSoCs FPGA development platform adopts the core board + carrier board mode, which is convenient for users to use the core board for secondary development. The core board uses XILINX Zynq UltraScale+ EV chip ZU5EV solution, uses Processing System(SS)+Programmable Logic(PL) technology to integrate dual-core ARM ARM Cortex-A53 and FPGA programmable logic on a single chip. In addition, the PS side of the core board has 4 pieces of 1GB high-speed DDR4 SDRAM chips, 1 piece of 32GB eMMC memory chip and 1 piece of 256Mb QSPI FLASH chip; the PL side of the core board has 1 piece of 1GB DDR4 SDRAM chip.

In the design of carrier board, we have extended a wealth of interfaces for users, such as 1 FMC LPC interface, 1 SATA M.2 interface, 1 DP interface, 1 PCIe x 2 Interfaces, 2 SPF+ Interfaces, 4 USB 3.0 Interface, 2 Gigabit Ethernet interfaces, 1 HDMI Input Interface, 1 HDMI Output Interface, 2 Uart Interfaces, 1 SD card slot, 2 x CAN bus interfaces, 2 x RS485 bus interfaces, 1 MIPI Camera Interface. It meets users' requirements for high-speed data exchange, data storage, Video transmission processing, deep learning, artificial intelligence and industrial control. It is a "professional" ZYNQ development platform. For high-speed data transmission and exchange, pre-verification and post-application of data processing is possible. This product is very suitable for students, engineers and other groups engaged in MPSoCs development.

---

### Part 1: FPGA Development Board Introduction

The entire structure of the AXU5EV-P FPGA development board is inherited from our consistent core board + carrier board model. A high-speed inter-board connector is used between the core board and the carrier board.

The core board is mainly composed of the smallest system of ACU5EV + 5 DDR4 + eMMC + QSPI FLASH, ACU5EV uses Xilinx's Zynq UltraScale+ MPSoCs EV chip, the model number is XCZU5EV-2SFVC784I. ZU5EV chip can be divided into processor system part Processor System (PS) and programmable logic part Programmable Logic (PL). On the PS side and PL side of the ZU5EV chip, there are 4 DDR4 and 1 DDR4 respectively, each with a capacity of up to 1GB, which enables the ARM system and FPGA system to independently process and store data. The 32GB eMMC FLASH memory chip and a 256Mb QSPI FLASH which are on the PS side, used to statically store the operating system, file system and user data of MPSoCs.

The AXU5EV-E carrier board expands its rich peripheral interface, including 1 M.2 interface, 1 DP interface, 4 USB 3.0 Interface, 2 Gigabit Ethernet interfaces, 1 PCIE X 2 Interface, 2 SFP Interfaces, 2 UART Interfaces, 1 SD card slot,1 HDMI Input Interface, 1 HDMI Output Interface,1 FMC Interface, 2 x CAN bus interfaces, 2 x RS485 bus interfaces, 1 MIPI Camera Interface and some keys and LEDs.

The following figure shows the structure of the entire development system:
Figure 1-1-1: The Schematic Diagram of the AXU5EV-P

Through this diagram, you can see the interfaces and functions that the AXU5EV-P FPGA Development Board contains:
- ACU5EV core board: It consists of ZU5EV +4GB DDR4PS+1GB DDR4PL+32GB eMMC FLASH + 256Mb QSPI FLASH, and there are 2 crystal oscillators to provide the clock, a single-ended 33.3333MHz crystal oscillator for the PS system, and a differential 200MHz crystal oscillator for the PL logic DDR reference clock.
- M.2 Interface: 1 PCIEx1 standard M.2 interface, used to connect M.2 SSD solid state drives, with a communication speed of up to 6Gbps.
- DP Output Interface: 1 standard Display Port output display output display interface, used for video image display. Supports up to 4K@30Hz or 1080P@60Hz output.
- USB 3.0 Interface: 4 x USB3.0 HOST interface, USB interface type is TYPE A. Used to connect external USB peripherals, such as connecting a mouse, keyboard, U disk, etc. Gigabit Ethernet Interface: 2 x10/100M/1000M Ethernet RJ45 interface for Ethernet data exchange with computers or other network devices. The network interface chip uses Micrel's KSZ9031 industrial grade GPHY chip. USB Uart Interface: 2 x Uart to USB interfaces for communication with the computer, for user debugging. The serial port chip adopts the USB-UAR chip of Silicon Labs CP2102GM, and the USB interface adopts the MINI USB interface. PCIe x 2 Interface: It supports the PCI Express 3.0 standard (compatible with 2.0), provides a standard PCIe x2 high-speed data transmission interface, and the single-channel communication rate can be as high as 8GBaud. 2 x SFP Fiber Interface: The two high-speed transceivers of the GTH transceiver are connected to the transmitting and receiving of two optical modules, realizing two high-speed optical fiber communication interfaces. The transmitting and sending speed of each optical fiber data communication is as high as 12.5Gb/s. SD Card Slot Interface: 1 Micro SD card holder, used to store operating system image and file system.
- HDMI Output Interface: 1 HDMI video output interface, using ADV7511 HDMI encoding chip from ANALOG DEVICE, supports up to 1080P@60Hz output and 3D output.
- HDMI Input Interface: 1 HDMI video input interface, using ADV7611 HDMI decoding chip from ANALOG DEVICE, supports up to 1080P@60Hz input and supports data input in different formats.
- FMC Expansion Interface: 1 standard FMC LPC expansion port, which can be connected to various FMC modules of XILINX or ALINX (HDMI input and output modules, binocular camera modules, high-speed AD modules, etc.).
- CAN Communication Interface: Two-way CAN bus interface, using TI's SN65HVD232 chip, the interface uses 4Pin green terminal blocks.
- 485 Communication Interface: Two-way 485 communication interface, using MAX3485 chip of MAXIM company. The interface uses 6Pin green terminal blocks.
- MIPI Interface: MIPI camera input interfaces, used to connect MIPI camera module (AN5641).
- JTAG debug port: A 10-pin 0.1 spacing standard JTAG ports for FPGA program download and debugging. Users can debug and download the ZU4EV system through the XILINX downloader.
- Temperature and humidity sensor chip: LM75 On-board temperature and humidity sensor chip LM75, used to detect the temperature and humidity of the surrounding environment around the FPGA development board.
- EEPROM: One EEPROM 24LC04 with I2C interface.
- Real Time Clock (RTC): 1 built-in RTC real-time clock.
- LED Lights: 5 LEDs, include 2 LEDs on the core board, 3 LED on the carrier board. There are 1 power indicator and 1 DONE Configuration indicator on the core board, 1 power indicator on the carrier board. There are 1 power indicator and 2 user indicators on the carrier board.
- KEYs: 3 KEYs, include 1 Rest KEY and 2 User KEYs.

---

### Part 2: ACU5EV Core Board

#### Part 2.1: ACU5EV Core Board Introduction
ACU5EV (core board model, the same below) FPGA core board, ZYNQ chip is based on XCZU5EV-2SFVC784I of XILINX company Zynq UltraScale+ MPSoCs EV Family.

This core board uses 5 Micron DDR4 chips MT40A512M16GE, of which 4 DDR4 chips are mounted on the PS side to form a 64-bit data bus bandwidth and 4GB capacity. One DDR4 chip is mounted on the PL end, which is a 16-bit data bus width and a capacity of 1GB. The highest operating speed of DDR4 SDRAM on the PS side can reach 1200MHz (data rate 2400Mbps), and the highest operating speed of DDR4 SDRAM on the PL side can reach 1066MHz (data rate 2132Mbps). In addition, a 256MBit QSPI FLASH and an 32GB eMMC FLASH chip are also integrated on the core board to start storage configuration and system files.

In order to connect with the carrier board, the four board-to-board connectors of this core board expand the PS side USB2.0 interface, Gigabit Ethernet interface, SD card interface and other remaining MIO ports; also expand 4 pairs of PS MGT high-speed transceiver interface; and almost all IO ports on the PL side (HP I/O: 96, HD I/O: 84). The wiring between the XCZU5EV chip and the interface has been processed with equal length and differential, and the core board size is only 3.15*2.36 (inch), which is very suitable for secondary development.

#### Part 2.2: ZYNQ Chip
The FPGA core board ACU5EV uses Xilinx's Zynq UltraScale+ MPSoCs EV family chip, module XCZU5EV-2SFVC784I. The PS system of the ZU5EV chip integrates 4 ARM CortexTM-A53 processors with a speed of up to 1.2Ghz and supports Level 2 Cache; it also contains 2 Cortex-R5 processors with a speed of up to 500Mhz.

The ZU5EV chip supports 32-bit or 64-bit DDR4, LPDDR4, DDR3, DDR3L, LPDDR3 memory chips, with rich high-speed interfaces on the PS side such as PCIE Gen2, USB3.0, SATA 3.1, DisplayPort; it also supports USB2.0, Gigabit Ethernet, SD/SDIO, I2C, CAN, UART, GPIO and other interfaces. The PL end contains a wealth of programmable logic units, DSP and internal RAM.

Figure 2-2-1 detailed the Overall Block Diagram of the ZU5EV Chip.

**The main parameters of the PS system part are as follows:**
- ARM quad-core Cortex TM -A53 processor, speed up to 1.5GHz, each
- CPU 32KB level 1 instruction and data cache, 1MB level 2 cache, shared by 2 CPUs
- ARM dual-core Cortex-R5 processor, speed up to 600MHz, each CPU 32KB level 1 instruction and data cache, and 128K tightly coupled memory
- Image Video Processor Mali-400 MP2, speed up to 677MHz, 64KB level 2 cache
- External storage interface, support 32/64bit DDR4/3/3L, LPDDR4/3 interface
- Static storage interface, support NAND, 2xQuad-SPI FLASH
- High-speed connection interface, support PCIe Gen2 x 4, 2 x USB3.0, Sata 3.1, Display Port, 4 x Tri-mode Gigabit Ethernet
- Common connection interfaces: 2 x USB2.0, 2 x SD/SDIO, 2 x UART, 2 x CAN 2.0B, 2 x I2C, 2 x SPI, 4 x 32b GPIO
- Power management: Support the four-part division of power supply Full/ Low/ PL/ Battery
- Encryption algorithm: support RSA, AES and SHA
- System monitoring: 10-bit 1Mbps AD sampling for temperature and voltage detection

**The main parameters of the PL logic part are as follows:**
- System Logic Cells: 256.2K
- CLB Flip-flops: 234.24K
- Look-up-tables (LUTs): 117.12K
- Block RAM: 5.1 Mb
- Clock Management Units (CMTs): 4
- DSP Slices: 1248
- Video Codec Unit (VCU): 1
- PCIE3.0: 2
- GTH 12.5Gb/s Transceiver: 4

XCZU5EV-2SFVC784I chip speed grade is -2, industrial grade, package is SFVC784

#### Part 2.3: DDR4 DRAM
The ACU5EV core board is equipped with 5 Micron (Micron) 1GB DDR4 chips, model MT40A512M16LY-062E, of which 4 DDR4 chips are mounted on the PS side to form a 64-bit data bus bandwidth and 4GB capacity. One DDR4 chip is mounted on the PL end, which is a 16-bit data bus width and a capacity of 1GB.

The maximum operating speed of the DDR4 SDRAM on the PS side can reach 1200MHz (data rate 2400Mbps), and the 4 DDR4 storage systems are directly connected to the memory interface of the PS BANK504. The highest operating speed of the DDR4 SDRAM on the PL side can reach 1066MHz (data rate