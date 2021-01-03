# ao486 port for MiSTer by Sorgelig.

Core was greatly reworked with many new features and performance added.

## Features:
* 486DX33 performance (no-FPU).
* 256MB RAM
* SVGA with up to 1280x1024@256, 1024x768@64K, 640x480@16M resolutions
* Sound Blaster 16 (DSP v4.05) and Sound Blaster Pro (DSP v3.02) with OPL3 and C/MS
* High speed UART (3Mbps) internet connection
* MIDI port (dumb and fake-smart modes)
* Extrnal MIDI device support (MT32-pi and generic MIDI)
* 4 HDDs with up to 137GB each
* 2 CD-ROMs
* Shared folder support

## How to install

* Copy ao486.rbf to root of SD card
* Create /ao486 directory on SD card and copy [boot0.rom](https://github.com/MiSTer-devel/ao486_MiSTer/blob/master/releases/bios/boot0.rom?raw=true), [boot1.rom](https://github.com/MiSTer-devel/ao486_MiSTer/blob/master/releases/bios/boot1.rom?raw=true) there.
* For floppy: copy desired floppy raw image with extension **img** to ao486 directory.
* For HDD: create an empty file of desired size with extension **vhd** in ao486 directory (or prepare .vhd file separately with any tool supporting .vhd or hard disk .img files and copy to /ao486 folder)
* Boot ao486 and in OSD choose desired floppy, hdd and boot order
* Save settings and press "Reset and apply HDD"

HDD image is a raw image with MBR. It can be opened in Windows/Linux by many applications,
so it's possible to prepare a HDD in windows/linux (in most cases you need to work with .img files, then just rename it to .vhd extension)

### Sound Blaster
Default config: A220 I5 D1 H5 T6
Supported alternative configs with IRQ 7 or 10 and/or no-HDMA (16bit DMA through 8bit DMA).
Standard SB16 config (diagnose) can be used to set alternative settings, or included sbctl util. Windows driver manages alternative settings by itself when manually configured.

Current implementation supports SoundBlaster Pro specific commands (not available in SB16 originally) as well. Compatible config for SBPro is "A220 I5 D1 T4" in case if some game will require it.

ASP/CSP is not implemented, but some specific commands with dummy replies are added to let Windows driver work.

Simple volume (only master volume) is implemented in mixer so windows volume can be used in additional to standard MiSTer volume control.

### C/MS Audio
C/MS (dual SAA1099) can be enabled in OSD. When enabled it prevents OPL2/3 access on ports 220-223. OPL2/3 still can be accessed on ports 388-38B (AdLib).

### OPL2/3 (Adlib)
OPL2/3 can be accessed as a part of Sound Blaster board at ports 220-223 (if C/MS is not enabled) and 228-229(OPL2 only). However it's recommended to use AdLib ports 388-38B instead.

### MIDI settings:
* address: 330h
* IRQ: 9

### MT32-pi support:
MT32-pi connection is supported through USER I/O port. MT32-pi is automatically detected.
Supported straight and crossed RX<->TX cables.
MT32-pi config and settings are [here](https://github.com/dwhinham/mt32-pi/wiki/MiSTer-FPGA-user-port-connection)
MT32-pi interface board is on [Hardware repository](https://github.com/MiSTer-devel/Hardware_MiSTer)
LCD and buttons are for convenience but not required. Basically only USER I/O connector is required, so can be assembled without interface board.

### Drivers
Windows 9x drivers for video and modem are [here](https://github.com/MiSTer-devel/ao486_MiSTer/blob/master/releases/drv)

### Note:
* Press **WIN+F12** to access **OSD on ao486 core**. F12 alone acts as generic F12 PC key.

### CD-ROM
Currently only data portion of CD is supported. Best image format is ISO, but BIN/CUE format still can be mounted. You just need to mount bin file or if it's multi-file image, then usually first track is data which you need to mount.

IDE 1-0 has special function - it's a placeholder for CD. So you can hot-swap CD images in this drive. Regardless special function this drive also supports HDD images. Once HDD image is loaded upon reboot this drive loses CD placeholder feature.

### Hard Disk and CD-ROM in Windows
Core supports up to 4 HDD images up to 137GB each. Up to 2 CD-ROMs are supported.

Currently due to unknown source of issue Windows works with IDE devices through BIOS. Most likely some BIOS function doesn't supply correct info for Windows drivers.
It doesn't prevent windows from working but you need to keep in mind some specifics:
* Hard disks mounted on Primary IDE (0-0/0-1) need no attentions. They simply work.
* Driver for Secondary IDE (1-0/1-1) have yellow mark. It's recommended to delete this device from device list - it's not used anyway but will be installed every time you start automatic HW detection procedure.
* CD-ROM needs oakcdrom.sys and mscdex.exe added to config.sys and autoexec.bat respectively (you may find them on bootable Window98 CD). Windows will use it to access CD-ROM.
* CD-ROM autostart won't be automatically triggered (because work through BIOS). After replacing image file in CD-ROM you need to refresh the folder with drives (F5) and icon of CD will be changed if provided by image. Autostart will be triggered when you click on CD icon.

Original core [repository](https://github.com/alfikpl/ao486)
