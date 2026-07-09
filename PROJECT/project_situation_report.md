# Project Situation Report - SDR System on ALINX AXU4EVB-P

## Overview
This report tracks the progress of the Software Defined Radio (SDR) project using the ADRV9008 transceiver on the ALINX AXU4EVB-P development board, as per the meeting notes dated 07.07.2026.
Goal: Digitize RF signals and output a spectrum analysis result.

## Pivot: ADRV9009 to FMCOMMS4
- Due to the ALINX AXU4EVB-P FMC LPC connector lacking GTH transceivers, the project has been pivoted.
- We are replacing the ADRV9009 (JESD204B) target with the AD9364/FMCOMMS4 (LVDS) target, which is fully compatible with the ALINX board's physical FMC connector.

## Completed Tasks
- [x] Initial Vivado project created and Zynq MPSoC configured for AXU4EVB-P.
- [x] Evaluated and verified hardware incompatibility of JESD204B with the ALINX FMC LPC connector.
- [x] Confirmed with team to pivot to FMCOMMS2/3/4 (AD9364).

## In Progress
- [ ] Create a new Vivado project (`fmcomms_sdr_axu4ev`).
- [ ] Construct the Block Design using `axi_ad9361` and `axi_dmac`.
- [ ] Identify the exact pin mapping from AD9361 FMC signals to ALINX AXU4EVB-P BANK 65/66.
- [ ] Write the `axu4ev_fmcomms.xdc` constraint file.
- [ ] Generate Bitstream and Export XSA.
- [ ] Developing Vitis application for RF signal processing and spectrum analysis.

## Upcoming Tasks
- Complete FPGA design: Add necessary IP (e.g., AXI-Stream, JESD204B, custom logic) to handle data from ADRV9008/9 via FMC.
- Export updated XSA after FPGA design changes.
- Configure PetaLinux: device tree to include FMC interfaces and any custom IP; build PetaLinux project.
- Set up Vitis software: create platform from XSA, add necessary drivers (e.g., ADRV9009 IIO driver from Related-Docs\analogdevices_linux_blob_main_Drivers_iio_adc), develop application to process data and output spectrum.
- Integrate and test end-to-end system: verify boot, data capture, and spectrum output.
- Document any issues and resolutions as per the troubleshooting sections in the instruction files.

## Issues / Risks
- FMC connector signal integrity for JESD204B high-speed links (ensure proper pin assignment per AXU4EVB-P FMC specification).
- Correct device tree configuration for ADRV9008/9 FMC interface (whether using FPGA for JESD204B or direct PS access).
- Linux kernel configuration for required drivers (IIO, etc.) and device tree nodes.
- Timing closure in Vivado design (check WNS after implementation).
- Ensuring the ADRV9008/9 is properly configured via SPI (check register access).

## Notes
- The generated XSA file (`SDR_Real/sdr_wrapper.xsa`) is the hardware platform to be used in PetaLinux and Vitis.
- The reference design in Related-Docs\hdl-main\projects\adrv9009 provides a good starting point for the FPGA portion (JESD204B linker and AXI-Stream data path), but must be adapted to the AXU4EVB-P FMC pinout.
- The Linux IIO driver in Related-Docs\analogdevices\devices_linux_blob_main_Drivers_iio_adc (adrv9009.c, .h, .conv.c) can be used for configuration and possibly for data access if an AXI slave for samples is exposed, but the FPGA design may need to provide such an interface or use an alternative data path (e.g., AXI-Stream to memory or processing IP).
- Utilize the troubleshooting sections in the instruction files for common issues.
- Ensure proper version compatibility: Vivado 2020.1, PetaLinux 2020.1, Vitis 2020.1 as specified in the instructions.

## Next Steps
1. Modify the FPGA block design in Vivado to include the ADRV9008/9 FMC interface (using the FMC HPC pins on BANK65/BANK66) and the JESD204.com (or custom logic) to deserialize the high-speed serial data.
2. Export the updated XSA.
3. Create PetaLinux project with the XSA, configure device tree for FMC and any custom IP, build PetaLinux.
4. Create Vitis platform from the XSA, add necessary drivers (e.g., ADRV9009 IIO driver from Related-Docs\analogdevices_linux_blob_main_Drivers_iio_adc), develop application to process the digitized RF data and compute spectrum (e.g., via FFT).
5. Test the system on hardware.

Please proceed with the FPGA design modifications and let me know if you need further assistance with any specific step.