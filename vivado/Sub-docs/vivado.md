We promise that this tutorial is not a permanent and unchanging document. We will continuously revise and optimize the tutorial based on feedback from everyone on the forum and actual development experience.​
Order​
First of all, thank you all for purchasing the ZYNQ development boards AXU3EG, AXU4EV, and AXU5EV produced by Xinyi Electronic Technology (Shanghai) Co., Ltd.! Your support and trust in us and our products have added confidence and courage to us to move forward forever.​
Someone may ask if someone with zero foundation can learn ZYNQ? It depends on where the zero is. If you can't even understand the schematic, don't know what an array is in C language, and have no concept of pointers, then you have a negative foundation. To learn ZYNQ, you need basic hardware knowledge and proficient C language skills.​
This tutorial is a partial tutorial on FPGA. Through continuous practice, you can master the basic process of FPGA development. Although it does not explain many principles, practice makes perfect. With more practice, you can gradually master the secrets.​
Part 1: Introduction to Ultrascale+ MPSoC​
The Zynq UltraScale + MPSoC series is the second generation Zynq platform of Xilinx. Its highlight is that the FPGA includes a complete ARM processing subsystem (PS), including a quad-core Cortex-A53 processor or a dual-core Cortex-A53 plus a dual-core Cortex-R5 processor. The entire processor is built around the processor, and the processor subsystem integrates a memory controller and a large number of peripherals, making the processor core completely independent of the programmable logic unit in Zynq. In other words, if the programmable logic unit part (PL) is not currently used, the ARM processor subsystem can also work independently, which is fundamentally different from the previous FPGA, which is processor-centric.​
Zynq consists of two major functional blocks, PS and PL. In other words, it is the SOC part of ARM and the FPGA part. Among them, PS integrates APU ARM Cortex ™ - A53 processor, RPU Cortex-R5 processor, AMBA ® interconnect, internal memory (OCM), external memory interface (DDR Controller) and peripherals (IOU). These peripherals (IOU) mainly include USB bus interface, Ethernet interface, SD/eMMC interface, I2C bus interface, CAN bus interface, UART interface, GPIO, etc. High-speed interfaces such as PCIe, SATA, Display Port.

Overall block diagram of ZYNQ MPSoC chip​
​
PS: Processing System is the part of ARM's SoC that is independent of FPGA.​
PL: Programmable Logic, which refers to the FPGA part.​
1.
PS and PL interconnection technology​
ZYNQ, as a product that closely combines high-performance ARM Cortex-A53 series processors with high-performance FPGA in a single chip, needs to design an efficient interconnection path between on-chip high-performance processors and FPGA to achieve high-speed communication and data exchange between ARM processors and FPGA, and to leverage the performance advantages of ARM processors and FPGA. Therefore, how to design an efficient PL and PS data interaction path is the top priority of ZYNQ chip design and one of the keys to the success or failure of product design. In this section, we will mainly introduce the connection between PS and PL, allowing users to understand the technology of the connection between PS and PL.​
In fact, in the specific design, we often don't need to do too much work on the connection. After we add the IP core, the system will automatically use the AXI interface to connect our IP core to the processor. We just need to add a little more.​
AXI, short for Advanced eXtensible Interface, is an interface protocol introduced by Xilinx starting from the FPGA series 6. It mainly describes the data transmission method between master and slave devices. It continues to be used in ZYNQ, with version AXI4, so we often see AXI4.0. ZYNQ internal devices all have AXI interfaces. In fact, AXI is a part of AMBA (Advanced Microcontroller Bus Architecture) proposed by ARM, which is a high-performance, high-bandwidth, low-latency on-chip bus and is also used to replace the previous AHB and APB buses. The first version of AXI (AXI3) was included in AMBA3.0 released in 2003, and the second version of AXI (AXI4) was included in AMBA 4.0 released in 2010.​
The AXI protocol mainly describes the data transmission method between the master and slave devices. The master and slave devices establish a connection through handshake signals. When the slave device is ready to receive data, it will send a READY signal. When the data of the master device is ready, it will send and maintain a VALID signal, indicating that the data is valid. Data only starts to be transmitted when both VALID and READY signals are valid. When these two signals remain valid, the master device will continue to transmit the next data. The master device can revoke the VALID signal or the slave device can revoke the READY signal to terminate the transmission. The AXI protocol is shown in the figure. At T2, the READY signal of the slave device is valid, and at T3, the VILID signal of the master device is valid, and the data transmission begins.

It has the characteristics of lightweight and simple structure, suitable for small batch data and simple control occasions. It does not support batch transmission, and can only read and write one word (32 bits) at a time. It is mainly used to access some low-speed peripherals and control peripherals.​
AXI4:​
The interface is similar to AXI-Lite, except that it adds a function of batch transmission, which can continuously read and write one address at a time. That is to say, it has the burst function of data reading and writing.​
Both of the above methods use memory mapping control, that is, ARM weaves the user-defined IP into a certain address for access. When reading and writing, it is like reading and writing to your own on-chip RAM, and programming is also very convenient, with low development difficulty. The cost is that it occupies too many resources and requires additional signal lines such as read address lines, write address lines, read data lines, write data lines, and write response lines.​
AXI4-Stream：​
This is a continuous stream interface that does not require address lines (similar to FIFO, just keep reading or writing). For this type of IP, ARM cannot control it through the memory mapping method above (FIFO has no concept of address), and there must be a conversion device, such as AXI-DMA module, to achieve the conversion from memory mapping to streaming interface. AXI-Stream is suitable for many occasions: video stream processing, Communication Protocol conversion, Digital Signal Processing, wireless communication, etc. Its essence is a data path constructed for numerical streams, constructing a continuous data stream from the source (such as ARM memory, DMA, wireless receiving front end, etc.) to the sink (such as HDMI display, high-speed AD audio output, etc.). This interface is suitable for real-time signal processing.​
​
AXI4 and AXI4-Lite interfaces contain 5 different channels.​
•
Read Address Channel​
•
Write Address Channel​
•
Read Data Channel​
•
Write Data Channel​
•
Write Response Channel​
​
Each channel is an independent AXI handshake protocol. The following two figures show the read and write models respectively.


AXI write data channel​
The AXI bus protocol is implemented by hardware in ZYNQ chip, including 12 physical interfaces, namely S_AXI_HP {0:3} _FPD, S_AXI_LPD, S_AXI_ACE_FPD, S_AXI_ACP_FPD, S_AXI_HPC {0,1} _FPD, M_AXI_HPM {0,1} _FPD, M_AXI_HPM0_LPD interfaces.​
S_AXI_HP {0:3} _FPD interface, is a high-performance/bandwidth AXI4 standard interface, a total of four, PL module as the main device connection. Mainly used for PL access to memory on PS (DDR and FPD Main Switch)​
S_AXI_LPD interface, high-performance port, connecting PL to LPD. Low-latency access to OCM and TCM, access to PS-side DDR.​
S_AXI_HPC {0,1} _FPD interface, connect PL to FPD, can connect to CCI, access L1 and L2 Cache, due to CCI, access to DDR controller will have a large delay.​
M_AXI_HPM {0,1} _FPD interface, high-performance bus, PS is master, connect FPD to PL, can be used for CPU, DMA, PCIe, etc. to push a large amount of data from PS to PL.​
M_AXI_HPM0_LPD interface, low latency interface bus, PS is master, connecting LPD to PL, can directly access the PL end of the BRAM, DDR, etc., is also often used to configure the PL end of the register.

Only M_AXI_HPM {0,1} _FPD and M_AXI_HPM0_LPD are Master Ports, that is, the host interface, and the rest are Slave Ports (slave interfaces). The host interface has the permission to initiate read and write, and ARM can use the two host interfaces to actively access PL logic. In fact, it maps PL to a certain address, and reading and writing PL registers is like reading and writing its own memory. The rest of the slave interfaces belong to passive interfaces, which accept read and write from PL and accept it. In PS and PL interconnection applications, the most commonly used interfaces are S_AXI_HP {0:3} _FPD, M_AXI_HPM {0,1} _FPD and M_AXI_HPM0_LPD.​
ARM located on the PS side directly supports the AXI interface with hardware, while PL needs to use logic to implement the corresponding AXI protocol. Xilinx provides ready-made IPs such as AXI-DMA, AXI-GPIO, AXI-Dataover, and AXI-Stream in the Vivado Development Environment, all of which implement corresponding interfaces. When using them, you can directly add them from the IP list of Vivado to achieve the corresponding functions. The following picture shows various DMA IPs under Vivado.

