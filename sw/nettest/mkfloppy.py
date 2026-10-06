#!/usr/bin/env python3
"""
Build a 1.44 MB FAT12 floppy image containing one or more files.

Written for the ao486 NE2000 bring-up: the DOS guest has no way to reach the
SD card, so the probe is delivered as a floppy the OSD can mount. Plain data
disk, not bootable.

  usage: mkfloppy.py out.img FILE [FILE ...]
"""

import os
import sys

SECTOR = 512
SECTORS = 2880                 # 1.44 MB
RESERVED = 1
NUM_FATS = 2
SECTORS_PER_FAT = 9
ROOT_ENTRIES = 224
ROOT_SECTORS = (ROOT_ENTRIES * 32) // SECTOR      # 14
DATA_START = RESERVED + NUM_FATS * SECTORS_PER_FAT + ROOT_SECTORS   # 33


def boot_sector():
    b = bytearray(SECTOR)
    b[0:3] = b'\xEB\x3C\x90'                       # JMP + NOP
    b[3:11] = b'MSDOS5.0'                          # OEM
    b[11:13] = (SECTOR).to_bytes(2, 'little')      # bytes per sector
    b[13] = 1                                      # sectors per cluster
    b[14:16] = (RESERVED).to_bytes(2, 'little')
    b[16] = NUM_FATS
    b[17:19] = (ROOT_ENTRIES).to_bytes(2, 'little')
    b[19:21] = (SECTORS).to_bytes(2, 'little')
    b[21] = 0xF0                                   # media descriptor
    b[22:24] = (SECTORS_PER_FAT).to_bytes(2, 'little')
    b[24:26] = (18).to_bytes(2, 'little')          # sectors per track
    b[26:28] = (2).to_bytes(2, 'little')           # heads
    b[28:32] = (0).to_bytes(4, 'little')           # hidden sectors
    b[32:36] = (0).to_bytes(4, 'little')           # large sector count
    b[36] = 0x00                                   # drive number
    b[38] = 0x29                                   # extended boot signature
    b[39:43] = (0x4E453230).to_bytes(4, 'little')  # volume serial
    b[43:54] = b'NE2KTEST   '                      # volume label
    b[54:62] = b'FAT12   '
    b[510:512] = b'\x55\xAA'
    return b


def set_fat12(fat, cluster, value):
    off = cluster + (cluster >> 1)                 # cluster * 1.5
    if cluster & 1:
        fat[off] = (fat[off] & 0x0F) | ((value << 4) & 0xF0)
        fat[off + 1] = (value >> 4) & 0xFF
    else:
        fat[off] = value & 0xFF
        fat[off + 1] = (fat[off + 1] & 0xF0) | ((value >> 8) & 0x0F)


def dir_entry(name, size, first_cluster):
    stem, _, ext = name.partition('.')
    e = bytearray(32)
    e[0:8] = stem.upper()[:8].ljust(8).encode('ascii')
    e[8:11] = ext.upper()[:3].ljust(3).encode('ascii')
    e[11] = 0x20                                   # archive
    e[22:24] = (0x6000).to_bytes(2, 'little')      # time 12:00
    e[24:26] = (0x5CFC).to_bytes(2, 'little')      # date 2026-07-28
    e[26:28] = (first_cluster).to_bytes(2, 'little')
    e[28:32] = (size).to_bytes(4, 'little')
    return e


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 1

    out, files = sys.argv[1], sys.argv[2:]

    img = bytearray(SECTOR * SECTORS)
    img[0:SECTOR] = boot_sector()

    fat = bytearray(SECTORS_PER_FAT * SECTOR)
    fat[0], fat[1], fat[2] = 0xF0, 0xFF, 0xFF      # media + EOC in entries 0/1

    root = bytearray(ROOT_SECTORS * SECTOR)
    next_cluster = 2
    slot = 0

    for path in files:
        data = open(path, 'rb').read()
        clusters = max(1, (len(data) + SECTOR - 1) // SECTOR)
        first = next_cluster

        for i in range(clusters):
            c = first + i
            last = (i == clusters - 1)
            set_fat12(fat, c, 0xFFF if last else c + 1)
            lba = DATA_START + (c - 2)
            chunk = data[i * SECTOR:(i + 1) * SECTOR]
            img[lba * SECTOR:lba * SECTOR + len(chunk)] = chunk

        root[slot * 32:(slot + 1) * 32] = dir_entry(
            os.path.basename(path), len(data), first)
        slot += 1
        next_cluster += clusters
        print('  %-14s %6d bytes  %d cluster(s) from %d'
              % (os.path.basename(path), len(data), clusters, first))

    for n in range(NUM_FATS):
        off = (RESERVED + n * SECTORS_PER_FAT) * SECTOR
        img[off:off + len(fat)] = fat

    off = (RESERVED + NUM_FATS * SECTORS_PER_FAT) * SECTOR
    img[off:off + len(root)] = root

    open(out, 'wb').write(img)
    print('wrote %s (%d bytes)' % (out, len(img)))
    return 0


if __name__ == '__main__':
    sys.exit(main())
