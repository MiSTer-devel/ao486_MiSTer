NE2KTEST - NE2000 bring-up probe for the ao486 core
===================================================

Hardware test T3.4 of NE2000_AO486_PLAN.md.

Everything it does is local to the card: no HPS transport, no packet driver,
nothing reaches the wire. That is the point - it isolates "is the card wired
into ao486 correctly" from "does networking work", so a bring-up failure has
one meaning instead of five.

  NE2KTEST [base]        base in hex, default 300

Checks, in the order a bring-up needs them:

  reset port      read base+0x18, ISR.RST must set
  card present    RTL8019 ID at base+0x0A / +0x0B reads 50 70
  registers       BNRY write/read-back
  station PROM    remote DMA read from 0x0000, prints the MAC
  packet RAM      8 words written and read back through the 16-bit data port
                  at base+0x10, byte order checked (a swapped result is named
                  explicitly rather than left as a mystery)
  debug aperture  base+0x20..0x26, the core's transport state

Enable Network in the OSD first (Hardware page). Default IRQ is 11.

Two implementations of the same probe:

  NE2KTEST.ASM   16-bit DOS .COM, freestanding (no libc, no runtime).
                 Build:  nasm -f bin -o NE2KTEST.COM NE2KTEST.ASM
                 This is the one that is built and shipped.

  NE2KTEST.C     the same checks in C, for Open Watcom:  wmake
                 Kept because it is easier to read and extend than the asm.

Getting it into the guest
-------------------------

The DOS guest cannot reach the SD card, so the .COM is delivered on a floppy
image built by mkfloppy.py (a small FAT12 writer - no mtools needed):

  python3 mkfloppy.py NE2KTEST.img NE2KTEST.COM

Copy the image to /media/fat/games/AO486/ on the MiSTer, mount it in the OSD
as Floppy A:, then run A:\NE2KTEST.

The .COM also tests the 16-bit remote-DMA data port, which DEBUG.EXE cannot
reach - its 'o' command is byte-only.

Expected before Phase 4: everything passes except that the debug aperture shows
HPS comm status 0x00 -- the shared-memory transport is not connected yet, so
the card works locally but no frames move.