Below is an introduction to the functions of several commonly used AXI interface IPs.​
AXI-DMA: Conversion from PS memory to PL high-speed transmission high-speed channel AXI-HP < ---- > AXI-Stream​
AXI-FIFO-MM2S: Conversion from PS memory to PL universal transport channel AXI-HPM <-----> AXI-Stream​
AXI-Datamover: realizes the conversion from PS memory to PL high-speed transmission high-speed channel AXI-HP < ---- > AXI-Stream, but this time it is completely controlled by PL, and PS is completely passive.​
AXI-VDMA: realizes the conversion from PS memory to PL high-speed transmission high-speed channel AXI-HP < ---- > AXI-Stream, but it is specifically designed for two-dimensional data such as videos and images.​
AXI-CDMA: This is done by PL to move data from one location in memory to another without CPU intervention.​
We will give examples of how to use these IPs in later chapters. Sometimes, users need to develop their own defined IPs to communicate with PS, and they can use the wizard to generate corresponding IPs. User-defined IP cores can have interfaces such as AXI4-Lite, AXI4, AXI-Stream, PLB, and FSL. The latter two are not used because ARM does not support them.​
With the above official IPs and custom IPs generated by the wizard, users don't actually need to know too much about AXI timing (unless they really encounter problems), because Xilinx has encapsulated all the details related to AXI timing, and users only need to focus on their own logic implementation.​
Strictly speaking, the AXI protocol is a peer-to-peer leader/follower interface protocol. When multiple peripherals need to interact with each other, we need to add an AXI Interconnect module, which is the AXI interconnection matrix. Its function is to provide a switching mechanism for connecting one or more AXI master devices to one or more AXI slave devices (similar to the switching matrix in switch).​
This AXI Interconnect IP core can support up to 16 master devices and 16 slave devices. If more interfaces are needed, multiple IP cores can be added.​
​
There are several basic connection modes for AXI Interconnect:​
•
N-to-1 Interconnect ​
•
to-N Interconnect ​
•
N-to-M Interconnect (Crossbar Mode) ​
•
N-to-M Interconnect (Shared Access Mode)


The AXI interface devices inside ZYNQ are interconnected through the interconnection matrix, which ensures the efficiency of data transmission and the flexibility of connection. In Vivado, Xilinx provides an IP core axi_interconnect to implement this interconnection matrix, which we only need to call. 
•
Tcl script​
•
Good foundation in English reading​
​
3.2
Logic developers​
•
Computer organization principle​
•
C language​
•
Fundamentals of digital circuits​
Part 2: Development board hardware introduction​
Xinyi Electronic Technology (Shanghai) Co., Ltd. has officially released the 2019 development board (model: AXU4EV-P) based on the XILINX Zynq UltraScale + MPSoCs development platform. In order to help you quickly understand this development platform, we have compiled this user manual.​
This MPSoCs development platform adopts a core board and expansion board mode, which facilitates users' secondary development and utilization of the core board. The core board uses the XILINX Zynq UltraScale + EV chip ZU4EV solution, which integrates quad-core ARM Cortex-A53 and FPGA programmable logic on one chip using Processing System (PS) + Programmable Logic (PL) technology. In addition, the PS end of the core board has four 4GB high-speed DDR4 SDRAM chips, one 8GB eMMC storage chip, and one 256Mb QSPI FLASH chip; the PL end of the core board has one 1GB DDR4 SDRAM chip.​
We have expanded a rich range of peripheral interfaces for users in baseplate design, such as 1 FMC LPC interface, 1 SATA M.2 interface, 1 DP interface, 1 PCIE x2 interface, 2 SFP + fiber optic interfaces, 4 USB3.0 interfaces, 2 Gigabit Ethernet interfaces, 1 HDMI input interface, 1 HDMI output interface, 2 UART interfaces, 1 SD card interface, 2 CAN bus interfaces, 2 RS485 interfaces, and 1 MIPI camera interface, etc. It meets users' requirements for various high-speed data exchange, data storage, video transmission processing, Deep learning, artificial intelligence, and industrial control, and is a "professional-level" ZYNQ development platform. It provides the possibility for high-speed data transmission and exchange, early verification and later application of data processing. It is believed that such a product is very suitable for students, engineers and other groups engaged in MPSoCs development.
Here is a brief introduction to the functions of the AXU4EV-P MPSoCs development platform.​
The entire structure of the development board inherits our consistent core board + expansion board pattern. The core board and expansion board are connected by high-speed board-to-board connectors.​
The core board is mainly composed of the smallest system of ZU4EV + 5 DDR4 + eMMC + 1 QSPI FLASH. ZU4EV uses Xilinx's Zynq UltraScale + MPSoCs EV series chip, model XCZU4EV-1SFVC784I. The ZU4EV chip can be divided into the processor system part Processor System (PS) and the programmable logic part Programmable Logic (PL). Four and one DDR4 chips are respectively hung on the PS and PL ends of the ZU4EV chip, with each DDR4 chip having a capacity of up to 1G bytes, enabling the ARM system and FPGA system to independently process and store data. The 8GB eMMC FLASH memory chip and one 256Mb QSPI FLASH chip on the PS end are used to statically store the operating system, file system, and user data of MPSoCs.​
The baseplate has expanded the core board with rich peripheral interfaces, including 1 M.2 interface, 1 DP output interface, 4 USB3.0 interfaces, 2 Gigabit Ethernet interfaces, 1 PCIE x2 interface, 2 fiber optic interfaces, 2 UART interfaces, 1 SD card interface, 1 HDMI output interface, 1 HDMI input interface, 1 FMC interface, 2 CAN bus interfaces, 2 RS485 interfaces, 1 MIPI interface, and some button LEDs.​
The following is a schematic diagram of the structure of the entire development system.

•
JTAG debugging port​
One 10-pin 2.54mm standard JTAG port is used for downloading and debugging FPGA programs. Users can debug and download the ZU4EV system through the XILINX downloader.​
•
Temperature and humidity sensor​
One temperature and humidity sensor chip LM75 is onboard to detect the temperature and humidity of the surrounding environment of the board.​
•
EEPROM​
EEPROM 24LC04 with 1 IIC interface.​
•
RTC real-time clock​
1 built-in RTC real-time clock;​
•
LED lights​
5 Light Emitting Diode LEDs, 2 on the core board and 3 on the baseplate. 1 power indicator and 1 DONE configuration indicator on the core board. 1 power indicator and 2 user indicator on the baseplate.​
•
Button​
3 buttons, 1 reset button, 2 user buttons.​
​
​
1.
ACU4EV Core Board​
1.1
Introduction​
ACU4EV ( core board model, the same below ) core board, ZYNQ chip is based on XILINX's Zynq UltraScale + MPSoCs EV series XCZU4EV-1SFVC784I.​
This core board uses 5 Micron DDR4 chips MT40A512M16GE, with 4 DDR4 chips mounted on the PS side, forming a 64-bit data bus bandwidth and a capacity of 4GB. 1 chip is mounted on the PL side, with a 16-bit data bus width and a capacity of 1GB. The maximum operating speed of the DDR4 SDRAM on the PS side can reach 1200MHz (data rate 2400Mbps), and the maximum operating speed of the DDR4 SDRAM on the PL side can reach 1066MHz (data rate 2132Mbps). In addition, the core board also integrates a 256MBit QSPI FLASH and an 8GB eMMC FLASH chip for starting storage configuration and system files.​
In order to connect with the baseplate, the four board-to-board connectors of this core board have expanded the USB 2.0 interface, Gigabit Ethernet interface, SD card interface, and other remaining MIO ports on the PS side; it has also expanded four pairs of PS MGT high-speed transceiver interfaces; and the four GTH transceivers and almost all IO ports (HP I/O: 96, HD I/O: 84) on the PL side. The wiring between the XCZU4EV chip and the interface has been processed equally and differentially, and the core board size is only 80 * 60 (mm), which is very suitable for secondary development.
1.2
ZYNQ chip​
The development board uses Xilinx's Zynq UltraScale + MPSoCs EV series chip, model XCZU4EV-1SFVC784I. The PS system of the ZU4EV chip integrates four ARM Cortex ™ - A53 processors, with a speed of up to 1.5Ghz and supports level 2 cache; in addition, ZU4EV also includes two Cortex-R5 processors (with a speed of up to 600Mhz) and one video codec processor.​
The ZU4EV chip supports 32-bit or 64-bit DDR4, LPDDR4, DDR3, DDR3L, LPDDR3 storage chips, with rich high-speed interfaces such as PCIE Gen2, USB3.0, SATA 3.1, DisplayPort on the PS side; it also supports USB2.0, Gigabit Ethernet, SD/SDIO, I2C, CAN, UART, GPIO and other interfaces. The PL side contains rich programmable logic units, DSP and internal RAM. The overall block diagram of the ZU4EV chip is shown in Figure 2-2-1​

