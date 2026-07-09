# Implementation Plan for SDR Project on ALINX AXU4EVB-P (FMCOMMS4 / AD9364)

## Project Overview
Based on hardware limitations identified during the initial ADRV9009 setup, the ALINX AXU4EVB-P's FMC port is an LPC (Low Pin Count) connector that lacks the Gigabit Transceivers (GTH) required for JESD204B. The project architecture is being pivoted to use the **AD9364 (via FMCOMMS4 or similar LVDS-based EVB)** which communicates over standard FMC LPC pins using LVDS/CMOS. 

This plan outlines the steps to build the Vivado hardware platform, PetaLinux OS, and Vitis application for the AD9361/AD9364 transceiver on the AXU4EVB-P board.

> [!WARNING]
> ## User Review Required
> Please review this major architectural pivot. We are abandoning the ADRV9009 (JESD204B) design and migrating to the FMCOMMS2/3/4 reference design which uses the `axi_ad9361` IP block. This will fully resolve the physical FMC connector mismatch.

> [!IMPORTANT]
> ## Open Questions
> 1. Do you have the exact schematic or an XDC pinout reference for the FMC LPC connector on the ALINX AXU4EVB-P? We will need to map the FMCOMMS4 pins (LA00_P/N to LA33_P/N) to the exact FPGA pins on BANK 65/66. 

## Phase 1: Hardware Setup (Vivado)
**Reference**: vivado/MEGA_VIVADO_INSTRUCTIONS.md (for AXU4EVB-P)

### Steps:
1. **Vivado Project Initialization**
   - Create a fresh project named "fmcomms_sdr_axu4ev" to avoid conflicts with the previous ADRV9009 build.
   - Target Part: `xczu4ev-sfvc784-1-i`.

2. **Block Design Construction**
   - **Zynq MPSoC**: Instantiate and configure Zynq UltraScale+ with AXU4EVB-P presets (DDR4, Clocks, MIOs). Set PL clocks to 100MHz (for AXI-Lite) and 200MHz (for AD9361 delay controllers).
   - **ADI IP Cores**: 
     - Add `axi_ad9361` (handles LVDS PHY and digital interface to AD9364).
     - Add `axi_dmac` (2 instances: one for RX data to memory, one for TX data from memory).
     - Add `util_ad9361_divclk` and necessary AXI Interconnects.
   
3. **Pin Constraints (XDC) - CRITICAL**
   - Write a custom `axu4ev_fmcomms.xdc` file.
   - Map the AD9361 LVDS data lanes (`rx_d_p/n`, `tx_d_p/n`), clocks (`rx_clk_in`, `tx_clk_out`), and SPI control signals to the specific FPGA pins on BANK 65 and 66 connected to the FMC LPC port.
   - Ensure `IOSTANDARD LVDS` or `LVCMOS18` is set appropriately based on the AD9361 configuration.

4. **Generate Bitstream and Export Hardware**
   - Validate design, Generate Output Products, Generate Bitstream.
   - Export XSA for software development.

## Phase 2: Operating System Setup (PetaLinux)
1. **PetaLinux Project Creation**: Create a ZynqMP PetaLinux project and import the new XSA.
2. **Device Tree**: Integrate the AD9361 Linux IIO driver into the device tree (`system-user.dtsi`).
3. **Kernel Config**: Enable AD9361 IIO driver and AXI DMAC drivers in the kernel.
4. **Build**: Run `petalinux-build` and generate `BOOT.BIN`.

## Phase 3: Software Development (Vitis)
1. If running Bare-metal/No-OS:
   - Clone the Analog Devices `no-OS` repository.
   - Compile the AD9361 initialization and calibration routines using Vitis targeting the exported XSA.
2. If running Linux:
   - Use `libiio` and `iio-oscilloscope` running on the PetaLinux rootfs to capture and transmit RF samples.

## Verification Plan
### Automated & Build Tests
- Verify Vivado Block Design validation passes without DRC errors.
- Verify Bitstream generation completes with correct pin assignments on BANK 65/66.

### Hardware Verification
- Boot the board with the FMCOMMS4 plugged into the FMC LPC.
- Run `iio_info` in Linux to verify the AD9361 SPI interface is detected and the driver loads successfully.