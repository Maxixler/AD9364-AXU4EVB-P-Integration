# MEGA VITIS INSTRUCTIONS — ALINX AXU4EVB-P Development Board

> **Purpose**: This document is the **single source of truth** for all technical details about Vitis software development on the ALINX AXU4EVB-P (also referenced as AXU4EV-P) FPGA/SoC development board. It is designed to be consumed by an AI assistant (Claude) to provide accurate, board-specific guidance for Vitis bare-metal and application development during an SDR project.
>
> **Toolchain**: Vivado 2020.1 + Vitis 2020.1
>
> **Target Chips**: XCZU4EV-SFVC784-1-I (AXU4EV-P) / XCZU5EV-2SFVC784I (AXU5EV-P)

---

## TABLE OF CONTENTS

1. [Board & Chip Quick Reference](#1-board--chip-quick-reference)
2. [Software Environment Requirements](#2-software-environment-requirements)
3. [Vivado-to-Vitis Handoff — The XSA File](#3-vivado-to-vitis-handoff--the-xsa-file)
4. [Vitis Application Project — Step-by-Step Creation](#4-vitis-application-project--step-by-step-creation)
5. [Platform Project & BSP Configuration](#5-platform-project--bsp-configuration)
6. [Building and Compiling Projects](#6-building-and-compiling-projects)
7. [Running and Debugging on Hardware](#7-running-and-debugging-on-hardware)
8. [ZYNQ MPSoC Boot Process — Theory](#8-zynq-mpsoc-boot-process--theory)
9. [FSBL (First Stage Boot Loader)](#9-fsbl-first-stage-boot-loader)
10. [Boot Image (BOOT.bin) Generation](#10-boot-image-bootbin-generation)
11. [SD Card Boot](#11-sd-card-boot)
12. [QSPI Flash Programming](#12-qspi-flash-programming)
13. [JTAG Programming Flows (XSCT)](#13-jtag-programming-flows-xsct)
14. [Deploy Automation Scripts](#14-deploy-automation-scripts)
15. [Vitis Workspace Creation via XSCT (Command-Line)](#15-vitis-workspace-creation-via-xsct-command-line)
16. [Syncing Hardware from Vivado](#16-syncing-hardware-from-vivado)
17. [LwIP Ethernet (PS-Side) Configuration](#17-lwip-ethernet-ps-side-configuration)
18. [PL-Side Ethernet Configuration](#18-pl-side-ethernet-configuration)
19. [AXI DMA Configuration and Usage](#19-axi-dma-configuration-and-usage)
20. [Network Remote Update of QSPI](#20-network-remote-update-of-qspi)
21. [MIPI Camera (OV5640) Integration](#21-mipi-camera-ov5640-integration)
22. [Display Output (HDMI / DisplayPort)](#22-display-output-hdmi--displayport)
23. [CAN Bus Loopback Testing](#23-can-bus-loopback-testing)
24. [RS485 Communication](#24-rs485-communication)
25. [RTC and Peripheral Driver Examples](#25-rtc-and-peripheral-driver-examples)
26. [EMIO GPIO (PL LED / PL Key via PS)](#26-emio-gpio-pl-led--pl-key-via-ps)
27. [Custom AXI IP Integration (PWM Example)](#27-custom-axi-ip-integration-pwm-example)
28. [BRAM Shared Memory (PS ↔ PL)](#28-bram-shared-memory-ps--pl)
29. [Dual-Core (CPU0 / CPU1) Development](#29-dual-core-cpu0--cpu1-development)
30. [Preflight Debugging & Environment Checks](#30-preflight-debugging--environment-checks)
31. [Batch Build Vitis Projects (TCL Scripts)](#31-batch-build-vitis-projects-tcl-scripts)
32. [BSP Management & Common Issues](#32-bsp-management--common-issues)
33. [AXI4-Lite Register Map Reference (ISP Example)](#33-axi4-lite-register-map-reference-isp-example)
34. [UDP Frame Streaming (Ethernet Application)](#34-udp-frame-streaming-ethernet-application)
35. [Debug History & Lessons Learned](#35-debug-history--lessons-learned)
36. [Common Pitfalls and Troubleshooting](#36-common-pitfalls-and-troubleshooting)
37. [Key Xilinx Documentation References](#37-key-xilinx-documentation-references)

---

## 1. Board & Chip Quick Reference

### Supported Development Boards

| Board Model | Chip Model | Vivado Part String |
|---|---|---|
| AXU4EV-P (AXU4EVB-P) | XCZU4EV-SFVC784-1-I | `xczu4ev-sfvc784-1-i` |
| AXU5EV-P (AXU5EVB-P) | XCZU5EV-2SFVC784I | `xczu5ev-sfvc784-2-i` |

### Architecture Overview

The Zynq UltraScale+ MPSoC is divided into:

- **PS (Processing System)**: ARM-based SoC subsystem (Cortex-A53 quad-core APU + Cortex-R5F dual-core RPU). Runs bare-metal or Linux applications. Controls boot, peripherals, and DDR.
- **PL (Programmable Logic)**: FPGA fabric with LUTs, FFs, BRAM, DSP slices, and transceivers.

> **KEY CONCEPT**: The main advantage of ZYNQ is the reasonable combination of FPGA and ARM. Starting from Vitis development, FPGA engineers and software engineers collaborate — FPGA engineers build the Vivado project and provide hardware (.xsa), software engineers develop applications based on this.

### PS Resources

| Component | AXU4EV-P | AXU5EV-P |
|---|---|---|
| APU | Quad-core Cortex-A53 @ 1.5 GHz | Quad-core Cortex-A53 @ 1.5 GHz |
| RPU | Dual-core Cortex-R5F @ 600 MHz | Dual-core Cortex-R5F @ 600 MHz |
| GPU | Mali-400 MP2 @ 677 MHz | Mali-400 MP2 @ 677 MHz |
| VCU | H.264/H.265 encode/decode | H.264/H.265 encode/decode |
| PS DDR4 | 4GB (4× MT40A512M16LY-062E) | 4GB (4× MT40A512M16LY-062E) |

### PL Resources (AXU4EV-P)

| Resource | Quantity |
|---|---|
| System Logic Cells | 192K |
| CLB LUTs | 88K |
| CLB Flip-Flops | 176K |
| Block RAM (BRAM) | 4.5 Mb |
| UltraRAM | 13.5 Mb |
| DSP Slices (DSP48E2) | 728 |
| GTH Transceivers | 4 |

### Board Peripherals (Quick Reference)

| Category | Interfaces |
|---|---|
| **Networking** | 2× GbE (1 PS-side, 1 PL-side), Ethernet PHY: JL2121 (JLSemi) |
| **Video** | 1× HDMI Out (ADV7511), 1× HDMI In (ADV7611), 1× Mini DP Out, 1× MIPI Camera |
| **Storage** | 1× Micro SD, 32GB eMMC, 256Mb QSPI Flash |
| **Serial** | 2× UART (USB-to-UART), 2× CAN Bus, 2× RS485 |
| **USB** | 4× USB 3.0 (Host mode) |
| **User I/O** | 2× User buttons (1 PS, 1 PL), 2× User LEDs (1 PS, 1 PL) |
| **Debug** | 1× JTAG (10-pin), RTC with battery backup |

---

## 2. Software Environment Requirements

### Required Software

| Software | Version | Purpose |
|---|---|---|
| **Vivado** | 2020.1 | FPGA design, synthesis, implementation, bitstream generation |
| **Vitis** | 2020.1 | Software application development (replaces SDK from 2019.2+) |
| **PuTTY** | Any | Serial port terminal (115200 baud, 8N1) |

### Common Installation Paths (Windows)

```
D:\Xilinx\Vitis\2020.1\          (or C:\Xilinx\Vitis\2020.1\)
D:\Xilinx\Vitis\2020.1\bin\xsct.bat    — XSCT command-line shell
D:\Xilinx\Vitis\2020.1\bin\vitis.bat    — Vitis IDE launcher
D:\Xilinx\Vitis\2020.1\settings64.bat  — Environment setup
```

### Environment Setup

Before using command-line tools (xsct, bootgen, program_flash), source the environment:
```bat
call D:\Xilinx\Vitis\2020.1\settings64.bat
```

### Serial Port Configuration

| Parameter | Value |
|---|---|
| Baud Rate | 115200 |
| Data Bits | 8 |
| Parity | None |
| Stop Bits | 1 |
| Flow Control | None |

> **TIP**: Use PuTTY → select "Serial" → fill in COM port (check Device Manager) → set Speed to 115200 → click "Open".

---

## 3. Vivado-to-Vitis Handoff — The XSA File

### What is an XSA File?

The **XSA (Xilinx Support Archive)** file is the hardware description file exported from Vivado. It contains:
- PS configuration information (MIO allocation, clock settings, DDR parameters)
- PL hardware design information (if bitstream is included)
- Device tree fragments
- Address map for all peripherals

### Exporting Hardware from Vivado

1. In Vivado menu bar: **File → Export → Export Hardware...**
2. In the pop-up window select **Fixed** and click Next
3. **Include bitstream**: Check this if PL logic is used in the design. If only PS is used (e.g., hello world), leave unchecked
4. Set export name and path (default: Vivado project directory)
5. Click **Finish**

> **CRITICAL**: The XSA file is the bridge between Vivado (FPGA engineer's domain) and Vitis (software engineer's domain). The Vivado and Vitis software are independent — the XSA can be placed anywhere, not necessarily under the Vivado project.

### When to Re-export

Re-export the XSA whenever:
- Block Design changes are made (new IP added/removed, connections changed)
- PS configuration changes (clocks, MIO, DDR)
- PL pin constraints change
- Any change that affects `xparameters.h` definitions

---

## 4. Vitis Application Project — Step-by-Step Creation

### Overview

Vitis creates two types of projects:
- **Platform Project**: Contains the hardware platform (from XSA) and BSP (Board Support Package)
- **Application (APP) Project**: Contains the user application code

### Step-by-Step

1. **Create a new folder** and copy the `xx.xsa` file exported from Vivado

2. **Launch Vitis**:
   - Double-click the Vitis software directly, OR
   - From Vivado: **Tools → Launch Vitis**
   - Select the newly created folder as workspace and click **Launch**

3. **Create Application Project**: Click **"Create Application Project"**
   - This generates both the APP project and Platform project

4. Skip the introduction page, click **Next**

5. **Select hardware platform**: Choose **"Create a new platform from hardware (XSA)"** → click **Browse** → select the previously generated XSA → click Open

6. **Generate boot components**: The option at the bottom — if checked, the software will automatically generate the FSBL project. **Usually check this by default**.

7. **Fill in APP project name**: Click on the box to select the corresponding processor (default: `psu_cortexa53_0`)

8. **Domain configuration**:
   - Domain name: keep default or modify
   - Operating system: select **standalone** (bare-metal)
   - Architecture: keep default (64-bit for A53)

9. **Select template**: Choose **"Hello World"** (or "Empty Application" for custom projects) → click **Finish**

10. **Result**: Two projects are generated:
    - **Platform project** (hardware platform)
    - **APP project** (application)

### Project Structure After Creation

```
workspace/
├── <platform_name>/           ← Platform project
│   ├── platform.spr           ← Platform specification (double-click to configure BSP)
│   ├── zynqmp_fsbl/           ← FSBL project (if Generate boot components was checked)
│   ├── domain_psu_cortexa53_0/ ← BSP for the APP project
│   └── hw/                    ← Hardware files (.xsa, .bit, psu_init.tcl)
├── <app_name>/                ← Application project
│   └── src/                   ← Source files
│       └── helloworld.c
└── <app_name>_system/         ← System project (links platform + app)
```

---

## 5. Platform Project & BSP Configuration

### Understanding BSP (Board Support Package)

The BSP contains driver files needed for development. Under the Platform project, you can see:
- **`zynqmp_fsbl`**: BSP for the FSBL
- **`domain_psu_cortexa53_0`**: BSP for the APP project

> **NOTE**: You can add additional BSPs in the Platform. This is different from previous SDK software where there was a single BSP.

### Viewing and Configuring BSP

1. **Double-click `platform.spr`** to see the Platform configuration
2. Click on **BSP** to see peripheral drivers provided by the project:
   - **Documentation**: Links to driver documentation provided by Xilinx
   - **Import Examples**: Example projects provided by Xilinx to speed up learning
3. To modify BSP settings: **Right-click BSP → Board Support Package Settings**

### Key BSP Files

| File | Location | Purpose |
|---|---|---|
| `xparameters.h` | `bsp/psu_cortexa53_0/include/` | Base addresses, device IDs, interrupt numbers for all peripherals |
| `libsrc/` | `bsp/psu_cortexa53_0/libsrc/` | Peripheral function definitions and usage instructions |
| `psu_init.c` / `psu_init.tcl` | Platform hw/ | PS initialization (MIO, PLL, DDR, peripheral config) |

### Finding Peripheral Information

The base address, device ID, interrupt, etc. of each peripheral are defined in `xparameters.h`. For example:
```c
// Example entries in xparameters.h
#define XPAR_XUARTPS_0_DEVICE_ID     0
#define XPAR_XUARTPS_0_BASEADDR      0xFF000000
#define XPAR_XEMACPS_3_BASEADDR      0xFF0E0000
#define XPAR_AXIDMA_0_DEVICE_ID      0
```

### Updating Platform from New XSA

If you modified the Vivado design and re-exported XSA:
1. In Vitis, right-click the Platform project → **Update Hardware Specification** → select new `.xsa`
2. The BSP will auto-regenerate, updating `xparameters.h` and device tree fragments
3. Rebuild the Platform and then rebuild the application

---

## 6. Building and Compiling Projects

### Building in Vitis IDE

1. Select the APP project in the Explorer
2. Right-click → **Build Project**, or click the **"Hammer"** button in the menu bar
3. Wait for compilation to finish
4. Output: ELF file generated in `<app>/Debug/<app>.elf`

### Build Targets

| What to Build | How | Output |
|---|---|---|
| **APP project only** | Right-click APP → Build Project | `<app>.elf` only (faster) |
| **System project** | Right-click `<app>_system` → Build Project | `<app>.elf` AND `BOOT.bin` |

> **⚠ TIP**: If you only need to test code changes, build just the APP project — it's much faster. Building the system project regenerates `BOOT.bin` every time, which wastes time. Only build the system when you need a new `BOOT.bin` for SD/QSPI boot.

### Command-Line Build (XSCT)

```tcl
# Open workspace
setws /path/to/workspace

# Build system project
sysproj build -name <app_name>_system

# Build app only
app build -name <app_name>
```

### Build via Makefile (Advanced)

```bat
cd <workspace>/<app_name>/Debug
make clean all
```

The ELF output will be at `<app_name>/Debug/<app_name>.elf`.

---

## 7. Running and Debugging on Hardware

### Prerequisites

1. Connect **JTAG cable** to development board
2. Connect **UART USB cable** to PC
3. Open serial terminal (PuTTY) with 115200 baud
4. **Set boot mode to JTAG** before powering on (unplug mode switch to "ON" position)
5. Power on the development board

### Run As (Execute Program)

1. Select the APP project → right-click → **Run As → Launch on Hardware (Single Application Debug)**
2. This downloads and runs the program directly via JTAG
3. Observe output in serial terminal

### Run Configuration (Recommended)

For reliable debugging, use **Run As → Run Configuration...**:
- **Reset entire system**: Selected by default (different from previous SDK)
- **Program FPGA**: Must be selected if there is PL design in the system

### Debug As (Step-by-Step Debugging)

1. Select APP project → right-click → **Debug As → Debug on Hardware**
2. Enter Debug mode (like other C language development IDEs)
3. Features:
   - Set breakpoints
   - Step-by-step execution (F6)
   - Variable inspection
   - Register viewing
4. Switch IDE mode in upper-right corner between Debug and Design views

### Switching Between Run and Debug

You can switch IDE mode in the upper right corner of the Vitis window.

---

## 8. ZYNQ MPSoC Boot Process — Theory

The startup of ZYNQ MPSoC is **dominated by ARM** (PS side), including the loading of FPGA programs. It generally consists of three stages (see UG1085):

### Stage 1: Pre-Configuration Stage

- Controlled by the **PMU (Platform Management Unit)**
- Executes code in the **PMU ROM**
- PMU handles all reset and wake-up processes

### Stage 2: Configuration Stage (Most Important)

After **BootROM** (part of the CSU ROM code) transfers **FSBL** to **OCM (On-Chip Memory)**, the processor starts executing FSBL code.

**FSBL main functions:**
1. Initialize PS-side configuration: MIO, PLL, DDR, QSPI, SD, etc.
2. If there is a PL-side program, load the PL-side bitstream
3. Move user programs to DDR and jump to execution

### Stage 3: Post-Configuration Stage

After FSBL starts executing, the CSU ROM code enters post-configuration:
- Responsible for system intervention response
- CSU provides continuous hardware support for:
  - Verifying file correctness
  - Loading PL through PCAP
  - Storing and managing security keys
  - Decryption

### Boot Flow Diagram

```
Power On
  → PMU ROM (Pre-config)
    → BootROM (CSU)
      → FSBL (loaded to OCM)
        → PS Init (MIO, PLL, DDR)
        → Load bitstream (if present)
        → Load application to DDR
        → Jump to application
```

---

## 9. FSBL (First Stage Boot Loader)

### What is FSBL?

FSBL is the secondary bootstrap program that completes:
- MIO allocation
- Clock and PLL initialization
- DDR controller initialization
- SD, QSPI controller initialization
- Searches for bitstream to configure FPGA (based on boot mode)
- Searches for user programs to load into DDR
- Hands over execution to the application program

### Automatic FSBL Generation

If you selected **"Generate boot components"** when creating the Vitis project, the Platform already imports the FSBL project and generates the corresponding `fsbl.elf` file.

### FSBL Debug Macro

To enable debug output during FSBL startup (useful for debugging boot issues):

1. In the FSBL project, modify the debug macro definition: `FSBL_DEBUG_INFO_VAL`
2. This outputs status information during FSBL startup
3. **Trade-off**: Enables debug info but leads to longer startup time
4. Save the file and rebuild the FSBL project

### FSBL Source Files

The FSBL project contains files for many peripherals:
- `psu_init.c` / `psu_init.h` — PS initialization
- QSPI driver files
- SD driver files
- Various peripheral initialization code

> **NOTE**: The FSBL template can be modified according to your needs for custom boot behavior.

### Rebuilding FSBL

After modifying FSBL source:
1. Right-click FSBL project → **Build Project**
2. The new `fsbl.elf` will be used for subsequent BOOT.bin generation

---

## 10. Boot Image (BOOT.bin) Generation

### Method 1: Automatic (System Project Build)

1. Right-click on the **system** of the APP project → **Build Project**
2. A `Debug` folder appears with `BOOT.bin` automatically generated

### Method 2: Manual (Create Boot Image)

1. Right-click on the system of the APP project → **Create Boot Image**
2. In the pop-up window you can see:
   - **BIF file path**: Configuration file for generating BOOT files
   - **BOOT.bin file path**: The output startup file

### Boot Image Partitions

The **Boot image partitions** list must follow this order:

| Order | File | Type | Required? |
|---|---|---|---|
| 1 | `fsbl.elf` | Bootloader | **Always** |
| 2 | `pmufw.elf` | PMU Firmware | **Always** (for MPSoC) |
| 3 | `<design>.bit` | PL Bitstream | Only if PL is used |
| 4 | `<app>.elf` | Application | **Always** |

Click **Create Image** to generate `BOOT.bin`.

### BOOT.bin via bootgen (Command-Line)

Create a BIF file (`boot.bif`):
```
//arch=zynqmp
all: {
  [bootloader,destination_cpu=a53-0] fsbl.elf
  [pmufw_image] pmufw.elf
  [destination_device=pl] imgproc_top_ov5640.bit
  [destination_cpu=a53-0,exception_level=el-3,trustzone] app.elf
}
```

Generate BOOT.bin:
```bat
bootgen -arch zynqmp -image boot.bif -o BOOT.bin -w
```

### BOOT.bin via TCL Script

```tcl
# make_boot.tcl — Generate SD/QSPI boot image BOOT.bin (FSBL + PMUFW + bit + app)
set script_dir [file dirname [file normalize [info script]]]
set out_dir [file join $script_dir boot_images]
file mkdir $out_dir

set fsbl  [file join $script_dir zynq_imgproc_platform export zynq_imgproc_platform sw zynq_imgproc_platform boot fsbl.elf]
set pmufw [file join $script_dir zynq_imgproc_platform export zynq_imgproc_platform sw zynq_imgproc_platform boot pmufw.elf]
set bit   [file join $script_dir zynq_imgproc_platform hw imgproc_top_ov5640.bit]
set app   [file join $script_dir imgproc_baremetal Debug imgproc_baremetal.elf]

foreach {label path} [list FSBL $fsbl PMUFW $pmufw BIT $bit APP $app] {
    if {![file exists $path]} {
        return -code error "$label does not exist: $path"
    }
}

set bif [file join $out_dir boot.bif]
set fh [open $bif w]
fconfigure $fh -encoding ascii -translation crlf
puts $fh "//arch=zynqmp"
puts $fh "all: \{"
puts $fh "\[bootloader,destination_cpu=a53-0\] $fsbl"
puts $fh "\[pmufw_image\] $pmufw"
puts $fh "\[destination_device=pl\] $bit"
puts $fh "\[destination_cpu=a53-0,exception_level=el-3,trustzone\] $app"
puts $fh "\}"
close $fh

set bootbin [file join $out_dir BOOT.bin]
exec bootgen -arch zynqmp -image $bif -o $bootbin -w
```

---

## 11. SD Card Boot

### Procedure

1. **Format the SD card** — must be **FAT32** format only (other formats will not boot)
2. **Copy `BOOT.bin`** to the root directory of the SD card
3. **Insert SD card** into the SD card slot on the development board
4. **Set boot mode** to SD card (adjust DIP switches on the board)
5. **Open serial terminal** (PuTTY, 115200 baud)
6. **Power on**

### Expected Serial Output

```
[FSBL startup information...]          ← Red box: FSBL boot info
...
Hello World                            ← Your application output
```

The FSBL startup information section shows PS initialization details (useful for debugging boot issues).

### SD Card Boot Mode DIP Switch Settings

Refer to the board's boot mode configuration section. The AXU4EVB-P has DIP switches to select between:
- **JTAG mode** — for development/debugging
- **SD card mode** — for standalone operation
- **QSPI mode** — for production deployment
- **eMMC mode** — for large-capacity storage boot (32GB)

---

## 12. QSPI Flash Programming

### Method 1: Vitis Menu (GUI)

1. Go to Vitis menu: **Xilinx → Program Flash**
2. Configuration:
   - **Hardware Platform**: Select the latest
   - **Image File**: Select the `BOOT.bin` file to burn
   - **FSBL File**: Select `fsbl.elf`
   - **Verify after flash**: Check this to verify after burning
3. Click **Program** and wait for completion
4. Set boot mode to **QSPI**, restart to see the same output as SD boot

### Method 2: Vivado Hardware Manager

1. In Vivado Hardware Manager, select device → right-click → **Add Configuration Memory Device**
2. Filter settings:
   - Manufacturer: **Micron**
   - Type: **qspi**
   - Width: **x4-single**
   - Density: **256**
   - Select the matching model (e.g., `mt25qu256`)
3. Right-click → Select programming file
4. Select the `BOOT.bin` and `fsbl.elf` to burn

> **⚠ WARNING**: If burning is not in JTAG startup mode, the software will give a warning. Set the board to **JTAG boot mode** when burning QSPI flash.

### Method 3: Batch File (Quick Burn)

Create a `program_qspi.bat` file:

```bat
call E:\XilinxVitis\Vitis\2020.1\bin\program_flash -f BOOT.bin -offset 0 -flash_type qspi-x4-single -fsbl fsbl.elf -verify
pause
```

**Parameters:**
- `-f` — File to burn (BOOT.bin)
- `-offset 0` — Flash offset address
- `-flash_type qspi-x4-single` — Flash type
- `-fsbl` — FSBL file for flash programming
- `-verify` — Verify after programming

**Usage:**
1. Put `BOOT.bin`, `fsbl.elf`, and the `.bat` file in the same folder
2. Connect JTAG cable and power on the board
3. Double-click the `.bat` file to burn

### Batch Download QSPI Flash (Multiple Projects)

All project directories have a `bootimage` folder containing `BOOT.bin`. You can:
1. Copy `BOOT.bin` to the `vitis_image_download` folder
2. Edit the `program_qspi.bat` to update the `program_flash` path to your installation
3. Double-click to download BOOT.bin to QSPI Flash

> **TIP**: It is recommended to download in JTAG mode. You can also use the SD card boot method to copy the BOOT.bin file to SD to boot.

---

## 13. JTAG Programming Flows (XSCT)

### Overview

XSCT (Xilinx Software Commandline Tool) provides scriptable JTAG access for programming and debugging.

### Full JTAG Programming Script

The following TCL script performs the complete JTAG programming flow: `psu_init → fpga → dow → con`:

```tcl
# program_jtag.tcl — XSCT JTAG: psu_init → fpga → dow → con
set script_dir [file dirname [file normalize [info script]]]
set ok_flag [file join $script_dir .program_jtag.ok]
catch {file delete -force $ok_flag}

set bit [file join $script_dir zynq_imgproc_platform hw imgproc_top_ov5640.bit]
set elf [file join $script_dir imgproc_baremetal Debug imgproc_baremetal.elf]
set psu [file join $script_dir zynq_imgproc_platform hw psu_init.tcl]

proc step {msg} {
    puts [format {%s %s} [clock format [clock seconds] -format {%H:%M:%S}] $msg]
    flush stdout
}

proc jtag_set_name {needle} {
    foreach line [split [string trim [targets]] \n] {
        if {[string match *$needle* $line]} {
            if {[regexp {^\s*(\d+)\s+} $line -> id]} {
                targets -set $id; return 1
            }
        }
    }
    return 0
}

# Connect to hw_server
set ::HW_SERVER_URL "TCP:127.0.0.1:10245"
catch {disconnect}
after 2000
connect -url $::HW_SERVER_URL

if {[targets] eq ""} { puts "ERROR: no JTAG targets"; exit 1 }
step "INFO: targets:\n[targets]"

# Stop A53 #0 if running
if {[jtag_set_name "Cortex-A53 #0"]} { catch {stop -timeout 15000} }

# PSU initialization
if {![jtag_set_name "PSU"]} { puts "ERROR: PSU not found"; exit 1 }
catch {mwr -force 0xffff0000 0x14000000}
catch {rst -system}
after 2000
configparams force-mem-accesses 1
source $psu
step "INFO: psu_init..."
if {[catch {psu_init} err]} { puts "ERROR: psu_init: $err"; exit 1 }
step "INFO: psu_init done"
catch {psu_ps_pl_isolation_removal}
catch {psu_ps_pl_reset_config}
configparams force-mem-accesses 0

# Program FPGA
if {![jtag_set_name "PL"]} { puts "ERROR: PL target not found"; exit 1 }
step "INFO: fpga $bit"
if {[catch {fpga -file $bit} fpga_err]} { puts "ERROR: fpga: $fpga_err"; exit 1 }
step "INFO: fpga OK"

# Download and run application
if {![jtag_set_name "Cortex-A53 #0"]} { puts "ERROR: A53 not found"; exit 1 }
catch {stop -timeout 15000}
after 500
catch {rst -processor}
after 2000
configparams force-mem-accesses 1
if {[catch {dow -clear $elf} err]} { puts "ERROR: dow: $err"; exit 1 }
configparams force-mem-accesses 0
step "INFO: dow OK"
con

set f [open $ok_flag w]; puts $f ok; close $f
step "OK — monitor UART0 @ 115200"
exit 0
```

### JTAG Flow After Vivado Program Device (DONE=HIGH)

If you already programmed the bitstream via Vivado Hardware Manager:

1. **Close** Vivado Hardware Manager (release JTAG)
2. **Do NOT** run scripts that `taskkill hw_server`
3. Execute the post-Vivado script:

```bat
deploy.bat program-elf
```

This internally uses `program_post_vivado.tcl`: `stop A53 → psu_init → dow → con`.

### JTAG Do's and Don'ts

| ✅ DO | ❌ DON'T |
|---|---|
| Close Vivado HW Manager before XSCT | Use factory `psu_init.tcl` to overwrite project (loses GEM3) |
| Set JTAG boot mode for flash programming | Repeatedly `rst -system` + multiple `psu_init` rounds (causes "Channel closed") |
| Use `program_jtag.tcl` (no `rst-system`, `psu_init` first then `fpga`) | Kill `hw_server` immediately after Vivado Program then run XSCT |
| Verify `fpga OK` in log output | Assume JTAG burn succeeded without checking logs |

### Expected UART Output After JTAG Programming

```
=== imgproc baremetal: AXI IIC + OV5640 ===
[ETH] board <board_ip> -> <pc_ip>:<port>
```

---

## 14. Deploy Automation Scripts

### deploy.bat — One-Stop Deployment

The `deploy.bat` script automates the complete Vitis workflow:

| Command | Description |
|---|---|
| `deploy.bat jtag` | Build + program via JTAG (default) |
| `deploy.bat program` | Program only (skip build) |
| `deploy.bat program-elf` | Vivado DONE=HIGH → `psu_init` + `dow` only |
| `deploy.bat program-auto` | Batch Vivado bit + XSCT post-vivado |
| `deploy.bat sync` | Copy Vivado bit to Vitis platform |
| `deploy.bat build` | Build firmware (re-copies impl bit) |
| `deploy.bat check` | JTAG connectivity check |
| `deploy.bat all` | Sync + jtag (full pipeline) |

### Deploy Flow Details

#### `deploy.bat sync` — Sync Hardware from Vivado
1. Runs `sync_hw_from_vivado.tcl` to copy bitstream and `psu_init.tcl`
2. Runs `fix_psu_init.py --fix` to patch PHY configuration
3. Runs `fix_axidma_sg_length.py` to align DMA parameters
4. Runs `check_psu_init.bat` for validation

#### `deploy.bat build` — Build Firmware
1. Runs `build_system.tcl` via XSCT
2. Re-copies Vivado `impl_1` bitstream (sysproj build may restore stale bit from XSA)
3. Copies bitstream to IDE path

#### `deploy.bat jtag` — Build + Program
1. Build firmware
2. Kill stale JTAG processes
3. Run `preflight_debug.py --fix`
4. Start `hw_server`
5. Run `program_jtag.tcl`
6. Kill `hw_server`
7. Check for `.program_jtag.ok` flag

> **CRITICAL**: The `deploy.bat build` step re-copies the bitstream from `impl_1` after building. This is because Vitis `sysproj build` may overwrite `hw/*.bit` with an older XSA bit (same size, different content).

---

## 15. Vitis Workspace Creation via XSCT (Command-Line)

### Full Workspace Regeneration Script

This script creates a complete Vitis workspace from an XSA file:

```tcl
# create_vitis_workspace.tcl
# Usage: xsct create_vitis_workspace.tcl
# Prerequisites: imgproc_top_ov5640.xsa in script directory
#                .regen_backup/imgproc_baremetal_src/*.c *.h

set script_dir [file dirname [file normalize [info script]]]
cd $script_dir
setws $script_dir

# Clean old Eclipse metadata
set projmeta [file join $script_dir .metadata .plugins org.eclipse.core.resources .projects]
foreach n {imgproc_baremetal imgproc_baremetal_system} {
    set mp [file join $projmeta $n]
    if {[file exists $mp]} { file delete -force $mp }
}

# Locate XSA
set xsa [file join $script_dir imgproc_top_ov5640.xsa]
if {![file exists $xsa]} {
    return -code error "XSA not found: $xsa"
}

# Delete old Platform / Application directories
foreach rel {zynq_imgproc_platform imgproc_baremetal imgproc_baremetal_system} {
    set p [file join $script_dir $rel]
    if {[file exists $p]} { file delete -force $p }
}

# Create platform with A53 standalone domain
platform create -name zynq_imgproc_platform -hw $xsa \
    -proc psu_cortexa53_0 -os standalone
platform active zynq_imgproc_platform

# Ensure A53 standalone domain exists
# ... (domain validation logic)

# Generate platform (creates BSP skeleton)
platform generate

# Enable lwIP (try multiple library versions)
foreach lib {lwip220 lwip211 lwip201} {
    if {![catch {bsp setlib -name $lib}]} {
        break
    }
}
# Configure lwIP for RAW API
catch {bsp config lwip220_api_mode RAW_API}

# Regenerate platform with BSP updates
platform generate

# Create empty application
app create -name imgproc_baremetal -lang c \
    -template {Empty Application} \
    -platform zynq_imgproc_platform \
    -domain standalone_psu_cortexa53_0

# Copy source files
set app_src [file join $script_dir imgproc_baremetal src]
file mkdir $app_src
foreach f [glob -nocomplain [file join $backup *.c]] {
    file copy -force $f $app_src
}
foreach f [glob -nocomplain [file join $backup *.h]] {
    file copy -force $f $app_src
}

# Build
app build -name imgproc_baremetal
```

### XSCT Quick Commands Reference

```tcl
# Set workspace
setws /path/to/workspace

# Create platform
platform create -name <plat_name> -hw <path.xsa> \
    -proc psu_cortexa53_0 -os standalone

# Generate platform (BSP)
platform generate

# Create application
app create -name <app_name> -lang c \
    -template {Hello World} \
    -platform <plat_name> \
    -domain standalone_psu_cortexa53_0

# Build
app build -name <app_name>

# BSP library management
bsp setlib -name lwip220
bsp config lwip220_api_mode RAW_API

# Domain management
domain list
domain active <domain_name>

# Remove and recreate
app remove <app_name>
platform remove <plat_name>
```

---

## 16. Syncing Hardware from Vivado

### Why Syncing Is Needed

After re-running Vivado synthesis/implementation:
- The bitstream in `impl_1/` is newer than what's in the Vitis platform `hw/` directory
- The `psu_init.tcl` may have been updated
- BSP parameters (like `c_sg_length_width`) may be mismatched

### sync_hw_from_vivado.tcl

```tcl
# Copy Vivado impl outputs to Vitis platform/hw
set vivado_proj [file join $repo_root vivado_proj]
set vitis_hw    [file join $script_dir zynq_imgproc_platform hw]

# Copy bitstream
set bit_src [file join $vivado_proj <proj>.runs impl_1 <top>.bit]
set bit_dst [file join $vitis_hw <top>.bit]
file copy -force $bit_src $bit_dst

# Copy psu_init.tcl (use BD canonical source, NOT mem_init_files copy)
set psu_src [file join $vivado_proj <proj>.srcs sources_1 bd <bd_name> ip \
    <bd_name>_zynq_ultra_ps_e_0_0 psu_init.tcl]
set psu_dst [file join $vitis_hw psu_init.tcl]
file copy -force $psu_src $psu_dst

# Also sync to IDE bitstream path
set ide_bit [file join $script_dir imgproc_baremetal _ide bitstream <top>.bit]
file mkdir [file dirname $ide_bit]
file copy -force $bit_dst $ide_bit

# Verify bit size matches impl_1
set impl_bit [file join $vivado_proj <proj>.runs impl_1 <top>.bit]
if {[file size $impl_bit] != [file size $bit_dst]} {
    return -code error "bit size mismatch after sync — copy failed?"
}
```

### psu_init.tcl Size Guidelines

| Size | Status |
|---|---|
| > 800KB | Normal (with DDR init, should match factory reference) |
| < 800KB | **Warning**: May be missing DDR initialization segments |
| ~894KB | Factory board_test reference size |
| ~659KB | Contains GEM3/ENET3 but may need DDR segments patched |

> **CRITICAL**: Never use the factory `psu_init.tcl` to overwrite the project's `psu_init.tcl` directly — it will remove GEM3 (PS Ethernet) configuration.

---

## 17. LwIP Ethernet (PS-Side) Configuration

### Overview

LwIP (Lightweight IP) is used for PS-side Ethernet communication. The PS GEM3 peripheral connects to an external PHY (JL2121).

### BSP Configuration for LwIP

1. Open Platform project → double-click `platform.spr`
2. Navigate to BSP settings for the application domain
3. Enable **lwIP** library:
   - Library name varies by version: `lwip220`, `lwip211`, or `lwip201`
   - Set API mode to **RAW_API** (for bare-metal applications)

### LwIP BSP Setup via XSCT

```tcl
# Enable lwIP library
bsp setlib -name lwip220

# Configure for RAW API mode
bsp config lwip220_api_mode RAW_API

# Regenerate platform
platform generate
```

### Ethernet Hardware Configuration (Vivado Side)

In the Block Design PS configuration:
1. **High Speed section**: Check **GEM 3**, select MIO 64..75
2. Check **MDIO 3**, select MIO 76..77
3. This maps PS Ethernet to the physical PHY on the board

### Testing Ethernet

After configuring LwIP and building the application:
1. Connect Ethernet cable between board and PC
2. Configure PC network adapter to same subnet as board
3. Run the application
4. Test with `ping <board_ip>` from PC

### Conditional Compilation Guard

```c
#if defined(XPAR_XEMACPS_0_BASEADDR) && defined(XPAR_AXIDMA_0_DEVICE_ID)
    // lwIP + DMA UDP streaming enabled
#else
    // Fallback: skip streaming, run test patterns only
#endif
```

> **NOTE**: Some BSPs map PS Ethernet 3 as `XPAR_XEMACPS_0_*` (single GEM instance index). If UDP streaming is skipped at compile time, align the preprocessor condition with your `xparameters.h` or regenerate BSP after enabling GEM3 + lwIP + DMA.

> **IMPORTANT**: Before conducting Ethernet experiments, it is necessary to modify the lwIP library. Refer to the LwIP configuration steps above.

---

## 18. PL-Side Ethernet Configuration

### Overview

In addition to PS-side Ethernet, the board has a PL-side Ethernet PHY. PL-side Ethernet requires:
- AXI Ethernet IP in the Block Design
- Interrupts configured and connected to PS
- AXI HP0 FPD enabled for DMA access

### Vivado Setup

1. Configure interrupts and **AXI HP0 FPD** based on the base PS configuration
2. Add AXI Ethernet IP core in the Block Design
3. Connect to the PL-side Ethernet PHY pins

### Vitis Development

The Vitis project creation is the same as PS-side. The lwIP library must already be configured.

### Testing

The testing method is the same as PS-side Ethernet — the establishment method of Vitis project is identical, and the lwIP library should already be modified.

---

## 19. AXI DMA Configuration and Usage

### Overview

AXI DMA transfers data between PS DDR memory and PL AXI-Stream interfaces. Used for high-bandwidth data paths (e.g., Ethernet frame streaming, camera capture).

### Key Parameters

| Parameter | Description | Typical Value |
|---|---|---|
| `c_sg_length_width` | Scatter-gather length register width | 26 (allows up to 64MB transfers) |
| Max transfer size | `(2^c_sg_length_width) - 1` bytes | 67,108,863 bytes (at width=26) |
| Frame size | Application frame payload | 1920×1080 + 8 = 2,073,608 bytes |

> **CRITICAL**: The BSP's `c_sg_length_width` must match the Vivado hardware. A mismatch (e.g., BSP=14, HW=26) causes DMA failures. Width must be ≥ 21 for 1080p frames.

### BSP / Hardware Alignment Check

```python
# Check in xparameters.h
#define XPAR_AXI_DMA_ETH_SG_LENGTH_WIDTH  26

# Check in Vivado .hwh file
# PARAMETER NAME="c_sg_length_width" VALUE="26"
```

### DMA S2MM (Slave-to-Memory-Mapped) Usage

```c
#include "xaxidma.h"

// Initialize DMA
XAxiDma_Config *CfgPtr = XAxiDma_LookupConfig(XPAR_AXIDMA_0_DEVICE_ID);
XAxiDma_CfgInitialize(&AxiDma, CfgPtr);

// Start S2MM transfer
XAxiDma_SimpleTransfer(&AxiDma, (UINTPTR)RxBuffer,
    FRAME_BYTES, XAXIDMA_DEVICE_TO_DMA);
```

### Common DMA Issues

| Symptom | Root Cause | Fix |
|---|---|---|
| DMA RxBuf all zeros | `tkeep` signal unconnected in RTL | Tie `eth_axis_tkeep = 1'b1` in top-level wrapper |
| `XST_DMA_ERROR` | sg_length_width mismatch | Run `fix_axidma_sg_length.py` then rebuild BSP |
| Frames shifted/corrupted | AXI bus width/endianness mismatch | Check AXIS data width and byte ordering |

---

## 20. Network Remote Update of QSPI

### Overview

In production, updating firmware may require opening the product shell for physical access. Network remote update allows updating FLASH programs through the network, using either **UDP** or **TCP** methods.

### Prerequisites

- LwIP library must be configured (see Section 17)
- Working Ethernet connection between board and host PC
- QSPI Flash accessible from PS

### Vivado Project

Uses the same base Vivado project as `ps_hello/vivado`.

### Vitis Project

Located in `ps_remote/vitis` directory.

> **NOTE**: Due to the use of lwIP, it is necessary to modify the lwIP library before conducting this experiment. Refer to Section 17.

---

## 21. MIPI Camera (OV5640) Integration

### Hardware

- Camera module: **ALINX AV5641** (OV5640 sensor, MIPI CSI-2, 2-lane)
- Resolution: 1920×1080 @ 30fps capable
- Data format: RAW10

### Vivado Block Design Setup

1. Add `mipi_csi2_rx_subsystem` module for receiving and parsing MIPI data
2. Configuration:
   - **Data format**: RAW10
   - **Lanes**: 2
   - **Line Rate**: 1000 Mbps (maximum supported; range 80-2500 Mbps)
   - **Pixels Per Clock**: 1 (default, 1 pixel per cycle)
3. Output: AXI-Stream interface

### Data Path

```
OV5640 MIPI CSI-2
  → MIPI RX Subsystem
    → sensor_if
      → img_preprocessor (Bayer/WB/Gamma/YCbCr)
        → line_buffer_ctrl
          → local_detail_enhance_11x11
            → bilateral_filter
              → CLAHE engine
                ├→ HDMI (ddr3_pixel_buf → display)
                └→ ETH  (frame_eth_tx → AXI DMA → PS DDR → LwIP UDP → PC)
```

### Vitis Application for Camera

The bare-metal application:
1. Initializes **AXI IIC** for camera control
2. Runs **OV5640 minimal register setup** via I2C
3. Calls `eth_stream_main()` for AXI DMA capture and UDP streaming

### Camera Bring-Up Checklist

1. Seat camera FPC connector correctly on the carrier board
2. Connect HDMI to monitor and Ethernet to PC
3. UART for logs (115200 8N1)
4. Power-on sequence: FSBL → PMU firmware → application
5. Download bitstream and ELF from Vitis
6. Monitor UART for sensor probe status

### MIPI Troubleshooting

| Symptom | Check |
|---|---|
| `DPHY not locked` | CSI-2 TX differential pair routing; MIPI reference clock (200 MHz); OV5640 power rails and reset |
| Sensor probe fails | Check I2C initialization; try `Ov5640_StandbyMode(0)` to wake sensor |
| Black image | Verify ISP pipeline registers; check DMA capture path |

---

## 22. Display Output (HDMI / DisplayPort)

### HDMI Output (ADV7511)

- Interface: Parallel RGB via ADV7511 HDMI transmitter
- Resolution: 1080p60 grayscale (148.5 MHz pixel clock)
- PL banks: BANK 45 and BANK 46 (3.3V HD I/O)

### DisplayPort Output

Configured in PS Block Design:
- Check **Display Port**, select MIO 27..30
- **Lane Selection**: Dual Higher
- Clock: DP_VIDEO = VPLL, DP_AUDIO and DP_STC = RPLL

### BMP Display Example

To display an image on DP monitor:
1. Save a **1920×1080 pixel, 24-bit BMP** file to SD card (filename: `1.bmp`)
2. Insert SD card into board
3. Connect board to DP monitor
4. Power on and run the program
5. The BMP image displays on the DP monitor
6. After power off, a captured `CAT.BMP` file may appear on the SD card

---

## 23. CAN Bus Loopback Testing

### Hardware

- 2× CAN bus transceivers (SN65HVD232C)
- CAN 0: MIO 38..39
- CAN 1: MIO 32..33

### Test Procedure

1. Build the CAN loopback test project
2. Connect CAN0 and CAN1 physically (or via loopback wiring)
3. Run the program in Debug mode
4. Set breakpoints at `RecvFrame`
5. Step through to observe:
   - `TxFrame` data generated
   - `RxFrame` data received
6. Press F6 to step — verify received data matches transmitted data

This completes CAN0 → CAN1 data transmission and reception.

---

## 24. RS485 Communication

### Hardware

- 2× RS485 transceivers (MAX3485) on the board
- Connected via PL-side UART

### Loop Test

The board has two RS485 circuits for loop testing:
1. Connect the two RS485 ports together
2. Run the RS485 test application
3. Verify serial port print information shows successful loopback

You can expand the functionality for testing based on this foundation.

---

## 25. RTC and Peripheral Driver Examples

### Finding Driver Examples

1. Click on `platform.spr` → click on **BSP**
2. Find the desired peripheral driver (e.g., RTC)
3. Click **Import Examples**
4. Look for relevant examples (e.g., `intr` suffix indicates interrupt-based examples)

> **TIP**: Basic skills are very important — knowing that "intr" means "interrupt" helps you find the right examples. Xilinx provides documentation and example projects to speed up learning.

### Peripheral Information in BSP

- **`xparameters.h`**: Contains all peripheral base addresses, device IDs, and interrupt numbers
- **`libsrc/`**: Contains peripheral function definitions and usage instructions
- **Documentation links**: Available in the BSP settings view

---

## 26. EMIO GPIO (PL LED / PL Key via PS)

### Concept

EMIO (Extended MIO) allows PS to control PL-side pins through GPIO. This is used when PS needs to control PL-side LEDs or read PL-side buttons.

### Vivado Setup

1. In Block Design, configure ZYNQ EMIO GPIO
2. Export EMIO pins to the top level
3. Add XDC constraints for the exported pins:

```tcl
####################Compress Bitstream############################
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]

set_property IOSTANDARD LVCMOS33 [get_ports {emio_tri_io[*]}]
#pl led
set_property PACKAGE_PIN AE15 [get_ports {emio_tri_io[0]}]
#pl key
set_property PACKAGE_PIN AE14 [get_ports {emio_tri_io[1]}]
```

4. **Generate bitstream** (since PL pins are used)
5. When exporting hardware, select **"Include bitstream"** (PL pins require bitstream)

### Interrupt Binding for Dual-Core

For CPU1, the key interrupt number needs to be bound to CPU1 specifically:
```c
// In PLGpioSetup function for CPU1
// Bind interrupt to CPU1 instead of CPU0
```

---

## 27. Custom AXI IP Integration (PWM Example)

### Adding Custom IP to IP Library

1. In Vivado, click **IP Catalog**
2. Right-click in **Vivado Repository** → **Add Repository**
3. Find the folder where the custom IP is located → click **Select**
4. Confirm the IP appears in the catalog

### PWM Example Application

```c
#include "xil_printf.h"
#include "ax_pwm.h"
#include "xil_io.h"
#include "xparameters.h"
#include "sleep.h"

unsigned int duty;

int main()
{
    init_platform();
    print("Hello World\n\r");

    // PWM out period = frequency(pwm_out) * (2^N) / frequency(clk)
    AX_PWM_mWriteReg(XPAR_AX_PWM_0_S00_AXI_BASEADDR,
        AX_PWM_S00_AXI_SLV_REG0_OFFSET, 17179); // 200Hz

    // duty = (2^N) * (1 - (duty cycle)) - 1
    while(1) {
        for(duty = 0x8fffffff; duty < 0xffffffff; duty = duty + 100000) {
            AX_PWM_mWriteReg(XPAR_AX_PWM_0_S00_AXI_BASEADDR,
                AX_PWM_S00_AXI_SLV_REG1_OFFSET, duty);
            usleep(100);
        }
    }

    cleanup_platform();
    return 0;
}
```

This creates a **breathing LED** effect on the PL LED using PWM.

### Debugging Custom AXI IP

- Use the Vitis debugger to inspect AXI register values
- Set breakpoints to verify register writes
- Use ILA (Integrated Logic Analyzer) in Vivado for PL-side signal monitoring

---

## 28. BRAM Shared Memory (PS ↔ PL)

### Block Design Setup

1. Add **AXI BRAM Controller** (for PS access)
2. Add **BRAM Generator** (Block RAM)
3. Add custom **PL BRAM controller** (for PL access)
4. Connect:
   - `BRAM_PORTA` of AXI BRAM Controller → `PORTA` of BRAM
   - `BRAM_PORT` of pl_bram_ctrl → `PORTB` of BRAM
5. Connect interrupt signal `intr` of pl_bram_ctrl to ZYNQ interrupt port
6. Click **Auto Connect** for remaining connections

### Address Configuration

In the **Address Editor**:
- Set BRAM address size (e.g., 4K space → 1K depth)

### Adding Logic Analyzer (Debug)

Two methods to add ILA for BRAM debugging:

**Method 1: Mark for Debug**
1. Select `BRAM_PORT` bus and `intr` interrupt
2. Right-click → **Debug**
3. Small "bug" icons appear on the signals
4. Click **Run Connection Automation** to connect debug probes

**Method 2: Manual ILA instantiation** in HDL

### Design Flow

1. Save design
2. Press F6 to check design (DRC)
3. **Generate Output Products**
4. If software auto-binds pins in reverse order, modify pin binding in IP Sources

---

## 29. Dual-Core (CPU0 / CPU1) Development

### Shared Memory Architecture

CPU0 and CPU1 communicate via shared memory addresses:
- Each CPU has its own Memory Space
- A shared address is defined for parameter passing between cores

### CPU0 Program

- Contains a character array in its Memory Space
- `Cpu1Data` points to the string address of CPU1 Memory Space
- In the `while` loop, checks for software interrupt from CPU1
- When interrupt received, prints the string from CPU1 Memory Space

### CPU1 Program

- Has its own character array
- `Cpu0Data` points to the string address of CPU0 Memory Space
- In `PLGpioSetup`, the key interrupt number is bound to CPU1

### Building Dual-Core Projects

Both CPU0 and CPU1 have separate application projects but share the same Platform project.

---

## 30. Preflight Debugging & Environment Checks

### Preflight Check Script

Before JTAG programming, run the preflight check to validate the environment:

```bat
py -3 preflight_debug.py --fix
```

### Checks Performed

| Check | Description | Fix |
|---|---|---|
| `vitis_2020.1` | Vitis 2020.1 installation found | Install Vitis 2020.1 or set XILINX_VITIS |
| `bitstream` | Bitstream file exists and has valid size | Run Vivado impl or `deploy.bat sync` |
| `firmware_elf` | Application ELF file exists | `deploy.bat build` |
| `psu_init` | psu_init.tcl valid (correct PHY, has GEM3, no stale values) | `py -3 fix_psu_init.py --fix` |
| `axidma_sg_length_width` | BSP sg_length matches Vivado HW (≥21) | `py -3 fix_axidma_sg_length.py` then build |
| `hw_server_port` | Port 10245 is free (no stale hw_server) | `_kill_jtag_all.bat` |
| `jtag_proc` | No stale xsct.exe / hw_server.exe running | `_kill_jtag_all.bat` |

### psu_init.tcl Validation

The preflight script checks:
- File size > 600KB
- Contains PHY config `0x00F022FF` (correct)
- Contains `GEM3` (PS Ethernet)
- Does NOT contain stale PHY `0x00F016CF`

### Auto-Fix Mode

Running with `--fix` automatically:
1. Kills stale JTAG processes
2. Runs `fix_psu_init.py --fix`
3. Runs `fix_axidma_sg_length.py`
4. Retries psu_init fix if stale PHY still present

---

## 31. Batch Build Vitis Projects (TCL Scripts)

### Overview

Due to the large space occupied by compiled Vitis projects, batch TCL scripts are provided to save time.

### Project Structure

Each project directory contains:
```
project/
├── vitis/
│   ├── <design>.xsa              ← Hardware description file
│   └── auto_create_vitis/
│       ├── build_vitis.bat       ← Batch build script
│       └── src/                  ← Source files (for projects not using templates)
```

### Setup

1. Right-click and edit `build_vitis.bat`
2. Replace the `xsct.bat` path with your installation path:
   ```
   D:\Xilinx\Vitis\2020.1\bin\xsct.bat
   ```
3. Save the file

### Running

1. Double-click `build_vitis.bat` to create and build the project
2. Wait for "Compile finished, press any key to exit"
3. Open Vitis, select the project path as workspace
4. After opening, close the Welcome interface — project is ready

---

## 32. BSP Management & Common Issues

### Regenerating BSP

After modifying `system.mss` (e.g., adding ttcps driver):

```tcl
# regen_bsp_ttcps.tcl
set script_dir [file dirname [file normalize [info script]]]
cd $script_dir
setws $script_dir

platform read [file join $script_dir zynq_imgproc_platform platform.spr]
domain active standalone_psu_cortexa53_0
platform generate

# Verify header exists
set hdr [file join $script_dir zynq_imgproc_platform psu_cortexa53_0 \
    standalone_psu_cortexa53_0 bsp psu_cortexa53_0 include xttcps.h]
if {![file exists $hdr]} {
    return -code error "BSP still missing xttcps.h: $hdr"
}
```

### Common BSP Issues

| Issue | Symptom | Fix |
|---|---|---|
| Missing `xttcps.h` | Compile error: "xttcps.h not found" | Add `psu_ttc_0..3` to `system.mss`, regenerate platform |
| lwIP library not found | `bsp setlib` fails | Try `lwip220`, `lwip211`, `lwip201` in order |
| `c_sg_length_width` mismatch | DMA transfers fail silently | Run `fix_axidma_sg_length.py` |
| Stale BSP after HW update | App uses old peripheral addresses | Right-click platform → Update Hardware Specification → select new XSA |

### BSP Library Management via XSCT

```tcl
# List available libraries
bsp listlib

# Add a library
bsp setlib -name lwip220

# Remove a library
bsp removelib -name lwip220

# Configure library parameter
bsp config lwip220_api_mode RAW_API

# Regenerate
platform generate
```

---

## 33. AXI4-Lite Register Map Reference (ISP Example)

### imgproc_top / axil_cfg_reg Registers

| Offset | Name | Fields | Description |
|---|---|---|---|
| `0x000` | `r_fb_addr_a` | `[31:0]` | Frame buffer A base (DDR) |
| `0x004` | `r_fb_addr_b` | `[31:0]` | Frame buffer B base |
| `0x008` | `r_ctrl` | `[0]` start, `[2:1]` res_sel, `[7:4]` frame_skip | Control register |
| `0x00C` | `r_black_level` | `[12:0]` | Black level offset |
| `0x010`–`0x018` | `r_wb_gain_*` | `[11:0]` | R/G/B white balance gains |
| `0x01C` | `r_gamma_wr` | `[20:13]` addr, `[12:0]` data | Gamma LUT write port |
| `0x020` | `r_ddr3_base` | `[31:0]` | Line-buffer DDR base |
| `0x024` | `r_sy_lut` | `[22:13]` addr, `[12:0]` data | Detail-enhancement LUT write |

### Status Registers (Read-Only)

| Offset | Name | Description |
|---|---|---|
| `0x200` | `status[0]` | Dead-pixel count |
| `0x204` | `status[1]` | Buffer select / eth_tx_frame_cnt |
| `0x208` | `status[2]` | MIPI beat counter |
| `0x20C` | `status[3]` | MIPI pixel counter |
| `0x210` | `status[4]` | RAW pixel count |
| `0x214` | `status[5]` | CLAHE pixel count |
| `0x218` | `status[6]` | FIFO overflow flags |

> **NOTE**: If `0x208+` reads `0xDEADC0DE`, the PL netlist is stale — `NUM_RD_REGS` is set to 2 instead of 7. Fix: Full `reset_run synth_1` + `impl_1` in Vivado, then re-deploy.

### Block Design Peripheral Address Map (Example)

| Instance | Function | Base Address |
|---|---|---|
| `zynq_ultra_ps_e_0` | PS, clocks, GEM3, UART | — |
| `mipi_csi2_rx_subsystem_0` | MIPI CSI-2 RX (RAW10) | `0xA0030000` |
| `axi_iic_0` | OV5640 I2C | `0xA0010000` |
| `axi_gpio_0` | Sensor GPIO | `0xA0020000` |
| `axi_dma_eth` | AXI DMA S2MM for Ethernet | `0xA0040000` |
| `imgproc_top` (M_AXIL_CFG) | ISP / display config | `0xA0000000` |

> Always cross-check `xparameters.h` in your BSP after export — exact names may vary per BD revision.

---

## 34. UDP Frame Streaming (Ethernet Application)

### Overview

The Ethernet streaming path sends image frames from PL to PC via UDP:

```
PL frame_eth_tx → AXI-Stream → AXI DMA S2MM → PS DDR → LwIP UDP → PC
```

### Frame Format

| Field | Size | Description |
|---|---|---|
| Header | 8 bytes | `0xAA 0x55`, frame ID, width, height |
| Payload | 1920×1080 bytes | Luma pixel data |
| **Total** | **2,073,608 bytes** | Per frame |

### UDP Packet Format

| Field | Size | Description |
|---|---|---|
| Chunk header | 8 bytes | Chunk metadata |
| Data | Up to 1392 bytes | Frame data chunk |
| **Max payload** | **1400 bytes** | Per UDP packet |

### Network Configuration

| Parameter | Value |
|---|---|
| Board IP | `<board_ip>` (set in `eth_stream.c`) |
| PC IP | `<pc_ip>` (set in `eth_stream.c`) |
| UDP Port | 5002 (default, avoids Windows `nidmsrv.exe` on 5000) |

### PC Receiver Setup

```powershell
# Install dependencies
python -m pip install -r tools/requirements.txt

# Run receiver
python tools/udp_img_viewer.py --bind 0.0.0.0 --port 5002 --width 1920 --height 1080

# Or use the PowerShell launcher (adds firewall rule)
powershell -NoProfile -ExecutionPolicy Bypass -File tools/start_udp_receiver.ps1
```

### One-Click JTAG + Receiver

```powershell
# Full flow
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run_full_flow.ps1

# ELF-only (Vivado already programmed bit)
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run_full_flow.ps1 -ElfOnly
```

### Common Issues

| Issue | Fix |
|---|---|
| `WinError 10048` (port in use) | Change `--port` or modify board-side `ETH_DST_PORT` |
| `WinError 10013` (access denied) | Use `--bind 0.0.0.0` or run as administrator |
| No packets received | Check `ping <board_ip>`, verify board is streaming (check UART for `[ETH] sent frame`) |
| `bad frame header` (~50% rate) | Frame sync / SOF alignment issue; debug `clahe_sof` / `frame_eth_tx` SOF with DMA TLAST boundaries |

---

## 35. Debug History & Lessons Learned

### Phase 1: Stale PL Netlist

| Symptom | Root Cause | Fix |
|---|---|---|
| `0xA0000208+` returned `0xDEADC0DE` | Synthesis DCP older than RTL; deployed bitstream still had `NUM_RD_REGS=2` | Full `reset_run synth_1` + `impl_1`; verify synth DCP timestamp is newer than RTL |

### Phase 2: Silent FPGA Programming Failures

| Symptom | Root Cause | Fix |
|---|---|---|
| JTAG burn appeared to succeed but PL unchanged | `program_jtag.tcl` swallowed errors | Add explicit `fpga OK` logging; `exit 1` on failure |

### Phase 3: Wrong Bitstream in Firmware Workspace

| Symptom | Root Cause | Fix |
|---|---|---|
| Bit hash mismatch after `deploy.bat build` | Vitis `sysproj build` overwrote `hw/*.bit` with older XSA bit | `deploy.bat build` now re-copies bit from `impl_1`; add size/hash checks |

### Phase 4: DMA RxBuf All Zeros

| Symptom | Root Cause | Fix |
|---|---|---|
| PL `eth_frames` incremented but PS `RxBuf` was zero | `ETH_AXIS_S2MM_tkeep` left unconnected in RTL | Tie `eth_axis_tkeep = 1'b1` in top-level wrapper |

### Phase 5: PS Register Write Hang

| Symptom | Root Cause | Fix |
|---|---|---|
| Writing `0xA0000008` hung PS | Empty AXI write in firmware | Source selection moved to RTL generics; firmware no longer writes that register |

### Key Takeaways

1. **Always verify synth/impl timestamps** before deploying a bitstream
2. **Check JTAG programming logs** for explicit success messages
3. **Re-copy bitstream after system build** — Vitis may overwrite with stale XSA copy
4. **Never leave AXI-Stream tkeep unconnected** — tie to `1'b1` if not used
5. **Don't write to unimplemented AXI registers** — can hang the PS bus

---

## 36. Common Pitfalls and Troubleshooting

### Vitis Project Issues

| Problem | Cause | Solution |
|---|---|---|
| "app create already exists" error | Stale Eclipse metadata | Delete `.metadata/.plugins/org.eclipse.core.resources/.projects/<app_name>` |
| Build fails with missing headers | BSP not regenerated after HW update | Right-click platform → Update Hardware Specification → new XSA → rebuild |
| BOOT.bin too old | System build uses stale bitstream | Re-copy bitstream from Vivado `impl_1` after building |
| Long build times | Building system project every time | Build APP project only when iterating; build system only for boot image |

### JTAG Issues

| Problem | Cause | Solution |
|---|---|---|
| "No JTAG targets" | USB cable disconnected or driver issue | Reconnect USB JTAG; check Windows Device Manager |
| "Channel closed" during psu_init | Multiple `rst -system` + `psu_init` cycles | Kill all hw_server/xsct, wait 5s, reconnect |
| JTAG timeout | Stale hw_server on port 10245 | Run `_kill_jtag_all.bat` to clean up |
| PL unchanged after burn | Silent FPGA programming failure | Check for `fpga OK` in logs; use `program_jtag.tcl` with explicit error checking |

### Boot Issues

| Problem | Cause | Solution |
|---|---|---|
| SD card won't boot | Wrong filesystem format | Must be **FAT32** only |
| FSBL hangs | DDR initialization failure | Check `psu_init.tcl` size (should be >800KB); run `regen_psu_init_and_sync.bat` |
| Application crashes after boot | Wrong psu_init.tcl / xparameters mismatch | Regenerate BSP from current XSA; verify DDR config matches board |
| QSPI burn fails | Not in JTAG boot mode | Set DIP switches to JTAG mode before programming |

### Ethernet Issues

| Problem | Cause | Solution |
|---|---|---|
| No link negotiation | PHY not initialized | Check BD clocking and PS Ethernet MDIO/MDC routing |
| `lwIP_init()` fails | BSP missing lwIP library | Add lwIP to BSP settings; set RAW_API mode |
| Ping timeout | Wrong subnet | Verify board and PC are on same subnet |
| UDP but no display | `recv_display.py` needs local desktop | Run on local Windows (not remote SSH); OpenCV `imshow` needs display |

### MIPI Issues

| Problem | Cause | Solution |
|---|---|---|
| DPHY not locked | Clock/routing issue | Verify MIPI reference clock (200 MHz); check termination |
| Sensor probe fails | I2C init failed | Check OV5640 power rails and reset signal |
| Black frames | ISP pipeline misconfigured | Check register writes; verify DMA capture path |

### Design Mode Tips

- You can switch between **Design** and **Debug** perspectives in the upper-right corner of Vitis
- The **Block Design name** should be as short as possible — long names cause problems when compiling under Windows (path length limits)

---

## 37. Key Xilinx Documentation References

| Document | ID | Description |
|---|---|---|
| Zynq UltraScale+ MPSoC TRM | **UG1085** | Complete technical reference for ZYNQ MPSoC |
| Vitis Unified Software Platform | **UG1393** | Vitis development workflow and tools |
| Bootgen User Guide | **UG1283** | Boot image generation |
| FSBL Wiki | — | First Stage Boot Loader customization |
| AXI Reference Guide | **UG1037** | AXI protocol and IP usage |
| LwIP Documentation | — | Lightweight IP stack for bare-metal |
| Vivado Design Suite User Guide | **UG910** | Vivado project management |
| ALINX Board Manual | — | AXU4EVB-P / AXU5EVB-P hardware manual |

### Useful IP Core Documentation

| IP Core | Purpose |
|---|---|
| AXI DMA | High-bandwidth PS↔PL data transfer |
| AXI IIC | I2C master for sensor/peripheral control |
| AXI GPIO | General purpose I/O from PS |
| MIPI CSI-2 RX Subsystem | Camera input processing |
| AXI Ethernet | PL-side network interface |
| AXI BRAM Controller | PS access to Block RAM |
| AXI Interconnect / SmartConnect | Multi-master/slave AXI routing |

---

## APPENDIX A: PS I/O Configuration Summary (Vivado Block Design)

### Bank Voltages

| Bank | Voltage |
|---|---|
| BANK 0 (MIO 0–25) | LVCMOS18 |
| BANK 1 (MIO 26–51) | LVCMOS18 |
| BANK 2 (MIO 52–77) | LVCMOS18 |
| BANK 3 | LVCMOS33 |

### Low Speed Pin Configuration

| Peripheral | Setting | MIO Pins |
|---|---|---|
| QSPI | Single mode, x4 data, Feedback Clk | Default |
| SD 0 (eMMC) | Slot Type: eMMC, 8Bit, Reset: MIO23 | MIO 13..22 |
| SD 1 (SD card) | Slot Type: SD 2.0, 4Bit, CD: MIO45 | MIO 46..51 |
| CAN 0 | — | MIO 38..39 |
| CAN 1 | — | MIO 32..33 |
| I2C 1 | For EEPROM, temp sensor | MIO 24..25 |
| UART 0 | Serial console | MIO 42..43 |
| GPIO1 MIO | General purpose | Checked |
| TTC 0–3 | Triple Timer Counter | Checked |

### High Speed Pin Configuration

| Peripheral | Setting | MIO Pins |
|---|---|---|
| GEM 3 (PS Ethernet) | MDIO 3: MIO 76..77 | MIO 64..75 |
| USB 0 | USB 3.0: GT Lane1, Reset: MIO 31 | MIO 52..63 |
| PCIe | ROOT mode (Switch To Advanced Mode) | — |
| Display Port | Dual Higher lanes, Reset: MIO 37 | MIO 27..30 |

### Clock Configuration

| Clock Source | Setting |
|---|---|
| PSS_REF_CLOCK | 33.333 MHz (default) |
| PCIe | Ref Clk0, 100 MHz |
| Display Port | Ref Clk2, 27 MHz |
| USB0 | Ref Clk1, 26 MHz |
| Output Clocks PLL | IOPLL (all, for consistency) |
| PL Clock | Default (provided to PL-side logic) |
| DP_VIDEO | VPLL |
| DP_AUDIO, DP_STC | RPLL |

### DDR Configuration

| Parameter | Value |
|---|---|
| DDR Preset | `DDR4_MICRON_MT40A512M16LY_062E` (or nearest match in Vivado) |
| Additional parameters | Modified per board-specific requirements |

---

## APPENDIX B: Repository Layout Reference

### Standard ALINX Tutorial Project Structure

```
project_name/
├── vivado/                    ← Vivado project
│   ├── <project>.xpr
│   └── <project>.runs/
│       └── impl_1/
│           └── <top>.bit
├── vitis/                     ← Vitis workspace
│   ├── <design>.xsa           ← Hardware description
│   └── auto_create_vitis/
│       ├── build_vitis.bat    ← Batch build script
│       └── src/               ← Source files
└── bootimage/
    └── BOOT.bin               ← Pre-built boot image
```

### Image Processing Project (imgproc) Structure

```
imgproc/
├── files/
│   ├── sources_1/             ← RTL sources
│   │   ├── rtl_top/           ← Top-level RTL
│   │   ├── project/src/       ← ISP pipeline RTL
│   │   └── common/            ← Utility modules
│   ├── create_bd_ov5640.tcl   ← Block Design creation script
│   ├── create_project_ov5640.tcl
│   └── imgproc_axu4evb_ov5640.xdc ← Pin constraints
├── vivado_proj/
│   ├── imgproc_*.xpr          ← Vivado project (OPEN THIS)
│   └── imgproc_*.srcs/
│       └── sources_1/bd/      ← Block Design
├── vitis_project/
│   ├── zynq_imgproc_platform/ ← Platform + BSP
│   │   ├── hw/                ← HW metadata, bitstream, psu_init
│   │   └── sysroot/.../bsp/   ← BSP libs & xparameters.h
│   ├── imgproc_baremetal/     ← Bare-metal application
│   │   └── src/
│   │       ├── main.c         ← Entry point
│   │       ├── eth_stream.c   ← AXI DMA + LwIP UDP
│   │       └── pl_iic_ov5640.c ← OV5640 I2C init
│   ├── imgproc_baremetal_system/
│   ├── deploy.bat             ← One-stop deployment
│   ├── create_vitis_workspace.tcl
│   ├── build_system.tcl
│   ├── make_boot.tcl
│   ├── program_jtag.tcl
│   ├── sync_hw_from_vivado.tcl
│   └── preflight_debug.py
├── pc_viewer/
│   └── recv_display.py        ← PC frame display
├── tools/
│   ├── udp_img_viewer.py
│   ├── start_udp_receiver.ps1
│   └── run_full_flow.ps1
└── boot_images/               ← Pre-built images
```

---

## APPENDIX C: Quick Command Reference

### Vitis IDE Shortcuts

| Action | Shortcut / Menu |
|---|---|
| Build Project | Right-click → Build Project, or Hammer icon |
| Run on Hardware | Right-click → Run As → Launch on Hardware |
| Debug on Hardware | Right-click → Debug As → Debug on Hardware |
| Step Over | F6 |
| Resume | F8 |
| Create Boot Image | Right-click system → Create Boot Image |
| Program Flash | Xilinx → Program Flash |
| Switch perspective | Upper-right corner icons |

### XSCT Commands

```tcl
# Workspace
setws <path>

# Platform
platform create -name <n> -hw <xsa> -proc psu_cortexa53_0 -os standalone
platform active <n>
platform generate

# Application
app create -name <n> -platform <p> -domain <d> -lang c -template {Hello World}
app build -name <n>
app remove <n>

# BSP
bsp setlib -name lwip220
bsp config lwip220_api_mode RAW_API
bsp listlib

# Domain
domain list
domain active <d>
domain create -name <n> -os standalone -proc psu_cortexa53_0

# System project
sysproj build -name <n>_system

# JTAG
connect -url TCP:127.0.0.1:10245
targets
targets -set <id>
fpga -file <bit>
dow -clear <elf>
con
stop
rst -system
rst -processor
configparams force-mem-accesses 1
```

### Batch Commands (Windows)

```bat
:: Source Vitis environment
call D:\Xilinx\Vitis\2020.1\settings64.bat

:: XSCT script execution
xsct script.tcl

:: Program QSPI flash
call D:\Xilinx\Vitis\2020.1\bin\program_flash -f BOOT.bin -offset 0 -flash_type qspi-x4-single -fsbl fsbl.elf -verify

:: Generate boot image
bootgen -arch zynqmp -image boot.bif -o BOOT.bin -w

:: Deploy commands
deploy.bat jtag          :: Build + program
deploy.bat sync          :: Sync from Vivado
deploy.bat build         :: Build only
deploy.bat program       :: Program only
deploy.bat program-elf   :: Post-Vivado ELF download
deploy.bat all           :: Full pipeline
```

---

> **Document Version**: 1.0
> **Last Updated**: 2026-07-07
> **Sources**: ALINX AXU4EVB-P User Manual, ALINX Vitis Tutorial Documentation, imgproc_zynq4ev_ov5640 project files, debug history logs
> **Note**: Feishu wiki URLs (cqsrdbo4fm8.feishu.cn) were inaccessible (HTTP 444 / authentication required). Content is derived entirely from local documentation and project files.