​•
DSP Slices: 728​
•
Image Codec Unit (VCU): 1​
•
PCIE3.0:2 pieces​
•
GTH 12.5Gb/s transceiver: 4​
The speed level of the XCZU4EV-1SFVC784I chip is -1, industrial grade, and packaged as SFVC784.​
​
1.3
DDR4 DRAM​
The ACU4EV core board is equipped with 5 Micron (Micron) 1GB DDR4 chips, model MT40A512M16GE-083E, among which 4 DDR4 chips are mounted on the PS side, forming a 64-bit data bus bandwidth and 4GB capacity. 1 chip is mounted on the PL side, with a 16-bit data bus width and 1GB capacity. The maximum operating speed of the DDR4 SDRAM on the PS side can reach 1200MHz (data rate 2400Mbps), and the 4 DDR4 storage systems are directly connected to the memory interface of PS's BANK504. The maximum operating speed of the DDR4 SDRAM on the PL side can reach 1066MHz (data rate 2132Mbps), and 1 DDR4 chip is connected to the interface of FPGA's BANK64. The specific configuration of the DDR4 SDRAM is shown in the following table 2-3-1.​
​
​
Locus number​
​
​
Chip model​
​
​
Capacity​
​
​
Manufacturer​
​
​
U12,U14,U15,U16​
​
​
MT40A512M16GE-083E​
​
​
512M x 16bit​
​
​
Micron​
​

​
Table 2-3-1 DDR4 SDRAM Configuration​
The hardware design of DDR4 requires strict consideration of signal integrity. We have fully considered matching resistors/end point resistors, wiring impedance control, and wiring length control in circuit design and PCB design to ensure the high-speed and stable operation of DDR4.​
​
PS DDR4 hardware connection is shown in Figure 2-3-1:​
​

​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
PL_DDR4_A3​
​
​
IO_L3N_T0L_N5_AD15N_64​
​
​
AC8​
​
​
PL_DDR4_A4​
​
​
IO_L11P_T1U_N8_GC_64​
​
​
AF7​
​
​
PL_DDR4_A5​
​
​
IO_L4P_T0U_N6_DBC_AD7P_64​
​
​
AD7​
​
​
PL_DDR4_A6​
​
​
IO_L9N_T1L_N5_AD12N_64​
​
​
AH7​
​
​
PL_DDR4_A7​
​
​
IO_L2P_T0L_N2_64​
​
​
AE9​
​
​
PL_DDR4_A8​
​
​
IO_L9P_T1L_N4_AD12P_64​
​
​
AH8​
​
​
PL_DDR4_A9​
​
​
IO_L1P_T0L_N0_DBC_64​
​
​
AC9​
​
​
PL_DDR4_A10​
​
​
IO_L4N_T0U_N7_DBC_AD7N_64​
​
​
AE7​
​
​
PL_DDR4_A11​
​
​
IO_L7N_T1L_N1_QBC_AD13N_64​
​
​
AH9​
​
​
PL_DDR4_A12​
​
​
IO_L6N_T0U_N11_AD6N_64​
​
​
AC6​
​
​
PL_DDR4_A13​
​
​
IO_L1N_T0L_N1_DBC_64​
​
​
AD9​
​
​
PL_DDR4_BA0​
​
​
IO_T1U_N12_64​
​
​
AH6​
​
​
PL_DDR4_BA1​
​
​
IO_L5N_T0U_N9_AD14N_64​
​
​
AC7​
​
​
PL_DDR4_RAS_B​
​
​
IO_T2U_N12_64​
​
​
AB5​
​
​
PL_DDR4_CAS_B​
​
​
IO_L5P_T0U_N8_AD14P_64​
​
​
AB7​
​
​
PL_DDR4_WE_B​
​
​
IO_L11N_T1U_N9_GC_64​
​
​
AF6​
​
​
PL_DDR4_ACT_B​
​
​
IO_L13N_T2L_N1_GC_QBC_64​
​
​
AD4​
​
​
PL_DDR4_CS_B​
​
​
IO_L6P_T0U_N10_AD6P_64​
​
​
AB6​
​
​
PL_DDR4_BG0​
​
​
IO_L2N_T0L_N3_64​
​
​
AE8​
​
​
PL_DDR4_RST​
​
​
IO_L7P_T1L_N0_QBC_AD13P_64​
​
​
AG9​
​
​
PL_DDR4_CLK_N​
​
​
IO_L10N_T1U_N7_QBC_AD4N_64​
​
​
AG5​
​
​
PL_DDR4_CLK_P​
​
​
IO_L10P_T1U_N6_QBC_AD4P_64​
​
​
AG6​
​
​
PL_DDR4_CKE​
​
​
IO_T3U_N12_64​
​
​
AE4​
​
​
PL_DDR4_OTD​
​
​
IO_L19N_T3L_N1_DBC_AD9N_64​
​
​
AH4​
​

1.4
QSPI Flash​
The ACU4EV core board is equipped with a 256MBit Quad-SPI FLASH chip to form an 8-bit bandwidth data bus. The FLASH model is MT25QU256ABA1EW9, which uses the 1.8V CMOS voltage standard. Due to the non-volatile nature of QSPI FLASH, it can be used as a system startup device to store system startup mirroring. These mirroring mainly include FPGA bit files, ARM application code, and other user data files. The specific model and related parameters of QSPI FLASH are shown in Table 2-4-1.​
​
​
​
Locus number​
​
​
Chip type​
​
​
Capacity​
​
​
Manufacturer​
​
​
U5​
​
​
MT25QU256ABA1EW9​
​
​
256M bit​
​
​
Winbond​
​

​
Table 2-4-1 QSPI Flash models and parameters​
​
QSPI FLASH is connected to the GPIO port of the PS part of the ZYNQ chip BANK500. In the system design, it is necessary to configure the GPIO port function of these PS ends as QSPI FLASH interface. Figure 4-1 shows the part of QSPI Flash in the schematic diagram.​
​



Figure 2-4-1 QSPI Flash connection diagram​
​
Configure chip pin allocation:​
​
​
Signal name​
​
​
Pin name​
​
​
Pin number​
​
​
MIO0_QSPI0_SCORE​
​
​
PS_MIO0_500​
​
​
AG15​
​
​
MIO1_QSPI0_IO1​
​
​
PS_MIO1_500​
​
​
AG16​
​
​
MIO2_QSPI0_IO2​
​
​
PS_MIO2_500​
​
​
AF15​
​
​
MIO3_QSPI0_IO3​
​
​
PS_MIO3_500​
​
​
AH15​
​
​
MY4_QSPI0_IO0​
​
​
PS_MIO4_500​
​
​
AH16​
​
​
MIO5_QSPI0_SS_B​
​
​
PS_MIO5_500​
​
​
AD16​
​

