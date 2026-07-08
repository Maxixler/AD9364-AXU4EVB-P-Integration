# MEGA LINUX / PETALINUX INSTRUCTIONS — ALINX AXU5EVB-P Development Board

> **Purpose**: This document is the **single source of truth** for all technical details about PetaLinux and embedded Linux development on the ALINX AXU5EVB-P (also referenced as AXU5EV-P / AXU4EV-P) FPGA/SoC development board. It is designed to be consumed by an AI assistant (Claude) to provide accurate, board-specific guidance for PetaLinux system building, device tree customization, application development, and boot configuration during an SDR project.
>
> **Toolchain**: Vivado 2020.1 + PetaLinux 2020.1 + Vitis 2020.1
>
> **Host OS**: Ubuntu 18.04 (recommended; Ubuntu 16 for Vivado 2017 only)
>
> **Target Chips**: XCZU5EV-2SFVC784I (AXU5EV-P) / XCZU4EV-SFVC784-1-I (AXU4EV-P)

---

## TABLE OF CONTENTS

1. [Board & Chip Quick Reference](#1-board--chip-quick-reference)
2. [Software Environment Requirements](#2-software-environment-requirements)
3. [PetaLinux Project Creation](#3-petalinux-project-creation)
4. [Hardware Configuration (petalinux-config --get-hw-description)](#4-hardware-configuration)
5. [Offline Compilation Setup](#5-offline-compilation-setup)
6. [Local Kernel and U-Boot Source Code](#6-local-kernel-and-u-boot-source-code)
7. [Device Tree Customization](#7-device-tree-customization)
8. [Building the PetaLinux Project](#8-building-the-petalinux-project)
9. [PetaLinux Configuration Commands Reference](#9-petalinux-configuration-commands-reference)
10. [Manually Configurable Files Reference](#10-manually-configurable-files-reference)
11. [BSP Package Creation and Usage](#11-bsp-package-creation-and-usage)
12. [Boot Image (BOOT.bin) Packaging](#12-boot-image-bootbin-packaging)
13. [SD Card Boot — INITRAMFS (ramdisk)](#13-sd-card-boot--initramfs-ramdisk)
14. [SD Card Root File System (EXT4 Persistent)](#14-sd-card-root-file-system-ext4-persistent)
15. [QSPI Flash Boot](#15-qspi-flash-boot)
16. [QSPI Flash + eMMC Boot (Hybrid)](#16-qspi-flash--emmc-boot-hybrid)
17. [Adding Startup Scripts and User Files](#17-adding-startup-scripts-and-user-files)
18. [Cross-Compiling C Applications (Hello World)](#18-cross-compiling-c-applications-hello-world)
19. [GPIO Control Under Linux](#19-gpio-control-under-linux)
20. [Linux Register-Level Peripheral Access (mmap)](#20-linux-register-level-peripheral-access-mmap)
21. [NVMe SSD Operation Under Linux](#21-nvme-ssd-operation-under-linux)
22. [Qt and OpenCV Cross-Compilation Environment](#22-qt-and-opencv-cross-compilation-environment)
23. [OpenCV Edge Detection Application](#23-opencv-edge-detection-application)
24. [OpenCV + Qt Face Detection](#24-opencv--qt-face-detection)
25. [Remote Debugging with GDB and QtCreator](#25-remote-debugging-with-gdb-and-qtcreator)
26. [Vitis Acceleration Platform Creation](#26-vitis-acceleration-platform-creation)
27. [Kernel and Rootfs Configuration Details](#27-kernel-and-rootfs-configuration-details)
28. [Display and Camera Setup Under Linux](#28-display-and-camera-setup-under-linux)
29. [PetaLinux Cleanup and Troubleshooting](#29-petalinux-cleanup-and-troubleshooting)
30. [Key Xilinx Documentation References](#30-key-xilinx-documentation-references)

---

## 1. Board & Chip Quick Reference

### Supported Development Boards

| Board Model | Chip Model | Vivado Part String | PetaLinux Template |
|---|---|---|---|
| AXU5EV-P (AXU5EVB-P) | XCZU5EV-2SFVC784I | `xczu5ev-sfvc784-2-i` | `zynqMP` |
| AXU4EV-P (AXU4EVB-P) | XCZU4EV-SFVC784-1-I | `xczu4ev-sfvc784-1-i` | `zynqMP` |

### Key Hardware

| Component | Details |
|---|---|
| **APU** | Quad-core ARM Cortex-A53 @ 1.3 GHz (runs Linux) |
| **RPU** | Dual-core ARM Cortex-R5F @ 533 MHz |
| **PS DDR4** | 4GB |
| **eMMC** | 8GB (mmc0 — first MMC device) |
| **SD Card** | Micro SD slot (mmc1 — second MMC device when using `ps_hello` project) |
| **QSPI Flash** | 256Mb (Micron mt25qu256) |
| **Ethernet** | PS GEM3 (MIO 64..75), PL-side GbE |
| **USB** | USB 3.0 Host (MIO 52..63) |
| **UART** | PS UART0 (MIO 42..43), 115200 8N1 |
| **Display** | Mini DisplayPort, HDMI out (ADV7511) |
| **Camera** | MIPI CSI-2 (OV5640) |

> **IMPORTANT**: The SD card is the **second** MMC device (`mmcblk1`) when using the `ps_hello` Vivado project. This affects root filesystem device node configuration.

---

## 2. Software Environment Requirements

### Host System

| Requirement | Specification |
|---|---|
| **OS** | Ubuntu 18.04 LTS (on bare metal or VM) |
| **VM Memory** | ≥ 16GB recommended (Vitis acceleration compilation needs ≥ 16GB) |
| **Disk Space** | ≥ 100GB for PetaLinux + Vivado + Vitis |
| **Display** | Full-screen terminal recommended (menuconfig may error on small windows) |

### Required Software

| Software | Version | Purpose |
|---|---|---|
| **Vivado** | 2020.1 | FPGA design, hardware export (.xsa) |
| **PetaLinux** | 2020.1 | Embedded Linux system builder |
| **Vitis** | 2020.1 | Application development, acceleration platform |
| **Serial Terminal** | Any (minicom, PuTTY, picocom) | UART monitoring (115200 8N1) |

### PetaLinux Installation Path

```
/opt/pkg/petalinux/          ← Default PetaLinux installation
/opt/pkg/petalinux/settings.sh  ← Environment setup script
```

### Vitis/Vivado Installation Path (Linux)

```
/tools/Xilinx/Vitis/2020.1/settings64.sh
/tools/Xilinx/Vivado/2020.1/settings64.sh
```

### Environment Variables

Environment variables are **only valid in the currently open terminal**. If the terminal is closed, you must re-source:

```bash
# PetaLinux environment
source /opt/pkg/petalinux/settings.sh

# Vitis/Vivado environment (for cross-compilation)
source /tools/Xilinx/Vitis/2020.1/settings64.sh
```

---

## 3. PetaLinux Project Creation

### Directory Structure Convention

```bash
# Create working directory structure
mkdir -p ~/peta_prj/<project_name>/hardware
```

| Path | Purpose |
|---|---|
| `~/peta_prj/` | Root for all PetaLinux projects |
| `~/peta_prj/<project_name>/` | Individual project folder |
| `~/peta_prj/<project_name>/hardware/` | Stores the .xsa file from Vivado |
| `~/peta_prj/<project_name>/petalinux/` | PetaLinux project (created by `petalinux-create`) |

### Step-by-Step

```bash
# 1. Create directories
mkdir -p ~/peta_prj/linuxPsBase/hardware

# 2. Copy XSA file from Vivado project to hardware folder
cp /path/to/vivado/project/design_1_wrapper.xsa ~/peta_prj/linuxPsBase/hardware/

# 3. Navigate to project folder
cd ~/peta_prj/linuxPsBase/

# 4. Source PetaLinux environment
source /opt/pkg/petalinux/settings.sh

# 5. Create PetaLinux project
petalinux-create -t project -n petalinux --template zynqMP

# 6. Enter the project directory
cd ~/peta_prj/linuxPsBase/petalinux
```

### petalinux-create Parameters

| Parameter | Value | Description |
|---|---|---|
| `-t` | `project` | Type: creating a project |
| `-n` | `petalinux` | Project name |
| `--template` | `zynqMP` | Template for Zynq UltraScale+ MPSoC |

> **NOTE**: For Zynq-7000 series, use `--template zynq` instead.

---

## 4. Hardware Configuration

### Importing Hardware Description

```bash
# Must be run from inside the petalinux project directory
cd ~/peta_prj/linuxPsBase/petalinux
petalinux-config --get-hw-description ../hardware/
```

> **⚠ IMPORTANT**: There must be **only one** `.xsa` file in the hardware directory.

> **TIP**: If you get menuconfig display errors, make the Ubuntu window **full screen** and maximize the terminal.

### Configuration Interface

After running `petalinux-config --get-hw-description`, a menuconfig interface appears with sections:
- **Linux Components Selection** — kernel/u-boot sources
- **Auto Config Settings** — kernel autoconfig, u-boot autoconfig
- **Subsystem AUTO Hardware Settings** — boot device, flash, Ethernet, SD
- **DTG Settings** — device tree generation
- **Image Packaging Configuration** — root filesystem type, boot format
- **Firmware Version Configuration** — hostname, product name
- **Yocto Settings** — build system configuration

### Kernel/U-Boot Autoconfig Options

> **NOTE**: This tutorial follows old PetaLinux habits and configures "kernel autoconfig" and "u-boot autoconfig" options. However, these two options can also be **left unselected**. If compile errors occur with these configured, try removing them and compiling again.

### Saving Configuration

If "Save" was not selected, when exiting, a prompt asks whether to save — select `<Yes>`.

---

## 5. Offline Compilation Setup

### Why Offline?

PetaLinux by default downloads packages from the internet. For environments without network access or for reproducible builds, configure offline compilation using pre-downloaded packages.

### Step-by-Step

1. Copy the offline package to the VM and unzip (e.g., to `/home/Downloads/petalinux_offline_pkg`)

2. Open terminal in the PetaLinux project:
   ```bash
   petalinux-config
   ```

3. **Disable network access**: Uncheck `Enable BB NO NETWORK`
   > If compile reports "Network access disabled through BB_NO_NETWORK", uncheck this option

4. **Set sstate cache path**: Go to `Yocto Settings → Local sstate feeds settings` and set the path to the `sstate_aarch64` package directory

5. **Set downloads mirror**: Go to `Yocto Settings → Add pre-mirror url` and set the path to the `downloads` package directory

6. Save and exit

---

## 6. Local Kernel and U-Boot Source Code

### Why Use Local Sources?

If you need to modify the kernel or U-Boot source code, configure PetaLinux to use local copies instead of downloading.

### Configuration

```bash
petalinux-config
```

1. Navigate to `Linux Components Selection`
2. Set **Linux kernel** source to `ext-local-src` and provide the path to local kernel source
3. Set **U-Boot** source to `ext-local-src` and provide the path to local U-Boot source
4. Save and exit

The offline package typically includes Xilinx kernel and U-Boot source trees that can be used directly.

---

## 7. Device Tree Customization

### Device Tree Files Location

```
<petalinux_project>/project-spec/meta-user/recipes-bsp/device-tree/files/
├── system-user.dtsi     ← Primary custom device tree (edit this)
├── pl-custom.dtsi       ← PL-side custom device tree
└── system-conf.dtsi     ← Auto-generated (do NOT edit directly)
```

### Basic Device Tree (SD + USB)

```dts
/include/ "system-conf.dtsi"
/ {
};

/* SD card — disable write-protect, disable 1.8V switching */
&sdhci1 {
    disable-wp;
    no-1-8-v;
};

/* USB — enable host mode */
&dwc3_0 {
    status = "okay";
    dr_mode = "host";
};
```

### Device Tree for Vitis Acceleration Platform (with zocl)

```dts
/include/ "system-conf.dtsi"
/ {
    chosen {
        bootargs = "earlycon console=ttyPS0,115200 clk_ignore_unused root=/dev/mmcblk1p2 rw rootwait cma=512M";
    };
};

&amba {
    zyxclmm_drm {
        compatible = "xlnx,zocl";
        status = "okay";
        interrupt-parent = <&axi_intc_0>;
        interrupts = <0 4>, <1 4>, <2 4>, <3 4>,
                     <4 4>, <5 4>, <6 4>, <7 4>,
                     <8 4>, <9 4>, <10 4>, <11 4>,
                     <12 4>, <13 4>, <14 4>, <15 4>,
                     <16 4>, <17 4>, <18 4>, <19 4>,
                     <20 4>, <21 4>, <22 4>, <23 4>,
                     <24 4>, <25 4>, <26 4>, <27 4>,
                     <28 4>, <29 4>, <30 4>, <31 4>;
    };
};

&axi_intc_0 {
    xlnx,kind-of-intr = <0x0>;
    xlnx,num-intr-inputs = <0x20>;
    interrupt-parent = <&gic>;
    interrupts = <0 89 4>;
};

&sdhci1 {
    no-1-8-v;
    disable-wp;
};
```

### Device Tree for QSPI+eMMC Boot

```dts
/include/ "system-conf.dtsi"
/ {
};

/* SD */
&sdhci1 {
    disable-wp;
    no-1-8-v;
};

/* eMMC */
&sdhci0 {
    disable-wp;
    no-1-8-v;
};

/* USB */
&dwc3_0 {
    status = "okay";
    dr_mode = "host";
};
```

---

## 8. Building the PetaLinux Project

### Build Commands

```bash
# Full build
petalinux-build

# Build SDK (requires online compilation enabled)
petalinux-build --sdk
```

### Build Output Location

All build outputs are in:
```
<petalinux_project>/images/linux/
├── BOOT.bin              ← Boot image (after packaging)
├── image.ub              ← Kernel + DTB + ramdisk (FIT image)
├── boot.scr              ← U-Boot boot script
├── rootfs.tar.gz         ← Root filesystem archive
├── zynqmp_fsbl.elf       ← First Stage Boot Loader
├── pmufw.elf             ← PMU Firmware
├── bl31.elf              ← ARM Trusted Firmware
├── u-boot.elf            ← U-Boot bootloader
├── system.dtb            ← Compiled device tree blob
└── sdk.sh                ← SDK installer (after --sdk build)
```

### Clean Build

If various compile problems occur (especially after modifying configurations):
```bash
petalinux-build -x mrproper -f
```
This cleans all previous compile results.

---

## 9. PetaLinux Configuration Commands Reference

| Command | Purpose |
|---|---|
| `petalinux-config` | Main system configuration (boot, flash, rootfs type) |
| `petalinux-config --get-hw-description <path>` | Import/update hardware description (.xsa) |
| `petalinux-config -c kernel` | Configure Linux kernel (menuconfig) |
| `petalinux-config -c u-boot` | Configure U-Boot (menuconfig) |
| `petalinux-config -c rootfs` | Configure root filesystem packages |
| `petalinux-build` | Build the full project |
| `petalinux-build --sdk` | Build the SDK for cross-compilation |
| `petalinux-build -x mrproper -f` | Clean all build artifacts |
| `petalinux-package --boot ...` | Package BOOT.bin |
| `petalinux-package --bsp ...` | Create BSP package for distribution |
| `petalinux-create -t project ...` | Create new PetaLinux project |
| `petalinux-create -t apps ...` | Create application recipe |

---

## 10. Manually Configurable Files Reference

All manually configurable files are in `<project>/project-spec/meta-user/`:

| File/Path | Purpose |
|---|---|
| `recipes-bsp/device-tree/files/system-user.dtsi` | Custom device tree |
| `recipes-bsp/device-tree/files/pl-custom.dtsi` | PL-side device tree |
| `recipes-bsp/u-boot/files/platform-top.h` | U-Boot configuration modifications |
| `recipes-bsp/u-boot/u-boot-zynq-scr.bbappend` | Boot script configuration |
| `recipes-kernel/linux/linux-xlnx/` | Kernel configuration |
| `recipes-apps/` | Custom application recipes |
| `conf/user-rootfsconfig` | Custom rootfs package list |

> **TIP**: These configuration files can be **directly copied** to other PetaLinux projects for reuse.

---

## 11. BSP Package Creation and Usage

### Creating a BSP Package

BSP packages allow easy distribution of verified PetaLinux projects:

```bash
# Run from the parent directory of the petalinux project
petalinux-package --bsp -p ./petalinux/ --output chapter1.bsp
```

| Parameter | Description |
|---|---|
| `-p` | Path to the PetaLinux project (first-level directory) |
| `--output` | Name of the BSP package file |

### Using a BSP Package

```bash
petalinux-create -t project -s chapter1.bsp
```

> **NOTE**: If the project that created the BSP package compiles successfully, the project created from the BSP package will also compile directly.

---

## 12. Boot Image (BOOT.bin) Packaging

### Basic BOOT.bin (No PL Bitstream)

```bash
petalinux-package --boot --fsbl images/linux/zynqmp_fsbl.elf \
    --u-boot --force
```

### BOOT.bin with PL Bitstream

```bash
petalinux-package --boot --fsbl images/linux/zynqmp_fsbl.elf \
    --fpga images/linux/system.bit \
    --u-boot --force
```

### BOOT.bin for QSPI Flash Boot (with kernel)

```bash
petalinux-package --boot \
    --fsbl ./images/linux/zynqmp_fsbl.elf \
    --u-boot \
    --kernel \
    --add ./images/linux/boot.scr --offset 0x01F10000 \
    --force
```

### BOOT.bin for QSPI+eMMC Boot

```bash
petalinux-package --boot \
    --u-boot \
    --add ./images/linux/boot.scr --offset 0xA10000 --load 0x20000000 \
    --force
```

### Linux BIF File Format

For Vitis acceleration platform, create `linux.bif`:
```
/* linux */
the_ROM_image:
{
    [fsbl_config] a53_x64
    [bootloader] <fsbl.elf>
    [pmufw_image] <pmufw.elf>
    [destination_device=pl] <bitstream>
    [destination_cpu=a53-0, exception_level=el-3, trustzone] <bl31.elf>
    [destination_cpu=a53-0, exception_level=el-2] <u-boot.elf>
}
```

---

## 13. SD Card Boot — INITRAMFS (ramdisk)

### Overview

The default root filesystem type in PetaLinux is **INITRAMFS (ramdisk)**. This filesystem is **read-only** — any modifications are lost after system restart.

### Files to Copy to SD Card

Copy these three files from `images/linux/` to the SD card (FAT32 formatted):
1. `BOOT.bin`
2. `boot.scr`
3. `image.ub`

### Boot Mode

Set the development board DIP switch to **SD card boot mode**, then power on.

### Default Login

| Parameter | Value |
|---|---|
| Username | `root` |
| Password | `root` |

---

## 14. SD Card Root File System (EXT4 Persistent)

### Overview

For a **persistent** root file system that survives reboots, use EXT4 format on SD card.

### PetaLinux Configuration

```bash
petalinux-config
```

1. Navigate to `Image Packaging Configuration → Root filesystem type`
2. Select **EXT (SD/eMMC/QSPI/SATA/USB)**
3. Set **Device node of SD device**:
   - If using `ps_hello` Vivado project: SD card is the **second** MMC device → enter `/dev/mmcblk1p2`
   - Default value `mmcblk0p2` represents the second partition of the **first** MMC device

> **⚠ CRITICAL**: If you fill in the device node incorrectly, Linux will **fail to boot**. The correct value depends on your Vivado project's eMMC/SD MIO mapping.

### SD Card Partitioning

1. Insert SD card into card reader → connect to VM
2. Open **Disks** utility in Ubuntu (search "disk")
3. Delete all existing partitions
4. Create **Partition 1**: ~5000MB, FAT format, name "FAT"
5. Create **Partition 2**: Remaining space, EXT4 format, name "EXT"
6. Reinsert SD card (system auto-mounts)

### Copying Files

```bash
# Extract rootfs to EXT4 partition
sudo tar -zxvf <petalinux_path>/images/linux/rootfs.tar.gz -C /media/alinx/EXT

# Sync cached data (may take a while)
sudo sync

# Copy boot files to FAT partition
cp <petalinux_path>/images/linux/BOOT.bin /media/alinx/FAT/
cp <petalinux_path>/images/linux/boot.scr /media/alinx/FAT/
cp <petalinux_path>/images/linux/image.ub /media/alinx/FAT/
```

### Boot

Set board to SD mode, power on. The system will retain applications and data across reboots.

---

## 15. QSPI Flash Boot

### PetaLinux Configuration

```bash
petalinux-config
```

1. `Subsystem AUTO Hardware Settings → Advanced bootable images storage Settings → boot image settings → image storage media` → Select **primary flash**
2. `Subsystem AUTO Hardware Settings → Advanced bootable images storage Settings → kernel image settings → image storage media` → Select **primary flash**
3. `Image Packaging Configuration → Root filesystem type` → Select **INITRAMFS**

### Flash Partition Configuration

Go to `Subsystem AUTO Hardware Settings → Flash Settings` and configure:

| Partition | Contents | Size (adjust to actual) |
|---|---|---|
| **boot** | .bit, u-boot, fsbl, .dtb | Must be > sum of all boot files |
| **bootenv** | U-Boot environment variables | Modify as needed |
| **kernel** | image.ub | Must be > image.ub size |
| **bootscr** | boot.scr | Must be > boot.scr size |

> **⚠ WARNING**: Total size of all partitions cannot exceed the Flash size (256Mb = 32MB).

### U-Boot Boot Script Offset

```bash
petalinux-config -c u-boot
```

Navigate to `ARM architecture → Boot script offset` and set:
```
Offset = boot_size + bootenv_size + kernel_size
Example: 0x1F10000 = 0xA00000 + 0x10000 + 0x1500000
```

### U-Boot Boot Script Offset File

Open `project-spec/meta-user/recipes-bsp/u-boot/u-boot-zynq-scr.bbappend` and modify the kernel offset address and kernel size to match the flash partition settings.

### Build and Package

```bash
petalinux-build

petalinux-package --boot \
    --fsbl ./images/linux/zynqmp_fsbl.elf \
    --u-boot \
    --kernel \
    --add ./images/linux/boot.scr --offset 0x01F10000 \
    --force
```

### Burning to QSPI

Use the Vitis `program_flash` tool (refer to the Vitis tutorial) to burn `BOOT.bin` to the board. Set DIP switch to QSPI mode and power on.

---

## 16. QSPI Flash + eMMC Boot (Hybrid)

### Concept

The board does not support booting directly from eMMC, but can use:
- **QSPI Flash**: Boot loader (FSBL + U-Boot + boot.scr)
- **eMMC**: Kernel (image.ub) + Root filesystem

### PetaLinux Configuration

1. Boot image → **primary flash** (QSPI)
2. Kernel image → **primary sd** (eMMC)
3. Root filesystem type → **EXT4**
4. Device node → `/dev/mmcblk0p1` (eMMC is first MMC device)
5. Add `ext4` to "Root filesystem formats"
6. Flash Settings → Configure boot partition size

### U-Boot Configuration

```bash
petalinux-config -c u-boot
```
Set boot script offset to `0xA10000`.

### Boot Command Modification

Open `project-spec/meta-user/recipes-bsp/u-boot/u-boot-zynq-scr/boot.cmd.default.initrd` and add:

```bash
setenv bootargs "earlycon console=ttyPS0,115200 clk_ignore_unused root=/dev/mmcblk0p2 rw rootwait"
fatload mmc 0:1 0x10000000 image.ub && bootm 0x10000000
```

### eMMC Partition Setup

Since eMMC cannot be formatted on PC, boot from another system first (e.g., SD card with Linux), then:

```bash
# Partition eMMC
fdisk /dev/mmcblk0

# Create partition 1 (FAT, 1GB for kernel)
n → p → 1 → default → +1G

# Create partition 2 (EXT4, remainder for rootfs)
n → p → 2 → default → default

# Save and exit
wq

# Format partitions
mkfs.vfat /dev/mmcblk0p1
mkfs.ext4 /dev/mmcblk0p2

# Mount
mkdir -p /media/sd-mmcblk0p1 /media/sd-mmcblk0p2
mount /dev/mmcblk0p1 /media/sd-mmcblk0p1/
mount /dev/mmcblk0p2 /media/sd-mmcblk0p2/

# Copy kernel
cp image.ub /media/sd-mmcblk0p1/

# Extract rootfs
tar -zxvf rootfs.tar.gz -C /media/sd-mmcblk0p2/
sync
```

### BOOT.bin Package and Burn

```bash
petalinux-package --boot --u-boot \
    --add ./images/linux/boot.scr --offset 0xA10000 --load 0x20000000 \
    --force
```

Burn BOOT.bin to QSPI, set DIP to QSPI mode, power on.

---

## 17. Adding Startup Scripts and User Files

### Creating an Application Recipe

```bash
petalinux-create -t apps --template install --name autostart --enable
```

### Autostart Recipe (autostart.bb)

Edit `project-spec/meta-user/recipes-apps/autostart/autostart.bb`:

```bitbake
#
# This file is the autostart recipe.
#

SUMMARY = "Simple autostart application"
SECTION = "PETALINUX/apps"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://autostart \
"

S = "${WORKDIR}"

inherit update-rc.d

INITSCRIPT_NAME = "autostart"
INITSCRIPT_PARAMS = "start 99 5 ."

do_install() {
    install -d ${D}${sysconfdir}/init.d
    install -m 0755 ${S}/autostart ${D}${sysconfdir}/init.d/autostart
}

RDEPENDS_${PN}_append += "bash"
```

### How It Works

- Copies the `autostart` script to `/etc/init.d/` with execute permissions (0755)
- Runs at boot with priority 99 in runlevel 5
- `RDEPENDS` declares dependency on bash

### Adding Files to SD Card

For ramdisk systems, you can also add files directly to the SD card. The startup script can reference files from the SD card mount point, and these survive system restarts (unlike ramdisk contents).

---

## 18. Cross-Compiling C Applications (Hello World)

### Using Vitis ARM Compiler

```bash
# Set environment
source /tools/Xilinx/Vitis/2020.1/settings64.sh

# Cross-compile
aarch64-linux-gnu-gcc -o helloworld main.c
```

### Using Vivado ARM Compiler

```bash
source /tools/Xilinx/Vivado/2020.1/settings64.sh
aarch64-linux-gnu-gcc -o gpio_test gpio_test.c
```

### Running on Board

1. Copy the compiled binary to SD card
2. Boot development board with Linux
3. Login (`root`/`root`)
4. Find the binary:
   ```bash
   find / -name helloworld
   ```
5. Execute:
   ```bash
   ./helloworld
   ```

---

## 19. GPIO Control Under Linux

### Linux GPIO Sysfs Interface

```c
#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include <unistd.h>

void led_ctl_init() {
    // Export GPIO pin
    int fd = open("/sys/class/gpio/export", O_WRONLY);
    write(fd, "<gpio_number>", strlen("<gpio_number>"));
    close(fd);

    // Set direction to output
    fd = open("/sys/class/gpio/gpio<N>/direction", O_WRONLY);
    write(fd, "out", 4);
    close(fd);
}

void led_ctl_on(int on) {
    int fd = open("/sys/class/gpio/gpio<N>/value", O_WRONLY);
    if (on) {
        write(fd, "1", 2);
    } else {
        write(fd, "0", 2);
    }
    close(fd);
}

int main() {
    led_ctl_init();
    printf("================start led ctrl==============\n");

    while(1) {
        led_ctl_on(1);
        printf("on\r\n");
        usleep(500000);

        led_ctl_on(0);
        printf("off\r\n");
        usleep(500000);
    }
    return 0;
}
```

The `led_ctl_init()` function exports the GPIO pin and initializes it as an output. The `led_ctl_on()` function controls the pin level.

---

## 20. Linux Register-Level Peripheral Access (mmap)

### Concept

Memory mapping (`mmap`) maps a kernel memory area to user space. This allows direct register access from user applications — useful for porting bare-metal peripheral code to Linux without writing a driver.

### Advantages Over read()/write()

- `read()` copies data twice (disk → kernel buffer → user space)
- `mmap()` copies data once (disk → user space via page fault)
- More efficient for large data transfers

### Usage Pattern

```c
#include <sys/mman.h>
#include <fcntl.h>
#include <unistd.h>

int fd = open("/dev/mem", O_RDWR | O_SYNC);
volatile void *base = mmap(NULL, size, PROT_READ | PROT_WRITE,
                           MAP_SHARED, fd, physical_address);

// Read/write registers
*(volatile uint32_t *)(base + offset) = value;
uint32_t val = *(volatile uint32_t *)(base + offset);

munmap((void *)base, size);
close(fd);
```

> **IMPORTANT**: Use `O_SYNC` when opening `/dev/mem` to ensure data is written to the peripheral device immediately (bypasses cache).

### Development Strategy

1. **First verify with Vitis bare-metal** — verify peripheral operation
2. **Port register addresses** from Vitis `xparameters.h` to Linux application
3. For peripherals and FPGA-side IPs, Vitis generates operation methods and addresses — reuse them

---

## 21. NVMe SSD Operation Under Linux

### Kernel Configuration

```bash
petalinux-config -c kernel
```

Navigate to `Device Drivers` → Enable **NVMe Support** (PCIe drivers loaded by default).

### Root Filesystem Tools

```bash
petalinux-config -c rootfs
```

Enable in `Filesystem Packages`:
- `base → util-linux` (partition tools)
- `base → e2fsprogs → e2fsprogs-mke2fs` (filesystem creation)

### SSD Operations On-Board

```bash
# Check SSD device
ls /dev/nvme*

# Partition SSD
fdisk /dev/nvme0n1
# n → p → defaults → wq

# Format partition
mkfs -t ext4 /dev/nvme0n1p1

# Mount
mkdir -p /run/media/nvme0n1p1
mount /dev/nvme0n1p1 /run/media/nvme0n1p1

# Speed tests
cd /run/media/nvme0n1p1

# Write test
time dd if=/dev/zero of=./testfile1 bs=100k count=1310
# ~202 MB/s write

# Read test (clear cache first)
echo 3 > /proc/sys/vm/drop_caches
time dd if=./testfile1 of=/dev/null bs=100k
# ~338 MB/s read

# Copy test
echo 3 > /proc/sys/vm/drop_caches
time dd if=./testfile1 of=./testfile2 bs=100k
# ~177 MB/s read+write
```

> **⚠ WARNING**: When using an SSD, do not touch the surface of the SSD to avoid electrostatic damage.

---

## 22. Qt and OpenCV Cross-Compilation Environment

### Rootfs Package Configuration

```bash
petalinux-config -c rootfs
```

Enable the following packages:
- **PetaLinux Package Groups → packagegroup-petalinux-v4lutils** — Linux video configuration tools (v4l)
- **PetaLinux Package Groups → packagegroup-petalinux-x11** — X11 library
- **Filesystem Packages → libs → libmali-xlnx** — GPU library

### SDK Build

```bash
# Must enable online compilation for SDK build
petalinux-build --sdk
```

### SDK Installation

```bash
cd <petalinux_project>/images/linux/
./sdk.sh -d ../../pfm/
```

---

## 23. OpenCV Edge Detection Application

### Preparation

1. Connect **DisplayPort** to a monitor
2. Plug in a **USB camera**
3. Boot development board, verify desktop displays on DP monitor

### Check Camera Device

```bash
ls /dev/video*
# Note your camera device number
```

### Environment Setup On-Board

```bash
# Set display
export DISPLAY=:0.0

# Start desktop
/etc/init.d/xserver-nodm start

# Adjust resolution (for 4K monitors)
xrandr --output DP-1 --mode 1920x1080

# Disable screen power management
xset s 0 0
xset dpms 0 0 0
```

### Edge Detection Algorithms Used

| Algorithm | Description | OpenCV Function |
|---|---|---|
| **Canny** | Optimal multi-level edge detection (low error, high positioning, minimal response) | `cv::Canny()` |
| **Sobel** | First-order differential operator (Gaussian smoothing + differentiation) | `cv::Sobel()` |
| **Laplacian** | Second-order differential operator (position-only edges, noise-sensitive) | `cv::Laplacian()` |

The application uses **three threads** to run each algorithm, fully utilizing ARM's quad-core A53.

---

## 24. OpenCV + Qt Face Detection

### Cascade Classifier

A cascade classifier concatenates N single-class classifiers. An object must pass ALL classifiers to be classified as positive (e.g., face). Face attributes: eyebrows, eyes, nose, mouth, U-shaped chin contour, etc.

---

## 25. Remote Debugging with GDB and QtCreator

### Overview

- **gdbserver** runs on the target board, monitors the debugged process
- **gdb** runs on the host (via QtCreator), communicates via network
- Developers control processes on the target board remotely

### QtCreator Device Configuration

1. **Tools → Options → Devices**
2. Click **Add** → Select **Generic Linux Device**
3. Configure:
   - **Host name/IP**: Board IP address (e.g., `192.168.1.45`)
   - **Username**: `root`
   - **Password**: `root`
4. Click **Next → Finish** — test connection

### Board IP Setup

```bash
# Check IP (DHCP)
ifconfig

# Manual IP assignment (if no DHCP)
ifconfig eth0 192.168.1.45 netmask 255.255.255.0
```

### Remote Run from QtCreator

1. Open project `.pro` file in QtCreator
2. Configure build kit with the cross-compiler
3. Click **Run** — QtCreator automatically:
   - Compiles the application
   - Deploys binary to board (to `/home/root/`)
   - Executes on board
   - Shows output in QtCreator console

### Remote Debugging

1. Set breakpoints in code
2. Click **Debug (F5)**
3. Program stops at breakpoints
4. Step through (F10/F11), inspect variables, registers
5. Press **F5** to continue

---

## 26. Vitis Acceleration Platform Creation

### Prerequisites

- Proficiency with Vivado and PetaLinux
- Recommended: Learn OpenCL and HLS first

### Vivado Hardware Platform Modifications

Starting from `ps_hello` project:

1. **Enable PL-to-PS interrupt**: PS-PL Configuration → Interrupt → PL to PS → IRQ0 = 1
2. **Add Clock Wizard IP**: Configure for multiple output clocks
3. **Add 3× Processor System Reset** IPs (one per clock)
4. **Enable Platform Interfaces**:
   - Window → Platform Interfaces
   - Enable `clk_out1`, `clk_out2`, `clk_out3`
   - Set `clk_out2` as default clock (ID=0, clk_out1 ID=1, clk_out3 ID=2)
5. **Add Interrupt Controller IP** (`axi_intc_0`)
   ```tcl
   set_property PFM.IRQ {intr {id 0 range 32}} [get_bd_cells /axi_intc_0]
   ```
6. **Modify AXI port types**: Set `S_AXI_HPC0_FPD` and `S_AXI_HPC1_FPD` memport to `S_AXI_HP`
7. **Enable AXI Interconnect ports**: M01_AXI through M08_AXI
8. **Validate, Generate, Export XSA** (Include bitstream if needed)

### PetaLinux for Acceleration

```bash
# Create project
petalinux-create -t project -n petalinux --template zynqMP

# Configure with acceleration XSA
petalinux-config --get-hw-description ../hardware/
# Set: SD card boot, EXT rootfs on /dev/mmcblk1p2
```

### Rootfs Configuration (user-rootfsconfig)

Edit `project-spec/meta-user/conf/user-rootfsconfig`:

```
#Note: Mention Each package in individual line
CONFIG_gpio-demo
CONFIG_peekpoke

#Packages for base XRT support:
CONFIG_packagegroup-petalinux-xrt
CONFIG_xrt-dev

#Packages for easy system management
CONFIG_dnf
CONFIG_e2fsprogs-resize2fs
CONFIG_parted

#Packages for Vitis-AI dependencies support:
CONFIG_packagegroup-petalinux-vitisai

#Packages for natively building Vitis AI applications:
CONFIG_packagegroup-petalinux-self-hosted
CONFIG_cmake
CONFIG_packagegroup-petalinux-vitisai-dev
CONFIG_opencl-clhpp-dev
CONFIG_opencl-headers-dev
CONFIG_packagegroup-petalinux-opencv
CONFIG_packagegroup-petalinux-opencv-dev

#Packages for GUI:
CONFIG_mesa-megadriver
CONFIG_packagegroup-petalinux-x11
CONFIG_packagegroup-petalinux-v4lutils
CONFIG_packagegroup-petalinux-matchbox
```

### Kernel Configuration

```bash
petalinux-config -c kernel
```
Remove all options in `CPU Power Management` (for acceleration stability).

### Build, SDK, and Platform Creation

```bash
# Build
petalinux-build

# Build SDK
petalinux-build --sdk

# Install SDK
cd images/linux/
./sdk.sh -d ../../pfm/

# Create pfm directories
mkdir -p pfm/image pfm/root

# Copy boot components to root/
cp images/linux/zynqmp_fsbl.elf pfm/root/fsbl.elf
cp images/linux/pmufw.elf pfm/root/
cp images/linux/bl31.elf pfm/root/
cp images/linux/u-boot.elf pfm/root/

# Copy image files
cp images/linux/boot.scr pfm/image/
cp images/linux/system.dtb pfm/image/

# Create linux.bif in root/
```

### Vitis Acceleration Platform

1. Open Vitis: `source /tools/Xilinx/Vitis/2020.1/settings64.sh && vitis -workspace wksp1`
2. Create **Platform Project** → select XSA → set OS to **Linux**
3. Configure: Bif file, Boot Components Directory (root/), Image directory (image/)
4. Build platform

### Testing Acceleration

1. Create application from **Hello World (HLS C/C++ kernel)** template
2. Set **Sysroot path** and **Kernel image** path
3. Build for **Hardware** target (needs ≥ 16GB VM memory)
4. Copy output to SD card FAT partition
5. Boot and run:
   ```bash
   cd /media/sd-mmcblk1p1
   export XILINX_XRT=/usr
   ./hello_world vadd.xclbin
   # "TEST PASSED" = success
   ```

> **NOTE**: If compilation errors about Y2K22, apply the `y2k22_patch-1.2.zip` patch.

---

## 27. Kernel and Rootfs Configuration Details

### Kernel Configuration Highlights

```bash
petalinux-config -c kernel
```

| Configuration | Path | Use Case |
|---|---|---|
| NVMe Support | Device Drivers → NVMe | SSD via M.2 PCIe |
| CPU Power Mgmt | CPU Power Management | Disable for acceleration |
| USB Gadget | Device Drivers → USB | USB device mode |
| V4L2 | Device Drivers → Media → Video4Linux | Camera support |

### Rootfs Configuration Highlights

```bash
petalinux-config -c rootfs
```

| Package | Path | Purpose |
|---|---|---|
| v4lutils | PetaLinux Package Groups | Video4Linux tools |
| x11 | PetaLinux Package Groups | Display server |
| libmali-xlnx | Filesystem Packages → libs | GPU acceleration |
| opencv | PetaLinux Package Groups | Computer vision |
| util-linux | Filesystem Packages → base | Partition tools |
| e2fsprogs | Filesystem Packages → base | Filesystem creation |
| XRT | PetaLinux Package Groups | Xilinx Runtime for acceleration |

---

## 28. Display and Camera Setup Under Linux

### DisplayPort Output

- Connected via PS-side Mini DisplayPort
- Factory system includes desktop environment (Matchbox WM)
- Resolution adjustable via `xrandr`:
  ```bash
  xrandr --output DP-1 --mode 1920x1080
  ```

### Disable Screen Power Management

```bash
xset s 0 0
xset dpms 0 0 0
```

### USB Camera

- Device appears as `/dev/video0` (or `/dev/video1`)
- Check with `ls /dev/video*`
- Set resolution in application: 640×480 typical
- Use V4L2 or OpenCV `VideoCapture` for capture

---

## 29. PetaLinux Cleanup and Troubleshooting

### Clean Build

```bash
petalinux-build -x mrproper -f
```

Use when:
- Various compile errors after modifying configurations
- Build is stuck and cannot proceed
- Switching between different hardware descriptions

### Common Issues

| Problem | Cause | Solution |
|---|---|---|
| Menuconfig display errors | Terminal window too small | Make Ubuntu and terminal **full screen** |
| "Network access disabled through BB_NO_NETWORK" | Offline mode enabled but packages needed | Uncheck "Enable BB NO NETWORK" or configure offline mirrors |
| Compile fails with missing packages | Online packages not available in offline mode | Configure sstate cache and downloads mirror paths |
| Boot fails — kernel panic | Wrong device node for root filesystem | Check `mmcblk0p2` vs `mmcblk1p2` — depends on Vivado project |
| SD card won't boot | Wrong filesystem format | FAT partition must be FAT32; EXT partition must be ext4 |
| Applications lost after reboot | Using ramdisk (INITRAMFS) rootfs | Switch to EXT4 rootfs or add apps to PetaLinux recipes |
| Long build times | Building everything from scratch | Use offline packages (sstate cache) |
| VM compile fails | Insufficient memory | Allocate ≥ 16GB RAM to VM (especially for acceleration) |
| `petalinux-config` hangs | Environment not sourced | Run `source /opt/pkg/petalinux/settings.sh` first |
| U-Boot stuck or wrong boot order | boot.scr offset mismatch | Verify offset = boot + bootenv + kernel partition sizes |
| eMMC not detected | Missing device tree entries | Add `&sdhci0` with `disable-wp` and `no-1-8-v` |
| USB not working | Missing device tree entry | Add `&dwc3_0` with `status = "okay"` and `dr_mode = "host"` |
| SSD not detected | NVMe driver not enabled | Enable in kernel config: Device Drivers → NVMe Support |

### MMC Device Numbering

| Vivado Project | eMMC | SD Card |
|---|---|---|
| `ps_hello` (standard) | mmcblk0 (mmc0) | mmcblk1 (mmc1) |
| Other projects | May vary | Check `ls /dev/mmcblk*` at runtime |

> **CRITICAL**: Always verify MMC numbering on your board. Wrong device node = boot failure.

---

## 30. Key Xilinx Documentation References

| Document | ID | Description |
|---|---|---|
| PetaLinux Tools Reference Guide | **UG1144** | Complete PetaLinux command reference |
| Zynq UltraScale+ MPSoC TRM | **UG1085** | Hardware technical reference |
| Embedded Design Tutorial | **UG1209** | Step-by-step embedded Linux tutorial |
| Vitis Unified Software Platform | **UG1393** | Vitis acceleration and application development |
| Bootgen User Guide | **UG1283** | Boot image generation |
| Device Tree Reference | — | Xilinx device tree generator documentation |
| ALINX Board Manual | — | AXU5EVB-P / AXU4EVB-P hardware manual |

### Useful Links

| Resource | URL |
|---|---|
| Xilinx PetaLinux Reference | https://www.xilinx.com/support/documentation/sw_manuals/xilinx2019_2/ug1144-petalinux-tools-reference-guide.pdf |
| Vitis Tutorials | https://github.com/Xilinx/Vitis-Tutorials/blob/2020.1/ |
| Xilinx Kernel Source | https://github.com/Xilinx/linux-xlnx |
| Xilinx U-Boot Source | https://github.com/Xilinx/u-boot-xlnx |

---

## APPENDIX A: Quick Command Reference

### PetaLinux Workflow

```bash
# 1. Environment
source /opt/pkg/petalinux/settings.sh

# 2. Create project
petalinux-create -t project -n petalinux --template zynqMP

# 3. Configure hardware
cd petalinux/
petalinux-config --get-hw-description ../hardware/

# 4. Configure components (as needed)
petalinux-config                    # System config
petalinux-config -c kernel          # Kernel
petalinux-config -c u-boot          # U-Boot
petalinux-config -c rootfs          # Root filesystem

# 5. Edit device tree
nano project-spec/meta-user/recipes-bsp/device-tree/files/system-user.dtsi

# 6. Build
petalinux-build

# 7. Package boot image
petalinux-package --boot --fsbl images/linux/zynqmp_fsbl.elf --u-boot --force

# 8. Clean (if needed)
petalinux-build -x mrproper -f
```

### Cross-Compilation

```bash
source /tools/Xilinx/Vitis/2020.1/settings64.sh
aarch64-linux-gnu-gcc -o app main.c
```

### SD Card Preparation

```bash
# FAT partition: boot files
cp BOOT.bin boot.scr image.ub /media/<user>/FAT/

# EXT4 partition: root filesystem
sudo tar -zxvf rootfs.tar.gz -C /media/<user>/EXT/
sudo sync
```

### On-Board Debugging

```bash
# Check devices
ls /dev/mmcblk*     # MMC devices
ls /dev/nvme*       # NVMe SSDs
ls /dev/video*      # Cameras
ifconfig            # Network

# Mount
mount /dev/mmcblk0p1 /mnt/
mount -t nfs -o nolock <host_ip>:/path /mnt/

# GPIO
echo <N> > /sys/class/gpio/export
echo out > /sys/class/gpio/gpio<N>/direction
echo 1 > /sys/class/gpio/gpio<N>/value
```

---

## APPENDIX B: PetaLinux Project Directory Structure

```
<petalinux_project>/
├── project-spec/
│   ├── meta-user/
│   │   ├── conf/
│   │   │   └── user-rootfsconfig       ← Custom package list
│   │   ├── recipes-bsp/
│   │   │   ├── device-tree/
│   │   │   │   └── files/
│   │   │   │       ├── system-user.dtsi ← Custom device tree (EDIT THIS)
│   │   │   │       └── pl-custom.dtsi   ← PL device tree
│   │   │   └── u-boot/
│   │   │       ├── files/
│   │   │       │   └── platform-top.h   ← U-Boot config
│   │   │       └── u-boot-zynq-scr.bbappend
│   │   ├── recipes-kernel/
│   │   │   └── linux/linux-xlnx/        ← Kernel config
│   │   └── recipes-apps/
│   │       └── <app_name>/              ← Custom app recipes
│   └── hw-description/                  ← Imported XSA data
├── components/
│   └── plnx_workspace/                  ← Build workspace
├── images/
│   └── linux/                           ← BUILD OUTPUT
│       ├── BOOT.bin
│       ├── image.ub
│       ├── boot.scr
│       ├── rootfs.tar.gz
│       ├── zynqmp_fsbl.elf
│       ├── pmufw.elf
│       ├── bl31.elf
│       ├── u-boot.elf
│       └── system.dtb
└── build/                               ← Build artifacts
```

---

> **Document Version**: 1.0
> **Last Updated**: 2026-07-07
> **Sources**: ALINX PetaLinux Tutorial Documentation (`Adsız doküman (2).md`), ALINX AXU5EVB-P User Manual, Related-Repos project files
> **Note**: Feishu wiki URLs were inaccessible. PDF file (`Adsız doküman (1).pdf`) could not be parsed directly but content overlaps with the markdown source.


## Vitis/sub-docs/Adsız doküman.pdf


We promise that this tutorial is not a permanent and unchanging document. We will continuously revise and optimize the tutorial based on everyone's feedback and actual development experience. 
Preparation work and precautions
Software environment
Software Development Environment based on Vivado 2020.1 


Hardware environment






Development board model





Chip model


AXU4EV-P



Xczu4ev-sfvc784-1-i



AXU5EV-P


azu5ev-sfvc784-1-i






Batch Download QSPI Flash
All project directories have a bootimage folder, which stores the corresponding BOOT.bin file. You can copy this file to the Vitis_image_download folder and overwrite the original BOOT.bin. You can also put BOOT.bin on the SD card to start the verification function vitis_image_download folder under the course_s2 directory, enter the folder, right-click program_qspi bat, open edit

Change the program_flash path to your own software installation path, save and close. Double-click program_qspi to download BOOT. BIN to QSPI FLASH. It is recommended to download in JTAG mode. You can also use the SD card boot
method to copy the BOOT.bin file to the SD to boot. Batch build Vitis project
Due to the large space occupied by the Vitis project after compilation, in order to save everyone's valuable time, we provide batch processing tcl scripts for the Vitis project.

There is a vitis folder under each project, which contains the hardware description file xx.xsa and the script for automatically creating the project  All you need to do is right-click and edit the build_vitis .bat file in the auto_create_vitis folder (Note: the source file of the vitis program that does not use the template is in the folder in the vitisauto_create_vitissrc) Replace the xsct.bat path in the yellow box with your own installation path, which is xx\ Vitis\ 2020.1\ bin\ xsct.bat

After saving, double-click build_vitis bat to create the project  Compile finished, press any key to exit
Open the Vitis software, select the project path, and launch. After opening, close the Welcom interface Project can be used 
Starting from this chapter, FPGA engineers and software development engineers will collaborate to implement it.

 The previous experiments were all conducted on the PL side, which shows no difference from the ordinary FPGA development process. The main advantage of ZYNQ is the reasonable combination of FPGA and ARM, which puts higher requirements on developers. Starting from this chapter, we will use ARM, which is what we call PS. In this chapter, we will use a simple serial port printing to experience the characteristics of Vivado Vitis and PS side. The previous experiments are all things that FPGA engineers should do. Starting from this chapter, there is division of labor. FPGA engineers are responsible for building the Vivado project and providing hardware to software developers, who can then develop applications based on this. Good division of labor is also beneficial for project progress. If software developers want to do everything, they may need to spend a lot of time and energy learning about FPGA knowledge. It is a painful process to switch from software thinking to hardware thinking. If it is purely for learning and there is time, it is another matter. Professional people doing professional things is a good choice.
1.
Hardware introduction

We can see from the schematic that the ZYNQ chip is divided into PL and PS. The IO allocation on the PS side is relatively fixed and cannot be arbitrarily allocated. Moreover, there is no need to allocate pins in the Vivado software. Although this experiment only uses PS, a Vivado project needs to be established to configure PS pins. Although the ARM on the PS side is hardcore, the ARM hardcore needs to be added to the project in ZYNQ before it can be used. The previous chapters introduced the code form of the project, and this chapter begins to introduce the graphical way to establish the project in ZYNQ.
Job responsibilities of FPGA engineer
The following introduces the responsibilities of FPGA engineers.
2.
Vivado Project Establishment
1. Create a project named "ps_hello", the establishment process will not be repeated, refer to "PL's" Hello World "LED experiment".
2. Click "Create Block Design" to create a Block design, which is a graphical design

3. "Design name" is not modified here, keep the default "design_1", you can modify it as needed, but the name should be as short as possible, otherwise there will be problems with compiling under Windows.
4. Click the "Add IP" shortcut icon
5. Search for "zynq", double-click "Zynq UltraScale + MPSoC" in the search results list.
6. Double-click the ZYNQ core in the Block diagram and configure the relevant parameters

7. The first interface that appears is the architecture diagram of ZYNQ hardcore, which can be clearly seen. You can refer to the ug1085 document for a detailed introduction to ZYNQ. The green part in the figure is the configurable module, which can be clicked to enter the corresponding editing interface. Of course, you can also enter the editing in the left window. Below, the functions of each window are introduced one by one.

2.1
Low Speed Configuration
1. In the I/O Configuration window, configure the voltages of BANK0~ BANK2 as LVCMOS18 and BANK3 as LVCMOS33. First, configure the Low Speed pin, check QSPI, set it to "Single" mode, set the Data Mode to "x4", and check Feedback Clk.
2. Check SD 0 to configure eMMC. Select MIO13.. 22, select eMMC for Slot Type, set Data Transfer Mode to 8Bit, check Reset, and select MIO23.
3. Check SD 1 to configure SD card. Select MIO 46.. 51, Slot Type select SD 2.0, Data Transfer Mode select 4Bit, check CD to detect SD card insertion, select MIO45
4. Check CAN 0, select MIO 38.. 39, check CAN 1, select MIO 32.. 33
5. Check I2C 1, I2C for EEPROM, etc., select MIO 24.. 25
6. Check serial port UART 0, select MIO 42.. 43, check GPIO1 MIO
7. Check TTC0~ TTC 3

2.2
High Speed Configuration
1. For the High Speed section, first configure the PS side Ethernet, check GEM 3, select MIO 64.. 75, check MDIO 3, select MIO 76.. 77.
2.2
High Speed Configuration
1. For the High Speed section, first configure the PS side Ethernet, check GEM 3, select MIO 64.. 75, check MDIO 3, select MIO 76.. 77.
2. Check USB 0, select MIO 52.. 63, check USB 3.0, select GT Lane1 USB Reset Select MIO 31 3. Check PCIe
4. Click on Switch To Advanced Mode, select PCIe Configuration, modify the following parameters, and configure it to ROOT mode

5. Return to I/O Configuration, reset and select MIO 37; check Display Port, select MIO 27.. 30, and select Dual Higher for Lane Selection. At this point, the I/O part is configured 
2.3 Clock configuration
 1.
In the Clock Configuration interface, the Input Clocks window configures the reference clock, where the reference clock PSS_REF_CLOCK for ARM defaults to 33.333MHz; PCIe selects Ref Clk0, 100MHz; Display Port selects Ref Clk2, 27MHz; USB0 selects Ref Clk1, 26MHz.

2. In the Output Clocks window, if it is not IOPLL, change it to IOPLL to maintain consistency and use the same PLL.

3. PL's clock remains default, which is the clock provided to the PL-side logic.
4. Full Power section, others remain default, change DP_VIDEO to VPLL, DP_AUDIO and DP_STC to RPLL.
Modify the bottom Interconnect as follows Other parts remain default, so the clock configuration is complete. 
2.4 DDR configuration
In the DDR Configuration window, Load DDR Presets select "DDR4_MICRON_MT40A256M16GE_083E"
Modify the parameters as follows Leave the others as default, click OK, the configuration is complete, and connect the clock as follows: 8. Select Block Design, right-click "Create HDL Wrapper...", create a Verilog or VHDL file, and generate an HDL top-level file for Block Design. 9.

Keep the default options and click "OK". 10. Expand the design and you can see that PS is used as a regular IP. 
11. Select the block design, right-click on "Generate Output Products", this step will generate the output file of the block, including IP, instantiated templates, RTL source files, XDC constraints, third-party comprehensive source files, etc. For subsequent operations.
12. Click "Generate"
13. Export hardware information in the menu bar "File - > Export - > Export Hardware...", which includes configuration information for the PS side.  14. Select Fixed in the pop-up window and click Next.

15. Click "OK" in the pop-up dialog box. Since the experiment only uses the PS serial port and does not require PL participation, there is no enable to not select "Include bitstream". Click Next
16. You can modify the export name and export path. By default, it is located in the vivado project directory. This file can be placed in a suitable location according to your needs. It does not have to be placed under the vivado project. Vivado and vitis software are independent. Here we choose to leave the default unchanged. Click Next.
Click Finish At this point, you can see the xsa file in the project directory. This file contains information about the Vivado hardware design and can be used by software developers. At this point, the work of the FPGA engineer comes to an end.
Job responsibilities of software engineers
The Vitis project directory is "ps_hello/vitis"
The following is the content that software engineers are responsible for.
3.
Debugging Vitis

3.1
Create Application Project
1. Create a new folder and copy the xx.xsa file exported from vivado.
2. Vitis is an independent software that can be opened by double-clicking the Vitis software
You can also open the Vitis software by selecting ToolsLaunch Vitis in the Vivado software Select the newly created folder and click "Launch". 3.
After starting Vitis, the interface is as follows. Click "Create Application Project". This option will generate the APP project and Platfrom project. The Platform project is similar to the previous version of the hardware platform, including relevant files for hardware support and BSP.
4. The first page is the introduction page, skip directly and click Next.
5. Select "Create a new platform from hardware (XSA) " and select "Browse".
Select the previously generated xsa and click Open. 6.

The Generate boot components option at the bottom, if checked, the software will automatically generate the fsbl project. We usually choose to check it by default. 7. Fill in the APP project name, click on the box to select the corresponding processor, we keep the default here

8. In this interface, you can modify the Domain name, select the operating system, ARM architecture, etc. Here, the default is maintained, and the operating system is selected as standalone, which means bare metal.
9. Select the "Hellow World" template and click "Finish" to complete
10. After completion, you can see that two projects have been generated, one is the hardware platform project, which is the Platfrom project mentioned earlier, and the other is the APP project
11.

After expanding the Platform project, you can see that it contains the BSP project and the zynq_fsbl project (this project is the result of selecting Generate boot components). Double-click platform.spr to see the corresponding BSP project generated by the Platform, where you can configure the BSP. Software developers are more clear that BSP means Board Support Package, which contains the driver files needed for development and is used for application development. You can see that there are multiple BSPs under the Platform, which is different from the previous SDK software. zynqmp_fsbl is the BSP of fsbl, and domain_psu_cortexa53_0 is the BSP of the APP project. You can also add BSP in the Platform, which will be discussed in future routines. 12. Click on BSP to see the peripheral drivers provided by the project. Documentation is the documentation for the drivers provided by xilinx, and Import Examples is the example project provided by xilinx to speed up learning.

13. Select the APP project, right-click Build Project, or click the "Hammer" button in the menu bar to compile the project.

13. Select the APP project, right-click Build Project, or click the "Hammer" button in the menu bar to compile the project.
Compile finished, generate elf file15. Connect JTAG cable to development board, UART USB cable to PC
16. Using PuTTY software as a serial port end point debugging tool, PuTTY is a small software that does not require installation 
17. Select Serial, fill in COM3 for Serial line, fill in 115200 for Speed, fill in the COM3 string slogan according to the display in Facility Management, click "Open".

18. Before powering on, it is best to set the startup mode of the development board to JTAG mode and unplug it to the "ON" position
19.

Power on the development board and prepare to run the program. The development board comes with the program when it leaves the factory. Here, you can select the JTAG mode for the running mode , and then power it back on . Select "hello", right-click, and you can see many options. This experiment will use "Run as" here, which means to run the program. There are many options in "Run as". Select the first "Launch on Hardware (Single Application Debug) " and use system debugging to run the program directly.
20. At this time, by observing the serial port software, you can see the output "Hello World".
21. To ensure reliable debugging of the system, it is best to right-click "Run As - > Run Configuration..."
22. We can take a look at the configuration inside. Reset entire system is selected by default, which is different from previous SDK software. If there is also PL design in the system, "Program FPGA" must also be selected. 23. In addition to "Run As", you can also "Debug As", which allows you to set breakpoints and run step by step

2 4.
Enter Debug mode 25.
Like other C language development IDEs, it can be run step by step, set breakpoints, etc
26. You can switch IDE mode in the upper right corner.
4.
Solidification procedure
Ordinary FPGAs can generally be started from flash or passively loaded. The startup of ZYNQ is dominated by ARM, including the loading of FPGA programs. The startup of ZYNQ MPSoC generally consists of three steps, which are also introduced in UG1085. Pre-configuration satge: The preloading phase is controlled by the PMU and executes the code setting system in the PMU ROM. The PMU handles all reset and wake-up processes. Configuration stage: The next step is the most important one. After BootRom (part of the CSU ROM code) transfers FSBL to OCM, the processor starts executing FSBL code. FSBL mainly has the following functions:

� Initialize PS side configuration, MIO, PLL, DDR, QSPI, SD, etc
� If there is a PL-side program, load the PL-side bitstream.
� Move user programs to DDR and jump to execution  After FSBL starts executing, the CSU ROM code enters the post-configuration stage, responsible for system intervention response. CSU provides continuous hardware support for verifying file correctness, loading PL through PCAP, storing and managing security keys, decryption, etc.
4.1
Generate FSBL
FSBL is a secondary bootstrap program that completes MIO allocation, clock, PLL, DDR controller initialization, SD, QSPI controller initialization, searches for bitstream configuration FPGA through startup mode, then searches for user programs to load into DDR, and finally hands over to the application program for execution. 
1.

Since the Generate boot components option was selected when creating a new one, the Platform has imported the fsbl project and generated the corresponding elf file.
2. Modify the debug macro definition FSBL_DEBUG_INFO_VAL, you can output some status information of FSBL at startup, which is conducive to debugging, but it will lead to a longer startup time. Save the file. You can take a look at the files of many peripherals in fsbl, including psu_init, qspi, sd, etc. You can read the code carefully. Of course, this fsbl template can also be modified. As for how to modify it according to your own needs. 
3. Rebuild Project
4. Next, we can click on the system of the APP project, right-click and select Build project.
5. At this time, an additional Debug folder will appear, and the corresponding BOOT. BIN will be generated.
6. Another method is to right-click on the system of the APP project and select Creat Boot Image. In the pop-up window, you can see the generated BIF file path. The BIF

file is the configuration file for generating BOOT files, and there is also the generated BOOT.bin file path. The BOOT.bin file is the startup file we need, which can be placed on an SD card for startup or burned to QSPI Flash.
7. There are files to be synthesized in the Boot image partitions list. The first file must be the bootloader file, which is the fsbl.elf file generated above. The second file is the FPGA configuration file bitstream, which does not need to be added in this experiment because there is no bitstream for FPGA. The third file is the application program, which is hello.elf in this experiment. Since there is no bitstream, only the bootloader and application program will be added in this experiment. Click Create Image to generate.
8. The BOOT.bin file can be found in the generated directory
4.2
SD card boot test
1. Format the SD card, it can only be formatted as FAT32 format, other formats cannot be started
2.

Put the BOOT.bin file in the root directory 3. SD card inserted into the SD card slot of the development board 4. Adjust the startup mode to SD card startup 5. Open the serial port software, power on, and you can see the printing information. The red box is the FSBL startup information, and the yellow arrow part is the executed application helloworld.
4.3
QSPI startup test
1. Vitis menu Xilinx - > Program Flash
2. Select the latest Hardware Platform, select the BOOT.bin file to be burned for the Image FIle file, and select fsbl.elf for the FSBL file. Select Verify after flash and verify the flash after burning is complete.


3. Click Program and wait for the burning to complete
4. Set the startup mode to QSPI, restart, and you can see the same startup effect as SD in the serial port software.
4.4
Burning QSPI under Vivado
1. Select the device under HARDWARE MANGER, right-click Add Configuration Memory Device.
2. Select Try Micron, select qspi as the type, x4-single as the width, and 256 as the Density. When wt25qu256 appears, select the model with the red box.
3. Right-click and select the programming file
4.

Select the file and fsbl file to burn, and you can burn. If the burning is not in JTAG startup mode, the software will give a warning, so it is recommended to set the QSPI to JTAG startup mode when burning
4.5 Quickly burn QSPI using batch files.
 1.
Create a new program_qspi .txt text file with the extension changed to bat, fill in the content as follows,
E:\ XilinxVitis\ Vitis\ 2020.1\ bin\ program_flash is our tool path, modify it appropriately according to the installation path, -f is the file to be burned, -fsbl is the fsbl file to be burned, and -verify is the verification option.



allE:\XilinxVitis\Vitis\2020.1\bin\program_flash -f BOOT.bin -offset 0 -flash_type qspi-x4-single
fsbl fsbl.elf -verify
ause

 2. Put the BOOT.bin, fsbl, and bat files to be burned together 
3. After plugging in the JTAG cable and powering it on, double-click the bat file to burn the flash.
 

If you want to generate a BOOT. BIN file, you can choose system to compile. In this case, both elf and BOOT. BIN will be generated. I suffered losses when I first used it. Every time I compile, I choose system. As a result, I have to wait for BOOT. BIN to be generated every time, which wastes time. Everyone can pay attention.
 
7. Summary of this chapter
   6. Click on platform.spr and click on BSP  

7. Find the RTC driver and click Import Examples
  8. Very lucky, there is an example of interruption. How do you know this example is an example of interruption? It is guessed through "intr", so basic skills are very important, otherwise you won't even know how to find routines. 
   2. The base address, device ID, interrupt, etc. of each peripheral are defined in the xparameters.h Header File

  For example, the DEVICE_ID macro definition in the program is found in this file.   3. In the libsrc folder, there are definitions of peripheral functions and instructions for use   7. Click Run   8. The program runs to this point, and then sets a breakpoint at the RecvFrame

  9. Click Run again to see the data generated by TxFrame.   10. Press F6 to run step by step, and you can see the data received by RxFrame, thus completing the data transmission and reception from CAN0 to CAN1.
3.
On board verification
1. First, you need to save a 1920 * 1080 pixel, 24-bit BMP file to the SD card, with the file name 1.bmp (the file is in the project directory). If the development board is powered off, insert the SD card into the card holder.


 
2. Connect the development board to the DP monitor, then power it on. After running the download program, we can display the image of the 1.bmp file stored in the SD card on the DP monitor. 
   3. Afterwards, you can power off the development board, insert the SD card into the computer, and you can see more CAT. BMP.  
Part 9: Lwip for PS-side Ethernet

The vivado project directory is "ps_hello/vivado" The vitis project directory is "ps_net/vitis"
   4. When a character is input, the development board returns the same character  
3.
Experimental summary
Through experiments, we have a deeper understanding of the development of Vitis programs. This experiment simply explains how to create an LWIP application, which can complete protocols such as UDP and TCP. In subsequent tutorials, we will provide specific applications based on Ethernet, such as ADC collecting data and sending it

through Ethernet, and camera data being sent to the host computer for display through Ethernet.
Part 10: Network remote update QSPI on PS side
The vivado project directory is "ps_hello/vivado" The vitis project directory is "ps_remote/vitis"
 In actual work, there may be product upgrade issues. If you follow the program burning method, you may need to open the product shell, which is undoubtedly necessary. This chapter introduces a method of remotely updating FLASH programs through the network, including two methods: UDP and TCP.
Job responsibilities of software engineers
The following is the content that software engineers are responsible for. Note: Due to the use of lwip, it is necessary to modify the lwip library before conducting this experiment. Please refer to the chapter "Lwip for PS Ethernet Use".


7.

Add some content to emio.xdc, the port name must be consistent with the top-level file port.


#################Compress Bitstream############################ et_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
et_property IOSTANDARD LVCMOS33 [get_ports {emio_tri_io[*]}] pl led et_property PACKAGE_PIN AE15 [get_ports {emio_tri_io[0]}] pl key et_property PACKAGE_PIN AE14 [get_ports {emio_tri_io[1]}]


 8. Generate bit file    9. Although the logic of the PL end is not used, the pins of the PL end are used. Therefore, when exporting hardware, select "Include bitstream". 
 

 3.
Serial port print information  

4.
Summary of this chapter
This chapter introduces the use of two RS485 circuits on the board for loop testing. You can expand the functionality for testing based on this.
Part 15: PL-side Ethernet experiment
The experimental Vivado project directory is "pl_net/vivado". The experimental vitis project directory is "pl_net/vitis".


The usage of Ethernet on the PS side was introduced earlier, and this chapter introduces Ethernet on the PL side.
Job responsibilities of FPGA engineer
The following is the content that FPGA engineers are responsible for.
1.
Hardware environment setup
1. Configure interrupts and AXI HP0 FPDs based on "ps_hello"



include "xil_printf.h" include "ax_pwm.h" include "xil_io.h" include "xparameters.h" include "sleep.h"
nsignedint duty;
nt main()

nit_platform();
rint("Hello World\n\r");
pwm out period = frequency(pwm_out) * (2^N) / frequency(clk);
AX_PWM_mWriteReg(XPAR_AX_PWM_0_S00_AXI_BASEADDR, AX_PWM_S00_AXI_SLV_REG0_OFFSET,17179);//200hz
duty = (2^N) * (1 - (duty cycle)) - 1
while(1){ or(duty =0x8fffffff; duty <0xffffffff; duty = duty +100000){ AX_PWM_mWriteReg(XPAR_AX_PWM_0_S00_AXI_BASEADDR, AX_PWM_S00_AXI_SLV_REG1_OFFSET, duty);

sleep(100);
leanup_platform(); eturn0;

 4. By running the code, we can see that PLLED presents a breathing light effect.  5.

Let's check the registers through debugging 
     2. Add reset module for reset 
You can see that the newly added IP appears.  

 4.
Connect the BRAM_PORTA of AXI BRAM Controller to PORTA of BRAM, connect the BRAM_PORT of pl_bram_ctrl to PORTB of BRAM. Connect the interrupt signal intr of pl_bram_ctrl module to the interrupt port of ZYNQ. And click Auto Connect
  5. Select the BRAM address size in the Address Editor, such as setting 4K space, to query the BRAM space to 1K depth.  
1.1 Block Design Adding Logic Analyzer Method
6. Another way to add a logic analyzer is to select BRAM_PORT bus and intr interrupt, right-click and select Debug.


3. After adding, you can see the IP of the dynamic clock.
  4. Add a dynamic clock controller, the main function of this module is to configure different clock outputs according to different resolutions, essentially calling the phase-locked loop, but it should be noted that the reference clock of this module must be set to 100MHz   And connect the clock  

2. Add mipi_csi2_rx_subsystem module for receiving and parsing MIPI data, and convert it to axi-stream interface. The configuration is as follows: select RAW10 for data format, select 2 lanes, and configure Line Rate to 1000Mbps, which refers to the maximum supported rate. You can also fill in according to your own needs, with a range of 80-2500. The default configuration of Pixels Per Clock is 1, which means 1 pixel per cycle.
ob responsibilities of software engineers
The following is the content that software engineers are responsible for. Note: Due to the use of lwip, it is necessary to modify the lwip library before conducting this experiment. Please refer to the chapter "Lwip for PS Ethernet Use". 
2.
Vitis program development
2.1 PL-side Ethernet test

The establishment method of Vitis project is the same as that of PS side, and the process will not be repeated. The lwip library has been modified earlier. The testing method has been introduced earlier.
  And the dual-core agreement has a shared address, so that parameters can be passed.   3. In the while loop, it is determined that there is a software interrupt from CPU1, and the string in CPU1 Memory Space is printed out.  
1.4 CPU1 Program Introduction
1.

There is also a character array in the CPU1 program, and Cpu0Data points to the string address of the CPU0 Memory Space.
  2. In the PLGpioSetup function, the key interrupt number needs to be bound to CPU1. Other parts are similar to CPU0 and will not be repeated.  
2. On board verification
 
1.1 Block Design Adding Logic Analyzer Method

6. Another way to add a logic analyzer is to select BRAM_PORT bus and intr interrupt, right-click and select Debug.
   7. You can see that there are small insects on the bus. Click Run Connection Automation to automatically connect   5. Export pin   

6. Save the design, press F6 to check the design, and Generate Output Products...
  7. Since the software automatically binds the pins in reverse order from the hardware design, it is necessary to modify the pin binding. Expand the red box below in IP Sources
      4.

Save Designs and Generate Output Products 
  If you want to add a custom IP to the IP library, click IP Catalog and right-click Add Repository in Vivado Repository.   Find the folder where the custom IP is located and click Select.   Jump out of the window, select IP, and click OK.

