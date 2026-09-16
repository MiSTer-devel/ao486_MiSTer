#!/usr/bin/env python3
"""
ne2000d.py - standalone NE2000 bridge daemon for the ao486 core (Phase 5).

Runs on the MiSTer as root. Bridges the FPGA NE2000's shared-memory window to a
real network interface with an AF_PACKET raw socket.

This is the first-packet implementation: deliberately simple, Python, standalone.
It exists to prove the protocol end to end. The production version belongs in
Main_MiSTer's poll loop (see A2065's minimig_a2065 for the shape).

    ne2000d.py [iface] [--debug]        default iface eth0

THE HOST CONTRACT (NE2000_AO486_PLAN.md, Phase 4 step 3):
  1. clear the whole window before publishing anything
  2. write the signature AFTER the clear
  3. bump the heartbeat every poll pass
  4. zero the signature on clean exit (best effort)

BYTE ORDER - measured, not guessed. Two independent conventions:
  * a core-logical 16-bit value is LITTLE-endian in the window:
        window[X] = v[7:0], window[X+1] = v[15:8]
  * a 32-bit slot is assembled by the core as {word@off+2, word@off}, so the
    LOW half sits at the base offset.
Getting either wrong is silent: the core simply never reports the signature.
"""

import argparse
import errno
import mmap
import os
import socket
import struct
import sys
import time

SHM_BASE = 0x1FF00000
SHM_SIZE = 0x10000

# --- shared window layout (third_party/minimig_eth/extra/minimig_eth_abi.h) ---
OFF_FLAGS         = 0x1000
OFF_MAC           = 0x104C
OFF_STATUS        = 0x1052
OFF_HEARTBEAT     = 0x1088
OFF_SIGNATURE     = 0x108C
OFF_TX_BUFFER     = 0x2000
OFF_TX_REQ_ADDR   = 0x2C00
OFF_TX_REQ_LEN    = 0x2C02
OFF_RX_QUEUE_HEAD = 0x2C04
OFF_RX_QUEUE_TAIL = 0x2C06
OFF_TX_REQ_SEQ    = 0x2C08
OFF_TX_DONE_SEQ   = 0x2C0A
OFF_RX_QUEUE_LEN  = 0x2C20      # 16 x u16, indexed by slot
OFF_RX_QUEUE_DATA = 0x9000      # 16 x 1536-byte slots

RX_SLOTS      = 16
RX_SLOT_BYTES = 0x600           # 1536; matches bg_rx_slot_offset in the core
FLAG_RX_AVAIL = 0x0004          # HPS-owned bit, low byte of OFF_FLAGS

SIGNATURE = 0xCAFEBABE

# FPGA-published status bits (high byte of OFF_STATUS)
ST_SAMPLED    = 0x0100
ST_SIGNATURE  = 0x0200
ST_HEARTBEAT  = 0x0400
ST_HB_CHANGED = 0x0800
ST_COMM_OK    = 0x1000

# The card's built-in virtual MAC (DEFAULT_MAC0..5 in ne2000_core.v): unicast,
# locally administered. The FPGA validates both before adopting an address.
VIRT_MAC_DEFAULT = [0x52, 0x54, 0x05, 0x04, 0x03, 0x02]

POLL_INTERVAL = 0.002          # 2 ms; heartbeat ticks every pass
MAX_FRAME     = 1536


class Window:
    """The shared DDR window, with the core's byte conventions baked in."""

    def __init__(self):
        fd = os.open('/dev/mem', os.O_RDWR | os.O_SYNC)
        try:
            self.m = mmap.mmap(fd, SHM_SIZE, mmap.MAP_SHARED,
                               mmap.PROT_READ | mmap.PROT_WRITE, offset=SHM_BASE)
        finally:
            os.close(fd)

    def close(self):
        self.m.close()

    def u16(self, off):
        return self.m[off] | (self.m[off + 1] << 8)

    def set_u16(self, off, val):
        self.m[off] = val & 0xFF
        self.m[off + 1] = (val >> 8) & 0xFF

    def u32(self, off):
        return (self.u16(off + 2) << 16) | self.u16(off)

    def set_u32(self, off, val):
        self.set_u16(off, val & 0xFFFF)
        self.set_u16(off + 2, (val >> 16) & 0xFFFF)

    def read(self, off, length):
        return bytes(self.m[off:off + length])

    def clear(self):
        self.m[0:SHM_SIZE] = b'\x00' * SHM_SIZE


def host_mac(iface):
    with open('/sys/class/net/%s/address' % iface) as f:
        return [int(x, 16) for x in f.read().strip().split(':')]


def derive_mac(iface):
    """Overlay the host NIC's last two bytes onto the card's virtual MAC, so two
    boards on one LAN cannot answer to the same address."""
    mac = list(VIRT_MAC_DEFAULT)
    mac[4:6] = host_mac(iface)[4:6]
    return mac