​
​
1.5
eMMC Flash​
The ACU4EV core board is equipped with a large-capacity 8GB eMMC FLASH chip, model MTFC8GAKAJCN-4M, which supports the HS-MMC interface of JEDEC e-MMC V5.0 standard, with a level support of 1.8V or 3.3V. The data width of eMMC FLASH and ZYNQ connection is 8 bits. Due to the large capacity and non-volatile characteristics of eMMC FLASH, it can be used as a large-capacity storage device in ZYNQ system, such as storing ARM applications, system files, and other user data files. the specific model and related parameters of eMMC FLASH are shown in Table 2-5-1.​
​
​
Locus number​
​
​
Chip type​
​
​
Capacity​
​
​
Manufacturer​
​
​
U19​
​
​
MTFC8GAKAJCN-4M​
​
​
8G Byte​
​
​
Micron​
​

​
Table 2-5-1 eMMC Flash models and parameters​
​
The eMMC FLASH is connected to the GPIO port of the PS part of the ZYNQ UltraScale + BANK500. In the system design, it is necessary to configure the GPIO port function of these PS ends as the EMMC interface. The figure 2-5-1 the part of the eMMC Flash in the schematic diagram.
Figure 2-5-1 eMMC Flash connection diagram​
​
Configure chip pin allocation:​
​
​
Signal name​
​
​
Pin name​
​
​
Pin number​
​
​
MMC_DAT0​
​
​
PS_MIO13_500​
​
​
AH18​
​
​
MMC_DAT1​
​
​
PS_MIO14_500​
​
​
AG18​
​
​
MMC_DAT2​
​
​
PS_MIO15_500​
​
​
AE18​
​
​
MMC_DAT3​
​
​
PS_MIO16_500​
​
​
AF18​
​
​
MMC_DAT4​
​
​
PS_MIO17_500​
​
​
AC18​
​
​
MMC_DAT5​
​
​
PS_MIO18_500​
​
​
AC19​
​
​
MMC_DAT6​
​
​
PS_MIO19_500​
​
​
AE19​
​
​
MMC_DAT7​
​
​
PS_MIO20_500​
​
​
AD19​
​
​
MMC_CMD​
​
​
PS_MIO21_500​
​
​
AC21​
​
​
MMC_CCLK​
​
​
PS_MIO22_500​
​
​
AB20​
​
​
MMC_RSTN​
​
​
PS_MIO23_500​
​
​
AB18​
​

​
​
1.6
Clock configuration​
The core board provides reference clock and RTC real-time clock for PS system and PL logic respectively, so that PS system and PL logic can work independently. The schematic diagram of clock circuit design is shown in the following figure 2-6-1:

Figure 2-6-1 Core Board Clock Source​
​
PS system RTC real-time clock​
The passive crystal Y2 on the core board provides a real-time clock source of 32.768KHz for the PS system. The crystal is connected to the PS_PADI_503 and PS_PADO_503 pins of the BANK503 of the ZYNQ chip. Its schematic is shown in Figure 2-6-2:​
​



Clock pin allocation:​
​
​
Signal name​
​
​
Pin​
​
​
PS_PADI_503​
​
​
N17​
​
​
PS_PADO_503​
​
​
N18​
​

​
​
PS system clock source​
The X1 crystal oscillator on the core board provides a clock input of 33.333MHz for the PS part. The clock input is connected to the PS_REF_CLK_503 pin of the BANK503 of the ZYNQ chip. Its schematic is shown in Figure 2-6-3:​
Figure 2-6-3 Active crystal oscillator in PS section​
​
Clock pin allocation:​
​
​
Signal name​
​
​
Pin​
​
​
PS_CLK​
​
​
R16​
​

​
​
PL system clock source​
A differential 200MHz PL system clock source is provided on the board for the reference clock of the DDR4 controller. The crystal output is connected to the timestamp oracle (MRCC) of the PL BANK64, which can be used to drive the DDR4 controller and user logic circuit in the FPGA. The schematic of the clock source is shown in Figure 2-6-4​
​



Figure 2-6-4 PL system clock source​
​
PL clock pin allocation:​
​
​
Signal name​
​
​
Pin​
​
​
PL_CLK0_P​
​
​
AE5​
​
​
PL_CLK0_N​
​
​
AF5​
​

​
​
1.7
LED lights​
The ACU4EV core board has 1 red power indicator (PWR) and 1 configuration LED light (DONE). When the core board is powered, the power indicator light will light up; when the FPGA configuration program, the configuration LED light will light up. The schematic diagram of the hardware connection of the LED light is shown in Figure 2-7-1:
Figure 2-7-1 Core board LED lamp hardware connection schematic​
​
1.8
Power supply​
The power supply voltage of the ACU4EV core board is + 12V, and power is supplied to the core board by connecting the baseplate. All the power required for the XCZU4EV chip is generated on the core board through a PMIC chip TPS6508641. Please refer to the power chip manual for the design of the TPS6508641 power supply. The design diagram is as follows:​
​


In addition, the VCCIO power supply of the BANK65 and BANK66 of the XCZU4EV chips is provided by the baseplate, which is convenient for users to modify, but the maximum power supply cannot exceed 1.8V.​
​

​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
79​
​
​
PS_MIO49​
​
​
M18​
​
​
80​
​
​
PS_MIO75​
​
​
A19​
​
​
81​
​
​
PS_MIO34​
​
​
L17​
​
​
82​
​
​
PS_MIO70​
​
​
C19​
​
​
83​
​
​
GND​
​
​
-​
​
​
84​
​
​
GND​
​
​
-​
​
​
85​
​
​
PS_MIO26​
​
​
L15​
​
​
86​
​
​
PS_MIO43​
​
​
K19​
​
​
87​
​
​
PS_MIO24​
​
​
AB19​
​
​
88​
​
​
PS_MIO51​
​
​
L21​
​
​
89​
​
​
GND​
​
​
-​
​
​
90​
​
​
GND​
​
​
-​
​
​
91​
​
​
PS_MIO25​
​
​
AB21​
​
​
92​
​
​
PS_MIO42​
​
​
L18​
​
​
93​
​
​
-​
​
​
-​
​
​
94​
​
​
PS_MIO33​
​
​
L16​
​
​
95​
​
​
GND​
​
​
-​
​
​
96​
​
​
GND​
​
​
-​
​
​
97​
​
​
-​
​
​
-​
​
​
98​
​
​
-​
​
​
-​
​
​
99​
​
​
VCCO_65​
​
​
-​
​
​
100​
​
​
VCCO_66​
​
​
-​
​
​
101​
​
​
VCCO_65​
​
​
-​
​
​
102​
​
​
VCCO_66​
​
​
-​
​
​
103​
​
​
VCCO_65​
​
​
-​
​
​
104​
​
​
VCCO_66​
​
​
-​
​
​
105​
​
​
GND​
​
​
-​
​
​
106​
​
​
GND​
​
​
-​
​
​
107​
​
​
+12V​
​
​
-​
​
​
108​
​
​
+12V​
​
​
-​
​
​
109​
​
​
+12V​
​
​
-​
​
​
110​
​
​
+12V​
​
​
-​
​
​
111​
​
​
+12V​
​
​
-​
​
​
112​
​
​
+12V​
​
​
-​
​
​
113​
​
​
+12V​
​
​
-​
​
​
114​
​
​
+12V​
​
​
-​
​
​
115​
​
​
+12V​
​
​
-​
​
​
116​
​
​
+12V​
​
​
-​
​
​
117​
​
​
+12V​
​
​
-​
​
​
118​
​
​
+12V​
​
​
-​
​
​
119​
​
​
+12V​
​
​
-​
​
​
120​
​
​
+12V​
​
​
-​
​

