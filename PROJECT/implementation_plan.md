# Implementation Plan for SDR Project on ALINX AXU4EVB-P

## Project Overview
Based on the meeting notes dated 07.07.2026, the project aims to implement a Software Defined Radio (SDR) system using the ADRV9008 transceiver on the ALINX AXU4EVB-P development board. The goal is to establish a hardware infrastructure that digitizes RF signals and outputs a spectrum analysis result. This plan outlines the steps required to complete the project, leveraging the provided instruction files for Vivado, Vitis, and PetaLinux setup, and the reference design in Related-Docs\hdl-main\projects\adrv9009.

## Key Considerations
- The target board is ALINX AXU4EVB-P (XCZU4EV-1SFVC784I).
- The ADRV9008 (similar to ADRV9009) will be connected via the FMC (FPGA Mezzanine Card) interface.
- The FMC interface provides more than just SPI; it includes high-speed serial links suitable for JESD204B (required for ADCV9008/9 high-speed data).
- Linux IIO drivers are available for the ADRV9009 (and compatible with ADRV9008) in Related-Docs\analogdevices_linux_blob_main_Drivers_iio_adc.
- The reference design for ADRV9009 on various Xilinx boards (see Related-Docs\hdl-main\projects\adrv9009) can be adapted for the AXU4EVB-P.

## Phase 1: Hardware Setup (Vivado)
**Reference**: vivado/MEGA_VIVADO_INSTRUCTIONS.md (for AXU4EVB-P)

### Steps:
1. **Vivado Project Establishment**
   - Create a project named appropriately (e.g., "adrv9008_sdr_axu4evb").
   - Use Block Design to create a graphical design.
   - Search for "zynq" and add the Zynq UltraScale + MPSoC IP.
   - Configure the Zynq core in the Block Diagram:
     - **I/O Configuration**: Set voltages for BANK0-BANK2 as LVCMOS18 and BANK3 as LVCMOS33. Configure QSPI (Single mode, x4 Data, Feedback Clk), eMMC (SD 0), SD card (SD 1), CAN 0/1, I2C 1, UART 0, GPIO1 MIO, and TTC0-3.
     - **High Speed Configuration**: Configure PS side Ethernet (GEM 3: MIO 64-75, MDIO 3: MIO 76-77), USB 0 (MIO 52-63, GT Lane1 USB Reset MIO 31), PCIe (set to ROOT mode via Switch To Advanced Mode), Display Port (MIO 27-30, Dual Higher Lane Selection).
     - **Clock Configuration**: Set reference clock PSS_REF_CLOCK for ARM to 33.333MHz; PCIe to Ref Clk0 (100MHz); Display Port to Ref Clk2 (27MHz); USB0 to Ref Clk1 (26MHz). In Output Clocks, set to IOPLL. Full Power section: set DP_VIDEO to VPLL, DP_AUDIO and DP_STC to RPLL.
     - **DDR Configuration**: Load DDR Presets "DDR4_MICRON_MT40A256M16GE_083E". Modify parameters as needed, then connect the clock.
   - Generate HDL Wrapper and proceed with Generate Output Products, then Generate bitstream.
   - Export hardware information (XSA file) via File > Export > Export Hardware... (Select Fixed).

2. **Adapt the ADRV9009 Reference Design for AXU4EVB-P FMC Interface**
   - Examine the reference design in Related-Docs\hdl-main\projects\adrv9009\ (specifically, look for a design that matches our board or similar, e.g., zcu102, zc706, etc.) and adapt it to the AXU4EVB-P FMC pinout.
   - The FMC HPC expansion port on the AXU4EVB-P connects to IO of BANK65 and BANK66 of the Zynq Ultrascale+ chip. Refer to the FMC interface section in vivado/MEGA_VIVADO_INSTRUCTIONS.md for pin assignments.
   - In the Block Design, ensure the FMC HPC expansion port is properly connected to the IO of BANK65 and BANK66.
   - The ADRV9008/9 uses JESD204B interface for high-speed data. We must implement the JESD204B transmitter/receiver in the FPGA fabric (or use available IP) to handle the high-speed serial data between the FPGA and the ADRV9008/9.
   - The SPI interface (for configuration) can be handled via the FMC's general-purpose I/O or via the PS (if connected to MIO). We will use the PS for SPI configuration if possible, or the FMC's GPIO signals.
   - Configure the FMC connector pin assignment as per the instructions in vivado/MEGA_VIVADO_INSTRUCTIONS.md (signals like FMC_CLK0_P/N, FMC_CLK1_P/N, FMC_LAxx_P/N, etc.) and the specific requirements of the ADRV9008/9 FMC connection (consult the ADRV9008/9 datasheet and the reference design).

