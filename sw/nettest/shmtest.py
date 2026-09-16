#!/usr/bin/env python3
"""
shmtest.py - HPS side of the ao486 NE2000 shared-window bring-up (Phase 1).

Runs on the MiSTer (as root). Maps the reserved DDR window the FPGA mailbox
targets and lets you read/write it, so the Phase 1 gate can be answered:

    do the FPGA and the HPS address the same physical bytes?

The window is safe to touch: the kernel is booted with `mem=511M` and
`memmap=513M$511M`, so 0x1FF00000 is the first byte after System RAM and is
reserved from Linux. Verify before trusting this:

    cat /proc/cmdline ; grep 'System RAM' /proc/iomem

BYTE ORDER - measured on hardware 2026-07-29, do not guess at this.
A core-logical 16-bit value lands in the window LOW BYTE FIRST:

    window[X]   = value[7:0]
    window[X+1] = value[15:8]

i.e. plain little-endian. Confirmed by reading back the core's own published
ENABLED flag (logical 0x2000 -> window[0x1001] = 0x20).

An earlier version of this tool used the opposite (big-endian) convention. It
appeared to work because the shm probe passes DMA data through unswapped while
the core applies hps_u16_from_dma, so probe round-trips agreed with it and the
core did not. The visible symptom was the core never setting
ETH_STATUS_FPGA_SIGNATURE: it was reading the signature byte-swapped.

Usage:
    shmtest.py dump [offset] [length]     hexdump raw window bytes
    shmtest.py peek <offset>              read one FPGA 16-bit value
    shmtest.py poke <offset> <value>      write one FPGA 16-bit value
    shmtest.py sign                       write signature + bump heartbeat
    shmtest.py watch [seconds]            bump heartbeat, report window changes
    shmtest.py clear                      zero the whole window
    shmtest.py mac [iface]                derive+publish the NE2000 MAC
                                          (default eth0; use eth1 if bridging that)

Offsets and values are hex.
"""

import mmap
import os
import sys
import time

SHM_BASE = 0x1FF00000
SHM_SIZE = 0x10000               # 64 KB window

# Well-known slots from the shared ABI (third_party/minimig_eth/extra/minimig_eth_abi.h)
OFF_FLAGS      = 0x1000
OFF_MAC        = 0x104C
OFF_STATUS     = 0x1052
OFF_HEARTBEAT  = 0x1088
OFF_SIGNATURE  = 0x108C
SIGNATURE      = 0xCAFEBABE


def open_window():
    fd = os.open('/dev/mem', os.O_RDWR | os.O_SYNC)
    try:
        return mmap.mmap(fd, SHM_SIZE, mmap.MAP_SHARED,
                         mmap.PROT_READ | mmap.PROT_WRITE, offset=SHM_BASE)
    finally:
        os.close(fd)


def fpga_peek16(m, off):
    """Read a 16-bit value in the core's convention (little-endian)."""
    return m[off] | (m[off + 1] << 8)


def fpga_poke16(m, off, val):
    m[off] = val & 0xFF
    m[off + 1] = (val >> 8) & 0xFF


def peek32(m, off):
    """32-bit slots (heartbeat, signature). The core assembles them as
        {word at off+2, word at off}
    so the LOW half lives at the base offset, and each half is little-endian.
    See BG_READ_HPS_SIG_HI_WAIT in ne2000_core.v."""
    return (fpga_peek16(m, off + 2) << 16) | fpga_peek16(m, off)


def poke32(m, off, val):
    fpga_poke16(m, off, val & 0xFFFF)
    fpga_poke16(m, off + 2, (val >> 16) & 0xFFFF)


def cmd_dump(m, args):
    off = int(args[0], 16) if args else 0
    length = int(args[1], 16) if len(args) > 1 else 0x40
    for row in range(off, off + length, 16):
        raw = m[row:row + 16]
        hexpart = ' '.join('%02X' % b for b in raw)
        text = ''.join(chr(b) if 32 <= b < 127 else '.' for b in raw)
        print('%04X  %-47s  %s' % (row, hexpart, text))


def cmd_peek(m, args):
    off = int(args[0], 16)
    print('%04X: %04X' % (off, fpga_peek16(m, off)))


def cmd_poke(m, args):
    off, val = int(args[0], 16), int(args[1], 16)
    fpga_poke16(m, off, val)
    print('%04X <- %04X (readback %04X)' % (off, val, fpga_peek16(m, off)))