​
​
​
​
2.2
M.2 interface​
The AXU4EV-P development board is equipped with a PCIE x1 standard M.2 interface for connecting to an M.2 SSD with a communication speed of up to 6Gbps. The M.2 interface uses an M key slot and only supports PCI-E, not SATA. When users choose an SSD, they need to choose a PCIE type SSD.​
The PCIE signal is directly connected to the ZU4EV's BANK505 PS MGT transceiver. The TX and RX signals are connected to the MGT's LANE1 in a differential signal manner. The PCIE clock is provided by the Si5332 chip, with a frequency of 100Mhz. The schematic diagram of the M.2 circuit design is shown in the following figure 3-2-1:
​
​
Signal name​
​
​
Pin name​
​
​
Pin number​
​
​
Remarks​
​
​
PCIE_TX_P​
​
​
505_TX0_P​
​
​
E25​
​
​
PCIE data transmission positive​
​
​
PCIE _TX_N​
​
​
505_TX0_N​
​
​
E26​
​
​
PCIE data transmission negative​
​
​
PCIE _RX_P​
​
​
505_RX0_P​
​
​
F27​
​
​
PCIE data reception positive​
​
​
PCIE _RX_N​
​
​
505_RX0_N​
​
​
F28​
​
​
PCIE data reception negative​
​
​
505_PCIE_REFCLK_P​
​
​
505_CLK0_P​
​
​
F23​
​
​
PCIE reference clock positive​
​
​
505_PCIE_REFCLK_N​
​
​
505_CLK0_N​
​
​
F24​
​
​
PCIE reference clock negative​
​
​
PCIE_RSTn_MIO37​
​
​
PS_MIO37_501​
​
​
J17​
​
​
PCIE reset signal​
​

​
2.3
DP display interface​
The AXU4EV-P development board comes with a standard DisplayPort output display interface for displaying video images. The interface supports the VESA DisplayPort V1.2a output standard, up to 4K x 2K@30Fps output, and supports Y-only, YCbCr444, YCbCr422, YCbCr420 and RGB video formats. Each color supports 6, 8, 10, or 12 bits.​
The DisplayPort data transmission channel is directly driven by ZU4EV's BANK505 PS MGT output. The LANE2 and LANE3 TX signals of the MGT are connected to the DP connector in a differential signal manner. The DisplayPort auxiliary channel is connected to the MIO pin of the PS. The schematic diagram of the DP output interface design is shown in the following figure 3-3-1:
3-3-1 DP interface design diagram​
​
DisplayPort interface ZYNQ pin allocation is as follows:​
​
​
Signal name​
​
​
ZYNQ pin name​
​
​
ZYNQ pin number​
​
​
Remarks​
​
​
GT0_DP_TX_P​
​
​
505_TX3_P​
​
​
B23​
​
​
DP data low transmission positive​
​
​
GT0_DP_TX_N​
​
​
505_TX3_N​
​
​
B24​
​
​
DP data low transmission negative​
​
​
GT1_DP_TX_P​
​
​
505_TX2_P​
​
​
C25​
​
​
DP data high-level transmission positive​
​
​
GT1_DP_TX_N​
​
​
505_TX2_N​
​
​
C26​
​
​
DP data high-level transmission negative​
​
​
505_CLK1_P​
​
​
505_CLK2_P​
​
​
C21​
​
​
DP reference clock is positive​
​
​
505_CLK1_N​
​
​
505_CLK2_N​
​
​
C22​
​
​
DP reference clock negative​
​
​
DP_AUX_OUT​
​
​
PS_MIO27​
​
​
J15​
​
​
DP auxiliary data output​
​
​
DP_AUX_IN​
​
​
PS_MIO30​
​
​
F16​
​
​
DP auxiliary data input​
​
​
DP_OE​
​
​
PS_MIO29​
​
​
G16​
​
​
DP auxiliary data output enable​
​
​
DP_HPD​
​
​
PS_MIO28​
​
​
K15​
​
​
DP insertion signal detection​
​

​
​
2.4
USB 3.0 interface​
The AXU4EV-P expansion board has 4 USB3.0 interfaces, supports HOST mode, and has a data transfer speed of up to 5.0Gb/s. USB3.0 is connected through the PIPE3 interface, and USB2.0 is connected to the external USB3320C chip through the ULPI interface, achieving high-speed data communication between USB3.0 and USB2.0.​
The USB interface is a flat USB interface (USB Type A), which is convenient for users to connect different USB slave peripherals (such as USB mouse, keyboard or USB flash drive) at the same time. The schematic diagram of the USB 3.0 connection is shown in 3-4-1:
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
USB_NXT​
​
​
PS_MIO55​
​
​
B16​
​
​
USB 2.0 next data signal​
​
​
USB_RESET_N​
​
​
PS_MIO31​
​
​
H16​
​
​
USB2.0 reset signal​
​

​
​
2.5
Gigabit Ethernet interface​
The AXU4EV-P expansion board has two Gigabit Ethernet interfaces, one connected to the PS end and the other connected to the PL end. The GPHY chip uses Micrel's KSZ9031RNX Ethernet PHY chip to provide users with network communication services. The KSZ9031RNX chip supports 10/100/1000 Mbps network transmission rates and communicates with the MAC layer of the ZU4EV system through the RGMII interface. The KSZ9031RNX supports MDI/MDX Self-Adaptation, various speed Self-Adaptation, Master/Slave Self-Adaptation, and MDIO bus for PHY register management.​
The KSZ9031RNX will detect the level status of some specific IO to determine its operating mode. Table 3-5-1 describes the default setting information of the GPHY chip after power-on.​
​
​
Configure pin​
​
​
Explanation​
​
​
Configuration value​
​
​
PHYAD[2:0]​
​
​
PHY address for MDIO/MDC mode​
​
​
PHY Address 011​
​
​
CLK125_EN​
​
​
Enable 125Mhz clock output selection​
​
​
Enable​
​
​
LED_MODE​
​
​
LED light mode configuration​
​
​
Single LED light mode​
​
​
MODE0~MODE3​
​
​
Link Self-Adaptation and Full-Duplex Configuration​
​
​
10/100/1000 Self-Adaptation, compatible with full-duplex and half-duplex​
​

​
Table 3-5-1 PHY chip default configuration values​
​
When the network is connected to Gigabit Ethernet, the data transmission between ZYNQ and PHY chip KSZ9031RNX is communicated through the RGMII bus, with a transmission clock of 125Mhz, and the data is sampled at the rising edge and falling sample of the clock.​
When the network is connected to 100Mbps Ethernet, the data transmission between ZYNQ and PHY chip KSZ9031RNX is communicated through the RMII bus, and the transmission clock is 25Mhz. The data is sampled at the rising edge and falling sample of the clock.​
Figure 3-5-1 is a schematic diagram of ZYNQ Ethernet PHY chip connection.

​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
Ethernet 2 RGMII receive clock​
​
​
PHY2_RXD0​
​
​
B66_L19_N​
​
​
A5​
​
​
Ethernet 2 receives data Bit0​
​
​
PHY2_RXD1​
​
​
B66_L19_P​
​
​
B5​
​
​
Ethernet 2 receives data Bit1​
​
​
PHY2_RXD2​
​
​
B66_L17_P​
​
​
F8​
​
​
Ethernet 2 receives data Bit2​
​
​
PHY2_RXD3​
​
​
B66_L24_P​
​
​
C9​
​
​
Ethernet 2 receives data Bit3​
​
​
PHY2_RXCTL​
​
​
B66_L22_N​
​
​
B8​
​
​
Ethernet 2 receives data valid signal​
​
​
PHY2_MDC​
​
​
B66_L21_N​
​
​
A6​
​
​
Ethernet 2 MDIO management clock​
​
​
PHY2_MDIO​
​
​
B66_L22_P​
​
​
C8​
​
​
Ethernet 2 MDIO manages data​
​
​
PHY2_RESET​
​
​
B66_L14_N​
​
​
D5​
​
​
Ethernet 2 reset signal​
​

​
2.6
USB Uart interface​
The AXU4EV-P expansion board is equipped with two Uart to USB interfaces, one connected to the PS end and one connected to the PL end. The conversion chip uses the USB-UAR chip of Silicon Labs CP2102GM, and the USB interface uses the MINI USB interface, which can be connected to the USB port of the PC for serial data communication with a USB cable. The schematic diagram of the USB Uart circuit design is shown in the following figure.​
​



