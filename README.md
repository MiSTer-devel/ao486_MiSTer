# ao486 port for MiSTer by Sorgelig.

Core was greatly reworked with many new features and performance added.

## Features:
* 486DX33 performance (no-FPU).
* 256MB RAM
* SVGA with up to 1280x1024@256, 1024x768@64K, 640x480@16M resolutions
* Sound Blaster 16 (DSP v4.05) and Sound Blaster Pro (DSP v3.02) with OPL3 and C/MS
* High speed UART (3Mbps) internet connection
* MIDI port (dumb and fake-smart modes)
* Dual HDD with up to 8GB each
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

### Drivers
Windows 9x drivers for video and modem are [here](https://github.com/MiSTer-devel/ao486_MiSTer/blob/master/releases/drv)

### Note:
* Press **WIN+F12** to access **OSD on ao486 core**. F12 alone acts as generic F12 PC key.

### Known issues
* FDD doesn't work under Win9x. To fix it simply delete floppy device from device manager and reboot.
Windows will still provide flopy access through BIOS in compatibility mode.

Original core [repository](https://github.com/alfikpl/ao486)