# AF_PACKET promiscuous membership. The virtual card MAC differs from the host
# NIC's own MAC, so unicast replies to the guest (DHCP OFFER, every TCP segment)
# arrive addressed to a MAC the host NIC would otherwise drop in hardware. Without
# this the guest receives only broadcast/multicast -- "card is receiving packets"
# yet DHCP never gets its (unicast) OFFER. Per-socket membership is removed
# automatically when the socket closes, so eth0 is not left promiscuous on exit.
SOL_PACKET = 263
PACKET_ADD_MEMBERSHIP = 1
PACKET_MR_PROMISC = 1


def set_promisc(s, iface):
    ifindex = socket.if_nametoindex(iface)
    # struct packet_mreq { int mr_ifindex; u16 mr_type; u16 mr_alen; u8 mr_address[8]; }
    mreq = struct.pack("IHH8s", ifindex, PACKET_MR_PROMISC, 0, b"")
    s.setsockopt(SOL_PACKET, PACKET_ADD_MEMBERSHIP, mreq)


def open_socket(iface):
    s = socket.socket(socket.AF_PACKET, socket.SOCK_RAW, socket.htons(0x0003))
    s.bind((iface, 0))
    set_promisc(s, iface)
    s.setblocking(False)
    return s


class Daemon:
    def __init__(self, iface, debug=False, accept_multicast=False):
        self.iface = iface
        self.debug = debug
        self.accept_multicast = accept_multicast
        self.win = Window()
        self.sock = open_socket(iface)
        self.mac = derive_mac(iface)
        self.heartbeat = 0
        self.last_tx_seq = 0
        self.tx_frames = 0
        self.tx_bytes = 0
        self.rx_frames = 0
        self.rx_bytes = 0
        self.rx_dropped_full = 0
        self.rx_dropped_self = 0
        self.rx_filtered = 0

    def log(self, fmt, *a):
        if self.debug:
            print(fmt % a, flush=True)

    # -- startup -------------------------------------------------------------
    def publish(self):
        # 1. clear first: the window comes up as uninitialised DDR, and a core
        #    reload can leave stale indices behind.
        self.win.clear()

        # 2. MAC, before the core reads it at init
        for i, b in enumerate(self.mac):
            self.win.m[OFF_MAC + i] = b

        # 3. signature only after everything else is in place
        self.win.set_u32(OFF_SIGNATURE, SIGNATURE)
        self.win.set_u32(OFF_HEARTBEAT, 0)

        # adopt whatever the core has already published as consumed
        self.last_tx_seq = self.win.u16(OFF_TX_DONE_SEQ)

        print('ne2000d: iface %s, card MAC %s'
              % (self.iface, ':'.join('%02X' % b for b in self.mac)))
        print('ne2000d: window published at 0x%08X' % SHM_BASE)
        print('ne2000d: reload the core if it was already running - the MAC is '
              'read once at init')

    def shutdown(self):
        # best effort: a killed daemon never gets here, which is why the core
        # also watches the heartbeat
        try:
            self.win.set_u32(OFF_SIGNATURE, 0)
        except Exception:
            pass
        self.win.close()
        self.sock.close()

    # -- transmit ------------------------------------------------------------
    def poll_tx(self):
        """The core stages a frame, then publishes TX_REQUEST_SEQ last. It waits
        for TX_COMPLETE_SEQ to equal that value before reporting the transmit
        done, so the ack must come only after the frame is really sent."""
        seq = self.win.u16(OFF_TX_REQ_SEQ)
        if seq == self.last_tx_seq or seq == 0:
            return

        length = self.win.u16(OFF_TX_REQ_LEN)
        if length == 0 or length > MAX_FRAME:
            # Do not ack nonsense: acking would tell the guest it was sent.
            self.log('ne2000d: TX seq %d has implausible length %d, ignored',
                     seq, length)
            return

        frame = self.win.read(OFF_TX_BUFFER, length)
        try:
            self.sock.send(frame)
        except OSError as e:
            if e.errno in (errno.EAGAIN, errno.EWOULDBLOCK, errno.ENOBUFS):
                return          # retry next pass; leave the request unacked
            self.log('ne2000d: send failed: %s', e)
            return

        self.tx_frames += 1
        self.tx_bytes += length
        self.log('ne2000d: TX seq %d, %d bytes  %s', seq, length,
                 ' '.join('%02x' % b for b in frame[:14]))

        # ack only now
        self.win.set_u16(OFF_TX_DONE_SEQ, seq)
        self.last_tx_seq = seq

    # -- receive -------------------------------------------------------------
    def wanted(self, frame):
        """Keep what the card would actually accept, drop the rest here rather
        than making the 486 do it: unicast to us and broadcast always; multicast
        only when --multicast is set. A default NE2000 (RCR/MAR unset) takes no
        multicast until the guest joins a group, and forwarding a busy LAN's
        mDNS/SSDP storm floods the 16-slot ring and buries real unicast traffic
        (the DHCP OFFER was being dropped this way). Per-group MAR honouring is
        future work; for now multicast is all-or-nothing behind the flag."""
        dst = frame[0:6]
        if dst == bytes(self.mac):
            return True
        if dst == b'\xff' * 6:
            return True
        if dst[0] & 0x01:                   # multicast group bit
            return self.accept_multicast
        return False

    def poll_rx(self):
        """Produce into the ring at TAIL. The FPGA owns HEAD and consumes from
        it; we never write HEAD, and we publish the payload and length BEFORE
        advancing TAIL so the core can never see a slot that is not ready."""
        for _ in range(32):                 # bounded work per pass
            try:
                frame = self.sock.recv(MAX_FRAME)
            except OSError as e:
                if e.errno in (errno.EAGAIN, errno.EWOULDBLOCK):
                    return
                raise

            if len(frame) < 14:
                continue

            # AF_PACKET also hands back what we transmit; feeding that to the
            # guest would look like every frame echoing.
            if frame[6:12] == bytes(self.mac):
                self.rx_dropped_self += 1
                continue

            if not self.wanted(frame):
                self.rx_filtered += 1
                continue

            head = self.win.u16(OFF_RX_QUEUE_HEAD) & (RX_SLOTS - 1)
            tail = self.win.u16(OFF_RX_QUEUE_TAIL) & (RX_SLOTS - 1)
            nxt = (tail + 1) & (RX_SLOTS - 1)
            if nxt == head:
                self.rx_dropped_full += 1   # ring full: the guest is behind
                continue

            if len(frame) > RX_SLOT_BYTES:
                frame = frame[:RX_SLOT_BYTES]

            base = OFF_RX_QUEUE_DATA + tail * RX_SLOT_BYTES
            self.win.m[base:base + len(frame)] = frame
            self.win.set_u16(OFF_RX_QUEUE_LEN + tail * 2, len(frame))

            # payload and length are in place; only now publish the index
            self.win.set_u16(OFF_RX_QUEUE_TAIL, nxt)

            # RX_AVAIL is ours to set (low byte lane); the core reads it as a
            # hint only -- it discovers frames from head/tail.
            self.win.m[OFF_FLAGS] = self.win.m[OFF_FLAGS] | FLAG_RX_AVAIL

            self.rx_frames += 1
            self.rx_bytes += len(frame)
            self.log('ne2000d: RX slot %d, %d bytes  %s', tail, len(frame),
                     ' '.join('%02x' % b for b in frame[:14]))

    # -- main loop -----------------------------------------------------------
    def run(self):
        self.publish()
        last_status = None
        last_report = time.time()

        while True:
            self.heartbeat = (self.heartbeat + 1) & 0xFFFFFFFF
            self.win.set_u32(OFF_HEARTBEAT, self.heartbeat)

            self.poll_tx()
            self.poll_rx()

            status = self.win.u16(OFF_STATUS)
            if status != last_status:
                bits = []
                for mask, name in ((ST_SAMPLED, 'SAMPLED'),
                                   (ST_SIGNATURE, 'SIGNATURE'),
                                   (ST_HEARTBEAT, 'HEARTBEAT'),
                                   (ST_HB_CHANGED, 'HB_CHANGED'),
                                   (ST_COMM_OK, 'COMM_OK')):
                    if status & mask:
                        bits.append(name)
                print('ne2000d: core status %04X [%s]' % (status, ' '.join(bits)),
                      flush=True)
                last_status = status

            if self.debug and time.time() - last_report >= 5:
                print('ne2000d: tx %d/%dB  rx %d/%dB  (full %d, self %d, filtered %d)  hb %d'
                      % (self.tx_frames, self.tx_bytes, self.rx_frames, self.rx_bytes,
                         self.rx_dropped_full, self.rx_dropped_self,
                         self.rx_filtered, self.heartbeat), flush=True)
                last_report = time.time()

            time.sleep(POLL_INTERVAL)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('iface', nargs='?', default='eth0')
    ap.add_argument('--debug', action='store_true')
    ap.add_argument('--multicast', action='store_true',
                    help='forward all multicast to the guest. Off by default: a '
                         'freshly-initialised NE2000 (default RCR/MAR) accepts '
                         'only broadcast + its own unicast, and a busy LAN''s '
                         'mDNS/SSDP multicast otherwise floods the 16-slot ring '
                         'and buries real traffic (e.g. the DHCP OFFER).')
    args = ap.parse_args()

    if os.geteuid() != 0:
        print('ne2000d must run as root (/dev/mem and AF_PACKET)')
        return 1

    d = Daemon(args.iface, args.debug, accept_multicast=args.multicast)
    try:
        d.run()
    except KeyboardInterrupt:
        print('\nne2000d: stopping')
    finally:
        d.shutdown()
    return 0


if __name__ == '__main__':
    sys.exit(main())