3-6-1 USB to Serial​
​
​
ZYNQ pin allocation for USB to serial port:​
​
​
Signal name​
​
​
Pin name​
​
​
Pin number​
​
​
Remarks​
​
​
PS_UART0_TX​
​
​
PS_MIO43​
​
​
K19​
​
​
PS Uart data output​
​
​
PS_UART0_RX​
​
​
PS_MIO42​
​
​
L18​
​
​
PS Uart Data Input​
​
​
PL_UART_TX​
​
​
B43_L9_P​
​
​
AA11​
​
​
PL Uart data output​
​
​
PL_UART_RX​
​
​
B43_L9_N​
​
​
AA10​
​
​
PL Uart Data Input​
​

​
​
2.7
SD card slot​
The AXU4EV-P expansion board includes a Micro SD card interface to provide users with access to SD card memory for storing BOOT programs for ZU4EV chips, Linux operating system kernels, file systems, and other user data files.​
The SDIO signal is connected to the IO signal of the PS BANK501 of ZU4EV, because the VCCIO of 501 is set to 1.8V, but the data level of the SD card is 3.3V. Here we connect it through the TXS02612 level converter. The schematic diagram of the PS and SD card connectors of ZU4EV is shown in Figure 3-7-1.​
​



Figure 3-7-1 SD card connection diagram​
​
SD card slot pin distribution​
​
​
Signal name​
​
​
Pin name​
​
​
Pin number​
​
​
Remarks​
​
​
SD_CLK​
​
​
PS_MIO51​
​
​
l21​
​
​
SD clock signal​
​
​
SD_CMD​
​
​
PS_MIO50​
​
​
M19​
​
​
SD command signal​
​
​
SD_D0​
​
​
PS_MIO46​
​
​
L20​
​
​
SD Data0​
​
​
SD_D1​
​
​
PS_MIO47​
​
​
H21​
​
​
SD Data1​
​
​
SD_D2​
​
​
PS_MIO48​
​
​
J21​
​
​
SD Data Data2​
​
​
SD_D3​
​
​
PS_MIO49​
​
​
M18​
​
​
SD Data3​
​
​
SD_CD​
​
​
PS_MIO45​
​
​
K20​
​
​
SD card detection signal​
​

​
​
2.8
HDMI output interface​
The implementation of HDMI output interface is the use of ANALOG DEVICE ADV7511 HDMI (DVI) encoding chip, the highest support 1080P@60Hz output, support 3D output.​
Among them, the video digital interface, audio digital interface, and I2C configuration interface of ADV7511 are connected to the BANK45,46 IO of the ZU4EV PL part. The ZYNQ UltraScale + system initializes and controls ADV7511 through the I2C pin. The hardware connection diagram of ADV7511 chip and ZYNQ UltraScale + is shown in the following figure 3-8-1:​
​


​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
HDMI_D17​
​
​
B35_L15_P​
​
​
F17​
​
​
HDMI video signal data 17​
​
​
HDMI_D18​
​
​
B35_L7_N​
​
​
G16​
​
​
HDMI video signal data 18​
​
​
HDMI_D19​
​
​
B35_L7_P​
​
​
G17​
​
​
HDMI video signal data 19​
​
​
HDMI_D20​
​
​
B35_L6_N​
​
​
H16​
​
​
HDMI video signal data 20​
​
​
HDMI_D21​
​
​
B35_L6_P​
​
​
J16​
​
​
HDMI video signal data 21​
​
​
HDMI_D22​
​
​
B35_L17_P​
​
​
C17​
​
​
HDMI video signal data 22​
​
​
HDMI_D23​
​
​
B35_L17_N​
​
​
B16​
​
​
HDMI video signal data 23​
​
​
HDMI_SCL​
​
​
B35_L13_N​
​
​
E15​
​
​
HDMI IIC control clock​
​
​
HDMI _SDA​
​
​
B35_L13_P​
​
​
E16​
​
​
HDMI IIC control data​
​

​
​
2.9
HDMI input interface​
HDMI input interface We use ANALOG DEVICE ADV7611 decoding chip, the highest support 1080P@60Hz input, support different formats of data output.​
Among them, the IIC configuration interface of ADV7611 is also connected to the IO of ZU4EV PL, and ZYNQ initializes and controls ADV7611 through the programming of I2C bus. The hardware connection of HDMI input interface is shown in Figure 3-9-1.
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
HDMI_IN_D15​
​
​
B43_L10_P​
​
​
W10​
​
​
HDMI input video signal data 16​
​
​
HDMI_IN_D16​
​
​
B44_L11_N​
​
​
W11​
​
​
HDMI input video signal data 17​
​
​
HDMI_IN_D17​
​
​
B44_L11_P​
​
​
W12​
​
​
HDMI input video signal data 18​
​
​
HDMI_IN_D18​
​
​
B44_L9_N​
​
​
W13​
​
​
HDMI input video signal data 19​
​
​
HDMI_IN_D19​
​
​
B44_L9_P​
​
​
W14​
​
​
HDMI input video signal data 20​
​
​
HDMI_IN_D20​
​
​
B44_L8_P​
​
​
AB15​
​
​
HDMI input video signal data 21​
​
​
HDMI_IN_D21​
​
​
B44_L8_N​
​
​
AB14​
​
​
HDMI input video signal data 22​
​
​
HDMI_IN_D22​
​
​
B43_L2_N​
​
​
AG11​
​
​
HDMI input video signal data 23​
​
​
HDMI_IN_SDA​
​
​
B43_L5_P​
​
​
AE12​
​
​
ADV7611 IIC control clock​
​
​
HDMI_IN_SCL​
​
​
B43_L5_N​
​
​
AF12​
​
​
ADV7611 IIC control data​
​
​
HDMI_DSCL​
​
​
B45_L5_N​
​
​
F10​
​
​
EDID read IIC clock​
​
​
HDMI_DSDA​
​
​
B45_L5_P​
​
​
G11​
​
​
EDID reads IIC data​
​

​
​
2.10
Fiber optic interface​
The AXU4EV-P expansion board has two fiber optic interfaces. Users can purchase SFP optical modules (1.25G, 2.5G, 10G optical modules on the market) and insert them into these two fiber optic interfaces for fiber optic data communication. The two fiber optic interfaces are respectively connected to the two RX/TX channels of the GTH transceiver of ZYNQ's BANK224. The data rate of each TX transmission and RX reception is as high as 12.5Gb/s. The reference clock of the GTH transceiver is provided by the 125M differential clock of the core board.​
The ZYNQ Ultrascale + and fiber design diagram is shown in the following figure 3-10-1:​
​


2-Channel fiber optic interface ZYNQ pin allocation is as follows:​
​
​
Signal name​
​
​
ZYNQ pin name​
​
​
ZYNQ pin number​
​
​
Remarks​
​
​
SFP1_TX_N​
​
​
224_TX0_N​
​
​
W3​
​
​
Optical Module 1 Data Transmission Negative​
​
​
SFP1_TX_P​
​
​
224_TX0_P​
​
​
W4​
​
​
Optical Module 1 Data Transmission Positive​
​
​
SFP1_RX_N​
​
​
224_RX0_N​
​
​
Y1​
​
​
Optical module 1 receives negative data​
​
​
SFP1_RX_P​
​
​
224_RX0_P​
​
​
Y2​
​
​
Optical Module 1 Data Reception Positive​
​
​
SFP2_TX_N​
​
​
224_TX1_N​
​
​
U3​
​
​
Optical Module 2 Data Transmission Negative​
​
​
SFP2_TX_P​
​
​
224_TX1_P​
​
​
U4​
​
​
Optical Module 2 Data Transmission Positive​
​
​
SFP2_RX_N​
​
​
224_RX1_N​
​
​
V1​
​
​
Optical module 2 receives negative data​
​
​
SFP2_RX_P​
​
​
224_RX1_P​
​
​
V2​
​
​
Optical module 2 receives data positively​
​
​
SFP_TX_DIS​
​
​
B45_L12_P​
​
​
D12​
​
​
Optical module light emission prohibition, high efficiency​
​
​
SFP1_LOSS​
​
​
B45_L9_N​
​
​
B10​
​
​
Optical module 1 receives LOSS detection signal​
​
​
SFP2_LOSS​
​
​
B45_L9_P​
​
​
C11​
​
​
Optical module 2 receives LOSS detection signal​
​