def cmd_clear(m, args):
    m[0:SHM_SIZE] = b'\x00' * SHM_SIZE
    print('window cleared (%d bytes at 0x%08X)' % (SHM_SIZE, SHM_BASE))


def cmd_sign(m, args):
    beat = (peek32(m, OFF_HEARTBEAT) + 1) & 0xFFFFFFFF
    poke32(m, OFF_SIGNATURE, SIGNATURE)
    poke32(m, OFF_HEARTBEAT, beat)
    print('signature 0x%08X at 0x%04X, heartbeat %d at 0x%04X'
          % (peek32(m, OFF_SIGNATURE), OFF_SIGNATURE, beat, OFF_HEARTBEAT))
    print('read 0x%04X from the guest with the probe to prove the round trip'
          % OFF_SIGNATURE)


def cmd_watch(m, args):
    seconds = int(args[0]) if args else 30
    poke32(m, OFF_SIGNATURE, SIGNATURE)

    snapshot = bytes(m[0:SHM_SIZE])
    beat = 0
    end = time.time() + seconds
    print('watching for %ds - signature written, heartbeat advancing' % seconds)
    print('any window byte the FPGA changes will be reported here')

    while time.time() < end:
        beat = (beat + 1) & 0xFFFFFFFF
        poke32(m, OFF_HEARTBEAT, beat)
        time.sleep(0.25)

        current = bytes(m[0:SHM_SIZE])
        for off in range(SHM_SIZE):
            if current[off] != snapshot[off]:
                # ignore the heartbeat slot we are writing ourselves
                if OFF_HEARTBEAT <= off < OFF_HEARTBEAT + 4:
                    continue
                print('  CHANGE at %04X: %02X -> %02X'
                      % (off, snapshot[off], current[off]))
        snapshot = current

    print('heartbeat reached %d' % beat)
    print('status word %04X, flags %04X'
          % (fpga_peek16(m, OFF_STATUS), fpga_peek16(m, OFF_FLAGS)))


def host_mac(iface):
    """Read an interface's MAC as six ints."""
    with open('/sys/class/net/%s/address' % iface) as f:
        return [int(x, 16) for x in f.read().strip().split(':')]


# The card's built-in virtual MAC (DEFAULT_MAC0..5 in ne2000_core.v). Byte 0 is
# unicast (bit0 clear) and locally administered (bit1 set) -- the FPGA checks
# both before adopting a provisioned address.
VIRT_MAC_DEFAULT = [0x52, 0x54, 0x05, 0x04, 0x03, 0x02]


def derive_mac(iface):
    """Overlay the last two bytes of the host NIC's real MAC onto the card's
    virtual MAC. The prefix stays fixed and locally administered; the tail makes
    the address unique per board, so two MiSTers on one LAN cannot collide."""
    hm = host_mac(iface)
    mac = list(VIRT_MAC_DEFAULT)
    mac[4:6] = hm[4:6]
    return mac


def cmd_mac(m, args):
    """mac <iface>   derive from that interface and publish it to the window"""
    iface = args[0] if args else 'eth0'
    mac = derive_mac(iface)

    # Window byte +0 is the logical LOW byte of each 16-bit word (measured --
    # see tb_ne2000_flag_owner.v), and the core reads MAC[2N] from bits [7:0].
    # So the bytes go into the window in plain wire order.
    for i, b in enumerate(mac):
        m[OFF_MAC + i] = b

    print('%s is %s' % (iface, ':'.join('%02X' % b for b in host_mac(iface))))
    print('NE2000 MAC published: %s' % ':'.join('%02X' % b for b in mac))
    print('(reload the core to make the card pick it up -- it is read once at init)')


COMMANDS = {
    'dump': cmd_dump, 'peek': cmd_peek, 'poke': cmd_poke,
    'sign': cmd_sign, 'watch': cmd_watch, 'clear': cmd_clear, 'mac': cmd_mac,
}


def main():
    if len(sys.argv) < 2 or sys.argv[1] not in COMMANDS:
        print(__doc__)
        return 1
    if os.geteuid() != 0:
        print('shmtest.py must run as root (/dev/mem)')
        return 1

    m = open_window()
    try:
        COMMANDS[sys.argv[1]](m, sys.argv[2:])
    finally:
        m.close()
    return 0


if __name__ == '__main__':
    sys.exit(main())