3. **Generate Bitstream and Export Hardware**
   - After completing the Block Design, generate the bitstream.
   - Export the hardware (XSA file) for use in Vitis and PetaLinux.

## Phase 2: Operating System Setup (PetaLinux)
**Reference**: Linux/MEGA_LINUX_INSTRUCTIONS_VSCODE.md (and Linux/MEGA_LINUX_INSTRUCTIONS.md)

### Steps:
1. **PetaLinux Project Creation**
   - Follow the directory structure convention: `mkdir -p ~/peta_prj/<project_name>/hardware`.
   - Copy the XSA file from the Vivado project to the hardware folder.
   - Source the PetaLinux environment: `source /opt/pkg/petalinux/settings.sh`.
   - Create the PetaLinux project: `petalinux-create -t project -n <project_name> --template zynqMP`.
   - Enter the project directory.

2. **Hardware Configuration**
   - Run `petalinux-config --get-w-description ../hardware/` from inside the petalinux project directory.
   - In the menuconfig:
     - Under **Linux Components Selection**, configure kernel/u-boot sources as needed.
     - Under **Auto Config Settings**, consider leaving kernel autoconfig and u-boot autoconfig unselected if compile errors occur.
     - Under **Subsystem AUTO Hardware Settings**, configure boot device, flash, Ethernet, SD.
     - Under **DTG Settings**, configure device tree generation.
     - Under **Image Packaging Configuration**, choose root filesystem type (e.g., EXT4 for persistent storage) and boot format.
     - Under **Firmware Version Configuration**, set hostname and product name.
     - Under **Yocto Settings**, configure build system.
   - Save configuration.

3. **Device Tree Customization for ADRV9008/9 via FMC**
   - Navigate to `<project>/project-spec/meta-user/recipes-bsp/device-tree/files/`.
   - Edit `system-user.dtsi-user.dtsi` (primary custom device tree) to include necessary peripherals for the FMC connection and any custom IP for JESD204B data transfer.
   - Since the ADRV9008/9 is connected via FMC, we need to define the FMC signals in the device tree (if using the FPGA to manage the JESD204B link) or configure the PS to handle the SPI for control.
   - We will likely use the FPGA (PL) to handle the JESD204B link, so we may need to define an appropriate device tree node for the custom IP (if we create one) or use the generic IIO driver if we are using the ADI Linux driver that expects the data via a different interface (like through the AXI ADC IP). However, note that the ADRV9008/9 is a transceiver (includes DAC and ADC) and the IIO driver we saw is for the ADC part. We may need to look for a transceiver driver or use the IIO driver for the ADC and a separate driver for the DAC (or use the IIO driver for both if available).
   - Given the complexity, we might use the reference design's approach: the reference design likely uses the FPGA to deserialize the JESD204B stream and then presents the data via AXI-Stream to the PS for processing (or via DMA to memory). We will follow that.
   - Refer to the examples in the instructions for basic device tree, Vitis Acceleration Platform (with zocl), and QSPI+eMMC Boot.
   - Ensure the device tree captures the hardware interfaces correctly, including any custom IP for JESD204B.

4. **Building the PetaLinux Project**
   - Run `petalinux-build` for the full build.
   - Optionally build the SDK: `petalinux-build --sdk` (requires online compilation enabled).
   - Build outputs are in `<project>/images/linux/`.

## Phase 3: Software Development (Vitis)
**Reference**: Vitis/MEGA_VITIS_INSTRUCTIONS_VSCODE.md (and Vitis/MEGA_VITIS_INSTRUCTIONS.md)

### Steps:
1. **Vitis Project Creation**
   - Create a new folder and copy the XSA file exported from Vivado.
   - Launch Vitis (double-click or via Tools > Launch Vitis in Vivado).
   - Select the newly created folder as workspace and launch.
   - Click "Create Application Project".
   - Skip the introduction page and click Next.
   - Select "Create a new platform from hardware (XSA)" and browse to the XSA file.
   - Check "Generate boot components" to automatically generate the FSBL project.
   - Fill in the application project name (default processor: psu_cortexa53_0).
   - In the Domain interface, keep default (standalone/bare-metal) or choose Linux if an OS is required.
   - Select a template (e.g., "Hello World" or "Empty Application") and click Finish.
   - Two projects are generated: hardware platform project (platform project) and the application project (APP project).