​
​
2.11
PCIe slot​
The AXU4EV-P expansion board has a PCIe x2 interface, and two pairs of transceivers are connected to the golden finger of PCIEx2, which can achieve PCIE 3.0 (compatible with 2.0) data communication.​
The transceiver signal of the PCIe interface is directly connected to the GTH transceiver of the ZYNQ BANK224, and the single-channel communication rate can reach up to 8G bit bandwidth.​
The design diagram of the PCIe interface of the development board is shown in Figure 3-11-1, where the TX transmission signal is connected in AC coupling mode.
Figure 3-11-1 PCIe slot design schematic​
​
PCIe x2 interface ZYNQ pin allocation is as follows:​
​
​
Signal name​
​
​
ZYNQ pin name​
​
​
ZYNQ pin number​
​
​
Remarks​
​
​
PCIE_RX0_N​
​
​
224_RX2_N​
​
​
T1​
​
​
PCIE channel 0 data reception negative​
​
​
PCIE_RX0_P​
​
​
224_RX2_P​
​
​
T2​
​
​
PCIE channel 0 data reception positive​
​
​
PCIE_RX1_N​
​
​
224_RX3_N​
​
​
P1​
​
​
PCIE channel 1 data reception negative​
​
​
PCIE_RX1_P​
​
​
224_RX3_P​
​
​
P2​
​
​
PCIE channel 1 data reception positive​
​
​
PCIE_TX0_N​
​
​
224_TX2_N​
​
​
R3​
​
​
PCIE channel 0 data transmission negative​
​
​
PCIE_TX0_P​
​
​
224_TX2_P​
​
​
R4​
​
​
PCIE channel 0 data transmission positive​
​
​
PCIE_TX1_N​
​
​
224_TX3_N​
​
​
N3​
​
​
PCIE channel 1 data transmission negative​
​
​
PCIE_TX1_P​
​
​
224_TX3_P​
​
​
N4​
​
​
PCIE channel 1 data transmission positive​
​
​
PCIE_PERST​
​
​
B43_L8_N​
​
​
AC11​
​
​
Reset signal for PCIE board​
​

​
​
2.12
CAN communication interface​
The AXU4EV-P expansion board has two CAN communication interfaces, which are connected to the MIO interface of the PS system side BANK501. The CAN transceiver chip uses TI's SN65HVD232C chip to provide users with CAN communication services.​
Figure 3-12-1 is a schematic diagram of the connection of the PS-side CAN transceiver chip
Figure 3-12-1 connection schematic diagram of PS side CAN transceiver chip​
CAN communication pin allocation is as follows:​
​
​
Signal name​
​
​
Pin name​
​
​
Pin number​
​
​
Remarks​
​
​
PS_CAN1_TX​
​
​
PS_MIO32​
​
​
J16​
​
​
CAN1 sender​
​
​
PS_CAN1_RX​
​
​
PS_MIO33​
​
​
L16​
​
​
CAN1 receiver​
​
​
PS_CAN2_TX​
​
​
PS_MIO39​
​
​
H19​
​
​
CAN2 sender​
​
​
PS_CAN2_RX​
​
​
PS_MIO38​
​
​
H18​
​
​
CAN2 receiver​
​

​
​
2.13
485 communication interface​
The AXU4EV-P expansion board has two 485 communication interfaces, and the 485 communication port is connected to the IO interface of the PL end BANK43 and 45. The 485 transceiver chip uses MAX3485 chip from MAXIM company to provide users with 485 communication services.​
Figure 3-13-1 is a schematic diagram of the connection of the PL terminal 485 transceiver chip
Figure 3-13-1 connection diagram of PL terminal 485 communication​
​
RS485 communication pin allocation is as follows:​
​
​
Signal name​
​
​
Pin name​
​
​
Pin number​
​
​
Remarks​
​
​
PL_485_TXD1​
​
​
B43_L1_P​
​
​
AG10​
​
​
First channel 485 transmitter​
​
​
PL_485_RXD1​
​
​
B43_L1_N​
​
​
AH10​
​
​
First channel 485 receiving end​
​
​
PL_485_DE1​
​
​
B45_L10_N​
​
​
A10​
​
​
First Route 485 Send Enable​
​
​
PL_485_TXD2​
​
​
B43_L3_N​
​
​
AH11​
​
​
Second channel 485 transmitter​
​
​
PL_485_RXD2​
​
​
B43_L3_P​
​
​
AH12​
​
​
The second channel 485 receiving end​
​
​
PL_485_DE2​
​
​
B45_L10_P​
​
​
B11​
​
​
Second Route 485 Send Enable​
​

​
​
2.14
MIPI interface​
The expansion board includes a MIPI camera interface that can be used to connect our MIPI OV5640 camera module (AN5641). The MIPI interface has a 15PIN FPC connector for 2 LANE data and 1 pair of clocks, connected to the differential IO pin of BANK65, with a level standard of 1.2V ( J43's jump cap needs to be connected to PIN2 and PIN3 pins ); other control signals are connected to BANK43's IO, with a level standard of 3.3V.

MIPI interface pin assignment​
​
​
Signal name​
​
​
ZYNQ pin name​
​
​
ZYNQ pin number​
​
​
Remarks​
​
​
MIPI_CLK_P​
​
​
B65_L1_P​
​
​
W8​
​
​
MIPI input clock is positive​
​
​
MIPI_CLK_N​
​
​
B65_L1_N​
​
​
Y8​
​
​
MIPI input clock negative​
​
​
MIPI _ LAN0 _ P​
​
​
B65_L2_P​
​
​
U9​
​
​
MIPI input data LANE0 positive​
​
​
MIPI_LAN0_N​
​
​
B65_L2_N​
​
​
V9​
​
​
MIPI input data LANE0 negative​
​
​
MIPI _ LAN1 _ P​
​
​
B65_L3_P​
​
​
U8​
​
​
MIPI input data LANE1 positive​
​
​
MIPI_LAN1_N​
​
​
B65_L3_N​
​
​
V8​
​
​
MIPI input data LANE1 negative​
​
​
CAM_GPIO​
​
​
B43_L4_P​
​
​
AE10​
​
​
GPIO control of the camera​
​
​
CAM_CLK​
​
​
B43_L4_N​
​
​
AF10​
​
​
Clock input of the camera​
​
​
CAM_SCL​
​
​
B43_L11_P​
​
​
Y9​
​
​
Camera's I2C clock​
​
​
CAM_SDA​
​
​
B43_L11_N​
​
​
AA8​
​
​
Camera I2C data​
​

​
​
2.15
FMC connector​
The AXU4EV-P expansion board comes with a standard FMC LPC expansion port, which can be connected to various FMC modules (HDMI input/output module, binocular camera module, high-speed AD module, etc.) from XILINX or our Black Gold. The FMC expansion port contains 36 pairs of differential IO signals.​
The 36 pairs of differential signals of the FMC expansion port are connected to the IO of the BANK65,66 of the ZYNQ Ultrascale + chip, with a level standard of 1.8V. The differential signals support LVDS data communication. The schematic diagram of the ZYNQ Ultrascale + and FMC connectors is shown in Figure 3-15-1.
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
​
FMC_LA30_P​
​
​
B66_L13_P​
​
​
D7​
​
​
FMC reference 30th channel data P​
​
​
FMC_LA30_N​
​
​
B66_L13_N​
​
​
D6​
​
​
FMC reference 30th data N​
​
​
FMC_LA31_P​
​
​
B66_L9_P​
​
​
B3​
​
​
FMC reference 31st data P​
​
​
FMC_LA31_N​
​
​
B66_L9_N​
​
​
A3​
​
​
FMC reference 31st data N​
​
​
FMC_LA32_P​
​
​
B65_L24_P​
​
​
H9​
​
​
FMC reference 32nd data P​
​
​
FMC_LA32_N​
​
​
B65_L24_N​
​
​
H8​
​
​
FMC reference 32nd data N​
​
​
FMC_LA33_P​
​
​
B66_L8_P​
​
​
A2​
​
​
FMC reference 33rd data P​
​
​
FMC_LA33_N​
​
​
B66_L8_N​
​
​
A1​
​
​
FMC reference 33rd data N​
​
​
FMC_PRSNT​
​
​
B45_L12_N​
​
​
C12​
​
​
FMC module presence signal​
​
​
PWRGD​
​
​
B44_L2_N​
​
​
AH14​
​
​
FMC Power Goods Signal​
​

​
2.16
JTAG debugging port​
A JTAG interface is reserved on the AXU4EV-P expansion board for downloading ZYNQ UltraScale + programs or solidifying programs to FLASH. In order to prevent damage to the ZYNQ UltraScale + chip caused by live plugging and unplugging, we added a protective diode to the JTAG signal to ensure that the voltage of the signal is within the range accepted by the FPGA, avoiding damage to the ZYNQ UltraScale + chip.
2.17
RTC real-time clock​
The ZU4EV chip has an internal RTC real-time clock function, which includes year, month, day, hour, minute, second, and week timing functions. An external passive clock of 32.768KHz needs to be connected to provide an accurate clock source to the internal clock circuit, so that the RTC can accurately provide clock information. At the same time, in order to ensure that the real-time clock can run normally after the product is powered down, an additional battery is generally needed to power the clock chip. The BT1 on the development board is a 1.5V button battery ( model LR1130, voltage is 1.5V ). When the system drops the battery, the button battery can also power the RTC system and provide continuous time information. Figure 3-12-1 is the schematic diagram of the RTC real-time clock
2.18
EEPROM and temperature sensors​
The AXU4EV-P development board is equipped with an EEPROM, model 24LC04, with a capacity of 4Kbit (2 * 256 * 8bit), which is connected to the PS end for communication through the IIC bus. In addition, the board also has a high-precision, low-power, digital temperature sensor chip, model LM75 from ON Semiconductor, with a temperature accuracy of 0.5 degrees. The EEPROM and temperature sensor are mounted on the Bank500 MIO of ZYNQ UltraScale + through the I2C bus. Figure 3-18-1 is the schematic diagram of the EEPROM and temperature sensor​
​


Figure 3-18-1 Schematic of EEPROM and sensor​
​
EEPROM communication pin allocation is as follows:​
​
​
Signal name​
​
​
Pin name​
​
​
Pin number​
​
​
Remarks​
​
​
PS_IIC1_SCL​
​
​
PS_MIO24​
​
​
AB19​
​
​
I2C clock signal​
​
​
PS_IIC1_SDA​
​
​
PS_MIO25​
​
​
AB21​
​
​
I2C data signal​
​

​
​
2.19
LED lights​
The AXU4EV-P expansion board has 3 Light Emitting Diode LEDs, including 1 power indicator, 1 PS control indicator, and 1 PL control indicator. Users can control the on and off through the program. When the IO voltage connected to the user LED is low, the user LED will turn off. When the IO voltage connected to the user LED is high, the user LED will light up. The hardware connection diagram of the user LED is shown in Figure 3-19-1.​
​


Figure 3-19-1 user LED lamp hardware connection diagram​
​
1.
Pin allocation for user LED lights​
​
​
Signal name​
​
​
Pin name​
​
​
Pin number​
​
​
Remarks​
​
​
PS_LED1​
​
​
PS_MIO40​
​
​
K18​
​
​
User PS LED lamp​
​
​
PL_LED1​
​
​
B44_L1_P​
​
​
AE15​
​
​
User PL LED lamp​
​

​
​
2.20
Button​
The AXU4EV-P expansion board has one reset button RESET and two user buttons. The reset signal is connected to the reset chip input of the core board, and the user can use this reset button to reset the ZYNQ system. One user button is connected to the MIO of PS, and the other is connected to the IO of PL. Both the reset button and the user button are active at a low level. The connection diagram of the user button is shown in Figure 3-20-1.
Figure 3-20-1 schematic diagram of the reset button connection​
​
ZYNQ pin assignment for buttons​
​
​
Signal name​
​
​
Pin name​
​
​
Pin number​
​
​
Remarks​
​
​
PS_KEY1​
​
​
PS_MIO26​
​
​
L15​
​
​
PS key 1 input​
​
​
PL_KEY1​
​
​
B44_L1_N​
​
​
AE14​
​
​
PL key 1 input​
​

​
​
2.21
DIP switch configuration​
There is a 4-bit DIP switch SW1 on the development board to configure the startup mode of the ZYNQ system. The AXU4EV-P system development platform supports 4 startup modes. These 4 startup modes are JTAG debugging mode, QSPI FLASH, EMMC and SD2.0 card startup mode. After the ZU4EV chip is powered on, it will detect (PS_MODE0~ 3) levels to determine which startup mode. Users can choose different startup modes through the DIP switch SW1 on the expansion board. The SW1 startup mode configuration is shown in the table 3-17-1 below.​
​
​
SW1​
​
​
Dial position (1, 2, 3, 4)​
​
​
MODE[3:0]​
​
​
Startup mode​
​
​
​
​
​
​
ON，ON，ON，ON​
​
​
0000​
​
​
PS JTAG​
​
​
ON，ON，OFF ,ON​
​
​
0010​
​
​
QSPI FLASH​
​
​
ON，OFF，ON，OFF​
​
​
0101​
​
​
SD card​
​
​
ON，OFF， OFF， ON​
​
​
0110​
​
​
EMMC​
​

​
Table 3-21-1 SW1 Startup Mode Configuration​
​
2.22
Power supply​
The power input voltage of AXU4EV-P development board is DC12V. On the baseplate, it is converted to + 5V, + 3.3V, + 1.8V through 1 DC/DC power chip TPS54620 and 2 DC/DC power chips MP1482. In addition, the baseplate generates + 1.2V through LDO to power the core board BANK65 (the power supply of BANK65 is selected through the jumper cap. When debugging the MIPI camera, 1.2V power supply is selected, and when using the FMC connector, 1.8V power supply is used). The power supply of BANK66 is + 1.8V. The power supply design diagram on the board is shown in the following figure 3-18-1:
Figure 3-22-1 Power interface part in schematic​
​
The functions of each power distribution are shown in the following table:​
​
​
Power supply​
​
​
Function​
​
​
+5.0V​
​
​
USB power supply​
​
​
+1.8V​
​
​
Ethernet, USB 2.0, core board BANK66​
​
​
+3.3V​
​
​
Ethernet, USB 2.0, SD, DP, CAN, RS485​
​
​
+1.2V​
​
​
Core board BANK65​
​

​
​
2.23
Fan​
Because ZU4EV generates a lot of heat when it works normally, we have added a heat sink and fan to the chip on the board to prevent overheating. The control of the fan is controlled by the ZYNQ chip. The control pin is connected to the IO of BANK44 (AG14). If the IO level output is high, the MOSFET tube is turned on and the fan works. If the IO level output is low, the fan stops. The fan design diagram on the board is shown in the following figure 3-23-1:
Figure 3-23-1 Fan design in the schematic diagram of the development board​
​
The fan has been fixed to the development board with bolts before leaving the factory. The power supply of the fan is connected to the socket of J42. The red one is the positive pole and the black one is the negative pole.​
​
2.24
Structural dimension diagram​
​



​
​
​
6.
The timing constraint wizard analyzes the clock in the design. Here, the "sys_clk_p" frequency is set to 200Mhz, and then click "Skip to Finish" to end the timing constraint wizard.​
​
​
​
7.
Click "OK" in the pop-up window.​
​
​
​
​
8.
Click "Finish"
​
​
8.
The eye diagram is configured by default. Note: There may be differences in measuring the eye diagram when using different software versions.​
​
​
4.
Experimental summary​
IBERT provides powerful debugging functions. This experiment only demonstrates some of the functions. For more detailed usage, please refer to the xilinx document pg173.​
​
​
​
​
​
​
​


​