2. **Platform Project & BSP Configuration**
   - Double-click `platform.spr` to see the Platform configuration.
   - Click on BSP to see peripheral drivers provided by the project.
   - To modify BSP settings: Right-click BSP → Board Support Package Settings.
   - Key BSP files: `xparameters.h` (base addresses, device IDs, interrupt numbers) and `libsrc/` (peripheral function definitions).
   - If using Linux OS, configure accordingly (e.g., enable necessary packages like Qt, OpenCV, etc., as per instructions).
   - Additionally, we need to integrate the ADRV9008/9 IIO driver (from Related-Docs\analogdevices_linux_blob_main_Drivers_iio_adc) into the PetaLinux rootfs and device tree.
   - We will need to add the driver to the kernel and create an appropriate device tree node for the IIO device (if the data is being provided via an AXI IP that the IIO driver can talk to). However, if we are using the FPGA to deserialize the JESD204B and then send the data via AXI-Stream to a custom IP that writes to memory or to an AXI-Stream to AXI-VDMA for storage, then we may not need the IIO driver for the data path. The IIO driver is more for direct register access and configuration via SPI/I2C and for accessing samples via an AXI interface if the FPGA provides an AXI slave for the samples.

   - Given the reference design, it is likely that the FPGA handles the JESD204B and then sends the samples to the PS via an AXI-Stream interface (to memory or to a processing IP). In that case, we may not need the IIO driver for the high-speed data. We will need the SPI/I2C interface for configuration of the ADRV9008/9.

   - We will use the PS's SPI controller (if connected to the FMC's SPI signals) or the FMC's I/O signals configured as SPI to configure the ADRV9008/9.

3. **Building and Compiling Projects**
   - In Vitis IDE, select the APP project and right-click → Build Project, or click the "Hammer" button.
   - Output: ELF file generated in `<app>/Debug/<app>.elf`.
   - For faster iteration, build only the APP project; build the system project only when a new BOOT.bin is needed for boot.

4. **Running and Debugging and Debugging on Hardware**
   - Connect JTAG cable and UART USB cable to PC.
   - Set boot mode to JTAG (all DIP switches ON) before powering on.
   - Power on the board.
   - Select the APP project → right-click → Run As → Launch on Hardware (Single Application Debug).
   - Observe output in serial terminal (e.g., PuTTY at 115200 baud).
   - For reliable debugging, use Run As → Run Configuration... (ensure Reset entire system is selected; if PL design exists, also select Program FPGA).
   - To debug: Debug As → Debug on Hardware (set breakpoints, step-by-step execution, variable inspection, register viewing).

## Phase 4: Integration and Testing
### Steps:
1. Integrate the hardware design (from Vivado) with the software application (from Vitis) and the operating system (from PetaLinux). 
   . 2. Ensure the data path between the ADRV9008/9 (via FMC) and the processing system is correctly configured in the Block Design (high-speed serial interfaces via JESD204B in the FPGA, then possibly AXI-Stream to memory or processing IP). 
   . 3. Develop the software application to handle the RF signal digitization (possibly in the FPGA or in the PS), processing (e.g., FFT for spectrum analysis), and output the spectrum result (e.g., via UART, display, or storage). 
   . 4. Test the end-to-end system: 
       - Verify hardware initialization via boot logs. 
       - Confirm data capture from ADRV9008/9. 
       - Validate spectrum output (e.g., display on HDMI/DP, or send via UART/Ethernet to a host PC for visualization). 
   . 5. Iterate on hardware and software as needed to achieve the desired functionality. 
   . 6. Document any issues and resolutions as per the troubleshooting sections in the instruction files.

## Timeline and Deliverables (Based on Meeting Notes)
. **Current Status**: Initiate the project setup as outlined above.
. **Three-Week Marker (Estimated: 28 July 2026)**: 
   - Demonstrate the hardware infrastructure setup (Vivado project with ADRV9008/9 FMC interface and JESD204B link).
   - Show a working PetaLinux boot on the board.
   - Present a basic software application that can process the digitized RF signals and produce a spectrum output (even if preliminary).
   - Present these advancements to the team lead.

. **Future Vision**: After the initial setup, perform benchmarking against existing systems (e.g., the older ADRV9361-based spectrum analyzer) to showcase performance improvements.

## Notes
- All steps should follow the detailed instructions provided in the respective files.
- Adjust configurations (pin assignments, clock settings, etc.) based on the specific requirements of the ADRV9008/9 FMC module and JESD204B interface.
- Utilize the troubleshooting sections in the instruction files to resolve common issues.
- Ensure proper version compatibility: Vivado 2020.1, PetaLinux 2020.1, Vitis 2020.1 as specified in the instructions.
- The reference design in Related-Docs\hdl-main\projects\adrv9009 provides a good starting point for the FPGA portion (JESD204B linker and AXI-Stream data path).
- The Linux IIO driver in Related-Docs\analogdevices_linux_blob_main_Drivers_iio_adc (adrv9009.c, .h, .conv.c) can be used for configuration and possibly for data access if we expose an AXI slave for the samples, but we may need to adapt it or use a different approach for the high-speed data.

This implementation plan provides a structured approach to complete the SDR project using the ALINX AXU4EVB-P board, adhering to the provided guidelines and meeting the project objectives outlined in the meeting notes.