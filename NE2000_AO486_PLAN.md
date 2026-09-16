# NE2000 Network Card for the MiSTer ao486 Core — Implementation Plan

Status: draft v1 (2026-07-27)
Author: planning document, not yet implemented code
Targets: `MiSTer-devel/ao486_MiSTer` (master @ `4ba37be`), reusing RTL from
`apolkosnik/Minimig-AGA_MiSTer` branch `Ethernet_shmem2` (@ `9598b93`)

---

## 1. Problem

### 1.1 What is missing

The ao486 core has no network interface card. Its only network path is serial:
two `gh_uart_16550` instances (COM1 `0x3F8`, COM2 `0x2F8`, `rtl/soc/uart/`)
routed to the DE10-Nano UART pins, with the HPS providing a PPP/modem bridge
(`releases/drv/modem9x.inf`). That gives a slow, single-session dial-up-style
link and nothing that a guest operating system recognises as Ethernet.

Guests that matter for ao486 expect a NIC, not a modem:

- Windows 95/98 networking (file sharing, TCP/IP over LAN)
- Windows NT 3.51/4.0, which has no usable PPP dialer story for casual use
- Novell NetWare clients (IPX over Ethernet)
- Linux, FreeBSD and other 486-era UNIX ports
- DOS packet-driver software (mTCP, Doom deathmatch over IPX, Netware)

The NE2000/DP8390 is the right target: it is the single most widely supported
ISA NIC across every one of those operating systems, drivers are in-box or
freely available, and the programming model is small enough to implement in
FPGA fabric.

### 1.2 Why this is not a copy-paste job

A complete NE2000/RTL8019AS implementation already exists, but not in ao486. It
lives in the Minimig-AGA `Ethernet_shmem2` branch:

| File | Lines | Role |
|---|---|---|
| `rtl/ethernet.v` | 3187 | NE2000/RTL8019AS device model + Amiga bus glue + DMA background engine |
| `rtl/eth_ddr3_mailbox.v` | 294 | 16-bit `eth_dma_*` ⇄ 64-bit Avalon master, CDC, lane mapping |
| `rtl/eth_avalon_arbiter.v` | 144 | strict-priority 2-master arbiter on the `ram2`/f2sdram2 port |
| `rtl/eth_dma_addr_map.v` | 31 | single source of truth for the shared-window base |
| `extra/minimig_eth.cpp` | 2784 | HPS-side bridge daemon (AF_PACKET raw socket), built into Main_MiSTer |
| `extra/minimig_eth_abi.h` | 95 | shared-memory ABI |
| `sim/eth_*.v`, `sim/*ethernet*_tb.v` | ~25 benches | lane, ring, mailbox, flood, wrap, ABI checks |

Three problems block direct reuse:

1. **The device model is fused to the Amiga bus.** `ethernet_interface` takes
   `cpu_as`/`cpu_uds`/`cpu_lds`, drives `dtack_eth`, decodes a 64KB autoconfig
   card aperture at `$EA0000`, and exposes NE2000 registers at **4-byte
   spacing** (`$EA0C00`, `$EA0C04`, …) as an X-Surf 100 clone. ao486 needs
   byte-spaced ISA ports at `0x300` with `bus_wait`/`bus_io32` semantics.
2. **Endianness is the opposite.** The Amiga is big-endian; x86 is
   little-endian and drives NE2000 with `DCR.BOS = 0`. Every byte-lane decision
   in the packet RAM (`mem_l`/`mem_u`), the remote-DMA word assembly, and the
   HPS packet buffers must be re-derived rather than assumed.
3. **The HPS⇄FPGA transport is not yet proven on hardware.** The branch's own
   `NE2000_HPS_FPGA_COMM_PLAN.md` records the current state: the HPS heartbeat
   advances, but no FPGA-owned mirror bits ever appear (`status & 0x7F00 == 0`,
   `CR=0x00`, `CURR=0x00`) — the two sides are not addressing the same physical
   DDR bytes. "Path A" (dedicated f2sdram2 mailbox at `0x1FF00000` + arbiter)
   passes simulation and a full Quartus build, but the hardware round trip is
   still an open gate. Porting that transport blind would import an unsolved
   bug.

Additional inherited risks recorded in the same document: worst setup slack
`-0.217 ns` on the Minimig build, and a fitter blow-up (93,497 combinational
nodes vs 83,820 available) when packet RAM was not inferred as block RAM.

### 1.3 Goals

- G1: A guest OS on ao486 sees a standard NE2000 at a configurable I/O base and
  IRQ, and reaches the LAN through the DE10-Nano's Ethernet or Wi-Fi.
- G2: The NE2000 device model becomes **bus-agnostic and reusable** by other
  MiSTer cores (the stated ambition in the community thread and in the Minimig
  plan document).
- G3: Every layer is provable in simulation before hardware, and every hardware
  gate has a named, observable pass criterion.
- G4: ao486 timing closure and fitter headroom are not regressed.

### 1.4 Non-goals

- No 100 Mbit / RTL8139 / PCI NIC. ao486 has no PCI.
- No boot ROM socket emulation (network boot). Packet drivers load from disk.
- No change to the existing UART/PPP path; it stays as-is and independent.
- No attempt to fix the Minimig core's own hardware bug as part of this work,
  beyond sharing whatever the transport proof reveals.

---

## 2. Relevant ao486 facts (verified against master `4ba37be`)

| Fact | Location | Consequence for this plan |
|---|---|---|
| I/O devices are attached with a registered chip-select, a flat read mux, and `bus_wait` | `rtl/system.v:379-440`, `rtl/soc/iobus.v` | NE2000 attach is ~15 lines of glue; no DTACK phase games |
| 16-bit single-cycle I/O exists via `bus_io32` (used by the IDE data port) | `rtl/system.v:459`, `rtl/soc/iobus.v:74,97,99` | Direct mechanism for the NE2000 16-bit remote-DMA data port |
| `irq[11]` and `irq[13]` are hardwired to 0 | `rtl/system.v:203-204` | IRQ 11 is free; IRQ 3/5/10 are contended by COM2/SB/GUS |
| PC RAM lives on `DDRAM_*`/f2sdram1 at `0x30000000` | `ao486.sv:574` (`DDRAM_ADDR[28:25] = 4'h3`) | The `0x1FF00000` mailbox window does **not** collide with guest RAM |
| `sys/` is stock upstream | `diff` vs Minimig shows only `emu_ports.vh`, `hps_io.sv`, `sys_top.v`, `yc_out.sv` differing, none for Ethernet | Adding the mailbox requires a `sys/` fork (12 new `ETH_MBX_*` ports + ~100 changed `sys_top.v` lines) — a maintenance cost to plan for |
| A generic HPS command channel already exists (`hps_ext`, cmds `0x61`–`0x63`, 16-bit words with address auto-increment) | `rtl/hps_ext.v`, used by MiSTerFS | Viable fallback transport with no `/dev/mem` and no address-unit ambiguity |
| Icarus-based unit benches with per-device Makefiles | `sim/iverilog/pic/Makefile`, `sim/iverilog/*` | Existing pattern for the new NE2000 benches |
| OSD options are plain `CONF_STR` entries | `ao486.sv` `localparam CONF_STR` | Add a "Network" section under `P2,Hardware` |

---

## 3. Proposed solution

### 3.1 Three-layer split

```
   ┌──────────────────────────────────────────────────────────────┐
   │ Guest OS (DOS / Win9x / NT / Linux)                          │
   │   NE2000 packet driver / NDIS / kernel ne module             │
   └──────────────────────────────────────────────────────────────┘
                  │  ISA port I/O 0x300-0x31F, IRQ 11
   ┌──────────────┴───────────────────────────────────────────────┐
   │ rtl/soc/ne2000/ne2000_isa.v        (NEW, ao486-specific)     │
   │  - iobus chip-select, byte/word sizing, bus_io32 data port   │
   │  - reset port, IRQ level output, OSD-selected base/IRQ       │
   └──────────────┬───────────────────────────────────────────────┘
                  │  generic byte-addressed register port
   ┌──────────────┴───────────────────────────────────────────────┐
   │ rtl/soc/ne2000/ne2000_core.v       (EXTRACTED from Minimig)  │
   │  - DP8390 registers (all pages), CR/ISR/IMR/DCR/RCR/TCR      │
   │  - receive ring, BNRY/CURR, remote DMA engine                │
   │  - 16KB packet RAM (split mem_l/mem_u, M10K-inferred)        │
   │  - station PROM / RTL8019 ID                                 │
   │  - DCR.BOS-driven byte order (NOT hardwired big-endian)      │
   │  - background FSM: TX drain, RX ring fill                    │
   └──────────────┬───────────────────────────────────────────────┘
                  │  eth_dma_* (16-bit req/ready master) — unchanged ABI
   ┌──────────────┴───────────────────────────────────────────────┐
   │ Transport (choose one, same interface)                       │
   │  A. rtl/soc/ne2000/ne2000_ddr_mailbox.v + eth_avalon_arbiter │
   │     → f2sdram2 (ram2) @ 0x1FF00000, CLK_AUDIO domain         │
   │  B. rtl/soc/ne2000/ne2000_extbus.v  → hps_ext EXT_BUS cmd    │
   └──────────────┬───────────────────────────────────────────────┘
                  │
   ┌──────────────┴───────────────────────────────────────────────┐
   │ Main_MiSTer: support/ne2000/mister_ne2000.cpp                │
   │  (generalised from extra/minimig_eth.cpp)                    │
   │  AF_PACKET raw socket, BPF filter, GSO split, MAC selection  │
   └──────────────────────────────────────────────────────────────┘
```

The `eth_dma_*` interface is the seam the Minimig plan already established, so
the transport can be swapped without touching the device model. Keep it.

### 3.2 Guest-visible programming model

Standard ISA NE2000, byte-spaced:

| Offset | Ports | Function |
|---|---|---|
| base+0x00..0x0F | 16 | DP8390 registers, page selected by `CR.PS1:PS0` |
| base+0x10..0x17 | 8 | Remote DMA data port (8- or 16-bit per `DCR.WTS`) |
| base+0x18..0x1F | 8 | Reset port (read triggers reset, write acknowledged) |

Default base `0x300`, so decode is `{iobus_address[15:5],5'd0} == 16'h0300`.
Alternate bases `0x280`, `0x320`, `0x340`, `0x360` selectable from the OSD.
Default IRQ 11 (free), with IRQ 3/5/10/11 selectable.

Internal address space seen through remote DMA (unchanged from the NE2000
standard and from the Minimig implementation):

- `0x0000`–`0x001F`: station PROM (MAC duplicated per byte pair, `0x57 0x57`
  signature at `0x0E/0x0F`)
- `0x4000`–`0x7FFF`: 16KB packet RAM, pages `0x40`–`0x7F`
- TX page `0x40` (staging, 6 pages), `PSTART = 0x46`, `PSTOP = 0x80`
- Everything else reads `0xFF`

RTL8019AS ID bytes (`0x50`, `0x70`) at page-0 `0x0A/0x0B` reads are kept so
that RTL8019-aware drivers probe correctly, exactly as the Minimig version
does.

Debug/diagnostic aperture: `base+0x20..0x2F` (i.e. `0x320`–`0x32F` at the
default base) is proposed as an ao486-only, non-standard window exposing the
transport status word, the HPS heartbeat mirror, and TX/RX sequence numbers.
This is what makes Phase 1 and Phase 4 testable from a plain DOS program with
`DEBUG.EXE` or a 20-line C utility, without a JTAG session. It must be
compile-time removable.

### 3.3 Byte order

The Minimig implementation is written for a big-endian 68k with 4-byte register
spacing. For ao486:

- Register access: byte-spaced, single byte per port, no lane swapping.
- Remote DMA data port in 16-bit mode: guest writes/reads little-endian words;
  `packet RAM[addr]` low byte ↔ `D[7:0]`.
- `DCR.BOS` (bit 1) must actually select byte order in `ne2000_core.v` rather
  than being ignored, so the same core still serves a big-endian host later.
- The HPS shared buffers hold frames in **wire order** (byte 0 = first byte on
  the wire). Any swapping belongs in the transport layer's lane mapping, not in
  the device model and not in the daemon.

### 3.4 Transport decision

**Primary: Path A, the DDR mailbox**, ported unchanged in structure from
Minimig (`eth_ddr3_mailbox.v` + `eth_avalon_arbiter.v`, HPS physical base
`0x1FF00000`, Avalon word base `0x03FE0000 = phys >> 3`, `ram2` shared with
`ddr_svc` under strict `ddr_svc` priority). ao486's PC RAM is on `DDRAM_*`
(f2sdram1, base `0x30000000`), so the reserved window is free.

**Fallback: Path B, `hps_ext` EXT_BUS.** A new `ne2000_extbus.v` presenting the
same `eth_dma_*` interface, moving frames over the existing user_io command
channel (new command IDs above `0x63`). Slower and it costs Main_MiSTer
protocol work, but it has no `/dev/mem`, no reserved-window assumption, no
Avalon-word-vs-byte-address unit mismatch, and no `sys/` fork. Given that the
Minimig branch is currently blocked on exactly that class of bug, Path B is the
de-risking option and Phase 1 exists to decide between them **before** any
NE2000 RTL is written for ao486.

### 3.5 HPS side

`extra/minimig_eth.cpp` is already a Main_MiSTer component (it includes
`shmem.h`, `hardware.h`, `user_io.h`, `spi.h`). Work needed:

- Rename/relocate to `support/ne2000/mister_ne2000.cpp` with a core-name gate
  so one Main_MiSTer binary serves Minimig and ao486.
- Move Amiga-specific behaviour (X-Surf MAC derivation, Amiga-oriented
  broadcast denoise heuristics) behind a per-core profile struct.
- Keep unchanged: AF_PACKET raw socket setup, interface auto-selection,
  cBPF kernel filter, GSO/GRO superframe splitting, RX queue, TX sequence
  handshake, restart-safe pending TX preservation.
- Keep the generated-ABI discipline (`minimig_eth_abi.h` +
  `sim/check_eth_abi.py`) and make it core-independent.

This is a separate Main_MiSTer pull request and is the long pole for
upstreaming; plan for the core to be testable with a locally built Main_MiSTer
binary in the meantime.

---

## 4. Execution steps

Each phase lists work items, exit criteria, and test steps. No phase starts
before the previous phase's exit criteria are met.

### Phase 0 — Harness and baseline — **DONE except 0.4 (blocked)**

**Work**

0.1 ~~Fork `ao486_MiSTer`, branch `ne2000`.~~ **Done, locally.** Working tree at
    `/Volumes/Home/nigelshearman/Development/ao486`, remote `upstream` =
    `MiSTer-devel/ao486_MiSTer`, branch `ne2000` off master `4ba37bed`
    (2026-07-16). A GitHub fork/push is a separate, user-initiated step.
0.2 ~~Vendor the Minimig sources into `third_party/minimig_eth/`.~~ **Done.**
    820 KB, source commit `9598b936` recorded, inventory + licence + missing
    dependencies + baseline findings in
    `third_party/minimig_eth/doc/PROVENANCE.md`.
0.3 ~~Create the NE2000 sim harness.~~ **Done.** `sim/iverilog/ne2000/`
    (`Makefile`, `run_baseline.sh`, `README.md`). Modelled loosely on
    `sim/iverilog/pic/Makefile`, but self-contained — see BF-2 below for why the
    upstream harness could not be reused as-is.
0.4 Record baseline Quartus results for unmodified master. **UNBLOCKED —**
    Quartus Prime Lite 17.0.0 found on `nshearman@192.168.1.65`
    (`/opt/altera/17.0/quartus/bin`). Baseline compile of the tree as it stands
    (nothing NE2000 is in `files.qip` yet, so this *is* the untouched-master
    baseline) is running; numbers land in Appendix C.

**Test results (2026-07-27, Icarus Verilog 13.0, Verilator 5.050)**

```bash
make -C sim/iverilog/ne2000 baseline
```

- ✅ Vendored suite: `pass=18 xfail=1 fail=0 skipped=3`, exit 0. This is the
  Phase 2 equivalence reference (T2.1).
- ✅ Verilator lints `rtl/soc/iobus.v` and `rtl/soc/pic.v` clean.
- ⛔ 0.4 baseline `.rbf`, fitter totals and slack — pending a Quartus host.

**Baseline findings**

- **BF-1** `ethernet_tb` fails at the vendored commit: a data-port read taken
  while the background FSM holds the packet-RAM port returns `0x5252` instead of
  the expected watchdog value `0xFFFF` (`sim/ethernet_tb.v:449`). Deterministic.
  Listed in `KNOWN_FAIL` so equivalence is measured against the real state of
  the source. Resolve in Phase 2 or with work item 4.3 (bounded timeouts).
- **BF-2** The upstream ao486 Icarus benches are stale: `make -C sim/iverilog/pic`
  fails (Makefile searches only `.`), and `rtl/soc/pic.v` uses declare-after-use
  that Icarus 13 rejects (70 elaboration errors). Verilator handles the same
  files, which confirms the plan's split: Icarus for NE2000 unit benches,
  Verilator for ao486 system-level bus benches.
- **BF-3** `ethernet.v` trips Verilator `MULTITOP` — it holds several modules
  including `ethernet_issp` (Altera in-system probe). The extracted
  `ne2000_core.v` must be one module per file and must not drag the ISSP stub
  into the ao486 build.
- **BF-4** `minimig_eth.cpp` needs `eth_gso.h` and `gen_eth_abi.py`, which live
  in the author's Main_MiSTer fork rather than the core repo. Needed at Phase 5.

**Remaining exit criterion:** 0.4 on a Quartus host.

### Phase 1 — Prove the HPS⇄FPGA transport before writing any NIC RTL — **COMPLETE, GATE PASSED**

This phase exists because it is the exact place the Minimig effort is stuck.

**RESULT — 2026-07-28, hardware, both directions:**

```
guest (SHMPROBE.COM)                    HPS (shmtest.py)
  window 0x108C  CAFE  [ok]   <-------- signature 0xCAFEBABE written
  window 0x108E  BABE  [ok]
  wrote 5A5A -> window 0x0000 --------> dump 0: 5A 5A 00 00 ...
  read back      5A5A  [ok]
PASSED - FPGA and HPS share the same window
```

**The architecture changed from what this phase originally specified**, on the
evidence of the A2065 project's own history (`~/Development/amiga/A2065`, whose
notes were read on 2026-07-28):

| Original plan | What was built | Why |
|---|---|---|
| Fork `sys/`: mailbox on `sys_top`'s `ram2`, arbitrated against `ddr_svc` | **`sys/` untouched.** Mailbox shares the core's own `emu` `DDRAM_*` port with the ao486 memory controller via `ne2000_ddram_arbiter` | A2065 built exactly the `ram2` version and had it **rejected in review**; it reworked to the `DDRAM_*` port with `sys/` byte-identical to upstream. Closes plan risk R5 and the upstreaming blocker |
| CDC between `clk_sys` and `clk_audio` | **No CDC at all** — `DDRAM_CLK = clk_sys` (`rtl/system.v:325`), so the mailbox is single-domain | Also removes the hazard A2065 hit: 1-cycle mailbox replies were fine at 49 MHz and missed at 114 MHz, stalling the bus permanently |
| Write a two-master arbiter | **Ported A2065's `a2065_ddram_arbiter.v`** | It already carries fixes for two real deadlocks: a grant latched after a single-beat write, and — the subtle one — holding an *idle* master off, which stops it ever requesting because the controller only asserts while `~BUSY`. ao486's L2 cache has the identical pattern (`rtl/cache/l2_cache.v:215-219`) |

Path B (`hps_ext`/EXT_BUS) was **not needed** and stays unbuilt. A2065's notes
also record the HPS2FPGA lightweight bridge as non-functional on MiSTer, so it
is not a fallback either.

Window safety was verified on the target before writing to `/dev/mem`:
`mem=511M memmap=513M$511M`, `System RAM` ends at `0x1FEFFFFF`, so `0x1FF00000`
is reserved and not kernel memory.

**Build:** ALMs 36,382 / 41,910 (87%), M10K 452/553 (82%), fitter successful, 0
errors, worst setup −6.040 ns (baseline −6.829), all hold slack positive, `sys/`
diff empty.

**Tooling built for the gate, kept for later phases:**

- `rtl/soc/ne2000/ne2000_shm_probe.v` — guest-visible window access at
  `0x328`–`0x32D`, no NE2000 logic, watchdog-bounded
- `sw/nettest/SHMPROBE.ASM` / `.COM` — guest side
- `sw/nettest/shmtest.py` — HPS side (`sign`, `dump`, `peek`, `poke`, `watch`,
  `clear`), runs on the MiSTer's own python3
- `sim/iverilog/ne2000/tb_ne2000_shm_probe.v` — the whole chain in simulation

**One false alarm worth recording:** the first hardware run reported
"transport TIMEOUT" on every access. The cause was not the transport — MiSTer
stores OSD settings per core *filename*, so the renamed `.rbf` booted with
`Network` off and every probe port read open bus (`0xFF`), which has both the
done and timeout status bits set. `SHMPROBE` now reports an all-ones status as
"port not decoded" instead of blaming the mailbox.


**Work**

1.1 Port `eth_ddr3_mailbox.v`, `eth_avalon_arbiter.v`, `eth_dma_addr_map.v`
    into `rtl/soc/ne2000/`, renaming to `ne2000_ddr_mailbox.v` etc.
1.2 Fork `sys/`: add the 12 `ETH_MBX_*` ports to `sys/emu_ports.vh`, wire
    `ddr_svc` to a private `dsvc_*` master and arbitrate `dsvc_*` (m0) against
    `ETH_MBX_*` (m1) onto `ram2_*` in `sys/sys_top.v`.
1.3 Add a **transport probe** device: a minimal I/O-mapped block at `0x320`–
    `0x32F` that lets the guest read/write arbitrary words of the shared window
    through `eth_dma_*` (address latch + data port + go/busy bit). No NE2000
    logic at all.
1.4 Write `sw/nettest/probe.c` (DOS, Open Watcom or DJGPP): writes a pattern to
    the shared window, reads it back, prints the transport status word.
1.5 Add a temporary HPS-side test daemon (or a `mister_ne2000.cpp` stub) that
    mmaps `0x1FF00000` via `shmem.h`, writes signature `0xCAFEBABE` and an
    incrementing heartbeat, and dumps what it sees.

**Test**

```bash
iverilog -g2012 -o sim/iverilog/ne2000/mbx_tb.vvp sim/iverilog/ne2000/tb_mailbox_arbiter.v rtl/soc/ne2000/ne2000_ddr_mailbox.v rtl/soc/ne2000/ne2000_avalon_arbiter.v rtl/soc/ne2000/ne2000_dma_addr_map.v
```

- T1.1 (sim) Lane/byte mapping, read round trip, backpressure, and no burst
  corruption while a `ddr_svc`-style burst master interleaves — port
  `sim/eth_mailbox_arbiter_tb.v` and `sim/eth_dma_lane_tb.v`. **Pass = both
  benches report PASS across two asynchronous clocks.**
- T1.2 (sim) Address map: recovered HPS physical byte address ==
  `0x1FF00000 + window_offset` for a sweep of offsets (port
  `sim/eth_dma_addr_map_tb.v`). **Pass = assertion clean over the full 64KB.**
- T1.3 (hardware, the real gate) Boot DOS, run `probe.exe`:
  - FPGA writes a known word → HPS daemon prints the same word.
  - HPS writes `0xCAFEBABE` + heartbeat → probe reports
    `status & ETH_STATUS_FPGA_SIGNATURE` and `ETH_STATUS_FPGA_HB_CHANGED` set.
  - **Pass = a full bidirectional round trip with non-zero FPGA-owned status
    bits.** This is the criterion the Minimig branch has never met.
- T1.4 (hardware) Audio and video are unaffected while the probe hammers the
  mailbox (the arbiter must not starve `ddr_svc`): play a sound-card test and
  watch for dropouts for 60 s under continuous probe traffic.
- T1.5 (build) Quartus compile still meets timing and fits within the Phase 0
  baseline plus an agreed margin.

**Decision gate:** if T1.3 fails after a bounded debug effort, switch to Path B
(`ne2000_extbus.v` over `hps_ext`) and repeat T1.3 against it. Do not proceed
to Phase 2 without a proven transport.

### Phase 2 — Extract a bus-agnostic `ne2000_core` — **DONE (T2.4 deferred)**

Reordered ahead of Phase 1: Phase 1 needs a Quartus host and real hardware,
Phase 2 needs neither, and the two are independent (Phase 2 is a pure refactor
below the `eth_dma_*` seam). The Phase 1 transport gate still stands before any
hardware claim is made.

**Result**

| Item | Status |
|---|---|
| 2.1 split | done — `rtl/soc/ne2000/{ne2000_core,ne2000_packet_ram,ne2000_issp}.v` |
| 2.2 `DCR.BOS` | done — but the finding was the opposite of what this plan assumed; see BF-5 |
| 2.3 M10K packet RAM | preserved — `mem_l`/`mem_u` untouched |
| 2.4 TPSR fix | preserved and now regression-tested (`tb_ne2000_tpsr.v`) |
| T2.1 equivalence | **PASS** — `pass=18 xfail=1 fail=0 skipped=3`, identical to the vendored baseline |
| T2.2 BOS | **PASS** — `tb_ne2000_bos.v` |
| T2.3 TPSR | **PASS** — `tb_ne2000_tpsr.v` |
| T2.4 M10K inference | **PASS** — both arrays map to M10K, see below |

```bash
make -C sim/iverilog/ne2000 check
```

Current ao486 suite: **pass=20 xfail=1 fail=0** (the xfail is BF-1).

**How equivalence was proven, and why the Amiga glue is gone.** The extraction is
a pure identifier rename (`cpu_*` → `host_*`, `ethernet_interface` →
`ne2000_core`), so the diff carries no behaviour. To demonstrate that, a
temporary 1:1 Amiga wrapper let the vendored bench suite run unmodified against
the extracted core: `pass=18 xfail=1 fail=0 skipped=3`, identical to the same
suite against the vendored `ethernet.v`, with BF-1 failing the same way at the
same time in both — which is what made the claim meaningful rather than
green-on-green. With that recorded, the wrapper was deleted: this is an
ao486-only core and no Amiga bus logic belongs in the tree. The 19 portable
benches were converted once to drive `ne2000_core` natively and now live in
`sim/iverilog/ne2000/regression/`; the three Amiga-glue benches (`gary`,
`cpu_wrapper`, `amiga_clk`) were dropped, their ao486 counterparts being T3.1–T3.3.

**T2.4 evidence** (Quartus 17.0 Lite, Cyclone V 5CSEBA6U23I7, `ne2000_core`
synthesised standalone):

```
ne2000_packet_ram:packet_ram_inst|altsyncram:mem_l_rtl_0 ... M10K block, True Dual Port, 8192 x 8
ne2000_packet_ram:packet_ram_inst|altsyncram:mem_u_rtl_0 ... M10K block, True Dual Port, 8192 x 8
Total block memory bits : 131,072      Total registers : 6,238
```

Zero packet-RAM bits in logic — the fitter blow-up that hit the Minimig build
(93k vs 84k nodes) is avoided. Module-body `parameter` declarations were changed
to `localparam` so the new parameter port list does not produce ~56 warnings.

**BF-5 — the vendored `DCR.BOS` polarity is inverted vs. a real DP8390.**
This plan assumed BOS was ignored. It is not: it drives the data-port swap. But
measured on the extracted core (`tb_ne2000_bos.v`, first wire byte at the even
packet-RAM address):

| DCR.BOS | vendored core puts first byte in | real DP8390 |
|---|---|---|
| 0 | D[15:8] | D[7:0] (8086 order) |
| 1 | D[7:0] | D[15:8] (68000 order) |

x86 guests program BOS=0 and expect low-byte-first, so an unmodified port would
byte-swap every frame — risk R2, caught in simulation rather than in Phase 6.
Fix: `ne2000_core` gained a `BOS_INVERT` parameter. `0` (default) keeps the
vendored Amiga behaviour bit-for-bit, so the equivalence suite still passes;
`ne2000_isa.v` will instantiate with `BOS_INVERT=1` for standard semantics.

**BF-3 resolved** — one module per file; Verilator lints `ne2000_core`,
`ne2000_packet_ram` and `ne2000_issp` clean. (Watch for comment lines starting
with the word "verilator" — those parse as lint pragmas.)

**Work as originally planned**

2.1 Split `ethernet.v` into:
   - `rtl/soc/ne2000/ne2000_core.v` — registers, ring, remote DMA, packet RAM,
     background FSM, `eth_dma_*` master. Generic port interface:
     `reg_addr[3:0]`, `reg_page`, `data_port_sel`, `reset_port_sel`,
     `wr/rd/wdata[15:0]/rdata[15:0]/word_access`, `irq`.
   - `third_party/minimig_eth/ne2000_amiga_glue.v` — the Amiga-side shell
     (`cpu_as/uds/lds`, `dtack_eth`, `$EA0C00` 4-byte spacing, 64KB aperture,
     `0xFFFF` dummy termination). Kept only so the extraction can be proven
     neutral; not built into ao486.
2.2 Make `DCR.BOS` functional; remove hardwired big-endian assumptions in the
    packet RAM and data-port paths.
2.3 Keep the split byte-wide `mem_l`/`mem_u` arrays — they are what makes
    Quartus infer M10K instead of blowing the fitter.
2.4 Keep the 2026-06-13 TX fix: TPSR is bounded by the physical packet-RAM page
    range `[0x40, 0x80)`, **not** by `[PSTART, PSTOP)`.

**Test**

- T2.1 (sim) Re-run every ported Minimig bench against
  `ne2000_core + ne2000_amiga_glue` **unmodified**: `ethernet_tb`,
  `eth_rx_ringwrap_tb`, `eth_rx_flood_tb`, `eth_rx_lensweep_tb`,
  `eth_rx_batch_tb`, `eth_station_mac_tb`, `eth_dataport_contention_tb`,
  `eth_ack_starvation_tb`, `eth_memtest_*`. **Pass = identical results to the
  pre-split baseline; the refactor is proven neutral.**
- T2.2 (sim) New `tb_ne2000_bos.v`: write a known 16-bit pattern through the
  data port with `DCR.BOS=0` and `DCR.BOS=1`, read back, assert the byte order
  flips and only then. **Pass = both orders correct.**
- T2.3 (sim) New `tb_ne2000_tpsr.v`: `TPSR=0x40` with `PSTART=0x46`,
  `PSTOP=0x80` must transmit and set `TSR.PTX`/`ISR.PTX` (this is the exact bug
  that the old Minimig bench masked). **Pass = PTX asserted.**
- T2.4 (synth) Trial-synthesise `ne2000_core` standalone; confirm both packet
  RAM arrays map to `altsyncram`/M10K. **Pass = zero packet RAM bits in
  logic.**

### Phase 3 — ao486 ISA glue and system integration — **COMPLETE**

**Result**

| Item | Status |
|---|---|
| 3.1 `ne2000_isa.v` | done — port decode, byte/word lanes, `io_wait` handshake, watchdog |
| 3.2 `rtl/system.v` | done — chip select, `bus_io32`, read mux, `bus_wait`, IRQ mux |
| 3.3 `ao486.sv` OSD | done — `P2oS,Network` and `P2oTU,NE2000 IRQ` |
| 3.4 `files.qip` | done — `rtl/soc/ne2000/ne2000.qip` |
| 3.5 MAC address | deferred to Phase 4/5 — it arrives through the shared window, which is not connected yet |
| T3.1 port decode | **PASS** — `tb_ne2000_isa.v` |
| T3.2 bus attach | **PASS** — `tb_ne2000_iobus.v`, driving the real `iobus.v` |
| T3.3 IRQ path | **PASS** — in `tb_ne2000_isa.v` |
| T3.4 DOS probe | **PASS** — `NE2KTEST.COM` reports PASSED on hardware after the BF-6 fix |
| T3.5 fit + timing | **PASS** — fits, builds an `.rbf`, no new failing clock domain (detail below) |

Suite after Phase 3: **pass=22 xfail=1 fail=0**.

**Guest-visible card**

| Port | Function |
|---|---|
| `0x300`–`0x30F` | DP8390 registers, byte-spaced, page-selected by `CR` |
| `0x310`–`0x317` | remote-DMA data port; 16-bit accesses retire in one bus cycle via `bus_io32` |
| `0x318`–`0x31F` | reset port |
| `0x320`–`0x32F` | debug aperture (ao486-only, `DEBUG_APERTURE` parameter) |

`0x330`–`0x33F` is deliberately left out of the decode — that is the MPU-401.
IRQ 11 is the default because it is the only line ao486 leaves free
(`rtl/system.v` used to tie it to 0); 10, 5 and 3 are selectable but are shared
with SB/GUS and COM2, so they are the user's problem if those are also in use.
`0x300` collides with nothing in the existing ao486 I/O map.

**Bus handshake.** `iobus` pulses `bus_read`/`bus_write` for a single cycle and
then stalls while `bus_wait` is high. `ne2000_isa` therefore latches the access
and holds the core strobes until `host_ack_n` — the same shape as the 68k
AS/DTACK cycle the core was written against. A `WATCHDOG_CYCLES` counter retires
any unacknowledged access as open bus, so a wedged core or dead transport cannot
hang the CPU (plan item 4.3, implemented early because the transport is not
connected yet).

**Transport is deliberately not wired.** `eth_dma_ready` is tied low until Phase
1/4. That does not make the card inert: registers, the station PROM and the full
16 KB packet RAM are serviced locally by `ne2000_core`, so a guest driver can
probe, reset, program the ring and move data through the remote-DMA port today.
Only HPS traffic — real frames in and out — needs the mailbox.

**First hardware run — 2026-07-28, DE10-Nano, Windows 9x guest, `DEBUG.EXE`**

| Check | Result |
|---|---|
| Core boots, guest runs normally | ✅ no regression from the +1,600 ALMs or the shared IRQ wiring |
| `IN 0x30A` / `IN 0x30B` (RTL8019 ID) | ✅ `50` `70` — the card is decoded and responding on real silicon |
| Byte-mode packet RAM round trip | ❌ wrote `AA BB`, read back **`BB AA`** |

**BF-6 — `DCR.BOS` was applied to 8-bit data-port reads.** In
`complete_data_port_transfer`, the 16-bit packet-RAM word is swapped by
`DCR.BOS` *before* the byte-mode path picks its half by address, so an 8-bit
read returned the neighbouring byte. Byte-mode writes never swapped, so write
and read disagreed and the round trip reversed. On a real DP8390, BOS applies
to 16-bit transfers only.

This was latent in the vendored source, not introduced here: the Amiga driver
and every vendored bench program `BOS=0`, which under the vendored polarity
means "no swap", so byte mode happened to work. Adopting standard polarity for
x86 (BF-5) turned the swap on at `BOS=0` and exposed it.

Fixed by gating the swap with `data_port_word_mode`. The failure was reproduced
in simulation first — `tb_ne2000_isa.v` returned the same `BB AA` — then fixed,
and the byte-mode round trip is now a permanent case in that bench. Full suite
after the fix: **pass=22 xfail=1 fail=0**.

Note what caught this: the 16-bit path was covered by simulation and was
correct; the 8-bit path was not covered, and only hardware exercised it. T3.4
earns its place in the plan.

**T3.4 result — hardware, 2026-07-28, `NE2KTEST.COM` on the fixed build**

```
NE2KTEST - ao486 NE2000 probe, I/O base 0x300
  [ ok ] reset port          ISR.RST set
  ..... RTL8019 ID          50 70    [ ok ]
  ..... BNRY read-back      46       [ ok ]
  ..... 8-bit data port     AA BB    [ ok ]     <- BF-6 fix confirmed
  ..... 16-bit data port    1234 A55A [ ok ]    <- never before exercised on hardware
  ..... station PROM (MAC)  52:54:05:04:03:02 [ ok ]
  Debug aperture: dmaL 20  dmaH 00  cntL 00  cntH 00  dpst 43  hpsc 00  hbLo 00
PASSED
```

Every guest-visible path of the card works on silicon: decode, registers, reset
port, station PROM, and both the 8-bit and 16-bit remote-DMA data ports with
correct x86 byte order. The 16-bit port is the one every driver uses for bulk
transfers and the one `DEBUG.EXE` cannot reach, which is why the probe was
worth building.

Two expected non-results, both Phase 4/5 work and neither a defect:

- **The MAC is the hardcoded `DEFAULT_MAC0..5` placeholder**, not a real
  address — it is baked into the bitstream, so two ao486 MiSTers on one LAN
  would collide. Item 3.5 (MAC provisioning through the shared window) is still
  open and must land before real traffic.
- `hpsc` (HPS comm status) reads `00` because no transport is connected yet.

**T3.5 result — rebuild after the BF-6 fix, 2026-07-28**

| Metric | Baseline | BF-6 fixed build | Delta vs baseline |
|---|---|---|---|
| Logic (ALMs) | 34,679 (83 %) | **36,166 (86 %)** | +1,487 |
| Registers | 34,751 | 37,026 | +2,275 |
| Block memory bits | 3,235,560 | 3,366,632 | +131,072 |
| RAM blocks (M10K) | 436 (79 %) | 452 (82 %) | +16 |
| `.rbf` | 4,190,484 B | 4,278,952 B | +88,468 B |
| Fitter / errors | Successful / 0 | **Successful / 0** | |

Worst setup slack: `emu|pll ... counter[0]` **−5.663 ns / TNS −25,167**
(baseline −6.829 / −20,696). Other domains all positive: hdmi +0.481,
`counter[4]` +0.831, `h2f_user0_clk` +1.401. Same picture as the first Phase 3
build — the already-failing CPU domain has a better worst path and more total
failing paths; nothing previously passing went negative.

Deployed to the MiSTer as `ao486_ne2000_20260728b.rbf` (md5
`98e6f18d9c3ba01034ddd0ca4656270e`, verified against the local copy).

**T3.5 result — first Phase 3 compile, 2026-07-27 (superseded by the rebuild above)**

| Metric | Baseline | With NE2000 | Delta |
|---|---|---|---|
| Logic (ALMs) | 34,679 (83 %) | **36,279 (87 %)** | +1,600 (+3.8 pp) |
| Registers | 34,751 | 36,932 | +2,181 |
| Block memory bits | 3,235,560 | 3,366,632 | +131,072 (exactly the 16 KB packet RAM) |
| RAM blocks (M10K) | 436 (79 %) | 452 (82 %) | +16 |
| `.rbf` | 4,190,484 B | 4,298,424 B | +107,940 B |
| Fitter | Successful | **Successful** | |
| Errors | 0 | **0** | |

Cost attribution from the fitter hierarchy report:

```
|ne2000_isa:ne2000|              1715.2 ALMs   2657 regs   131072 mem bits   16 M10K
   |ne2000_core:u_core|          1596.5 ALMs   2457 regs
      |ne2000_packet_ram|           0.6 ALMs      0 regs   131072 mem bits   16 M10K
```

The ISA glue itself is ~119 ALMs; essentially all the cost is the device model,
which is what the Minimig implementation always was. The +16 M10K is expected,
not a surprise: each 8192 × 8 array spans 8 physical M10K blocks (an M10K holds
1024 × 8), so two arrays = 16 blocks = the 131,072 bits above.

Timing, worst setup slack by clock:

| Clock | Baseline | With NE2000 | |
|---|---|---|---|
| `emu\|pll ... counter[0]` (CPU) | −6.829 ns / TNS −20,696 | **−6.047 ns / TNS −23,710** | worst path better, total failing worse |
| `pll_hdmi ... counter[0]` | +0.231 | +0.207 | positive |
| `sysmem h2f_user0_clk` | +1.371 | +0.836 | positive |
| `emu\|pll ... counter[4]` | +0.998 | +1.187 | positive |

Read honestly: the CPU domain already fails in stock upstream and still fails —
its worst path actually improved by 0.78 ns, but total negative slack grew ~15 %,
i.e. more paths miss by less. **No previously-passing domain was pushed
negative**, which is the criterion this plan can hold to. The remaining margin
is the real constraint: 87 % ALM and 82 % M10K leaves room for the Phase 4
transport, but not much beyond it. Revisit at Phase 7 (7.3/7.4) — the debug
aperture and any tracing must be compile-time removable for release builds.

**Work as originally planned**

3.1 `rtl/soc/ne2000/ne2000_isa.v`: decode `base+0x00..0x1F` into the core's
    generic port; drive a 32-bit `io_readdata` in the IDE style so the 16-bit
    data port works through `bus_io32`; handle the reset port; expose an 8-bit
    `irq` level.
3.2 `rtl/system.v`:
   - add `ne2k_cs <= ({iobus_address[15:5],5'd0} == ne2k_base);` to the
     registered decode block (`rtl/system.v:379`)
   - add `ne2k_dbg_cs` for the debug aperture (compile-time gated)
   - extend `bus_io32` with `(ne2k_cs & ne2k_dataport & word_access)`
   - route `ne2k_readdata` into the `bus_readdata` mux alongside the IDE ports
     (`rtl/system.v:462`), leaving `iobus_readdata8` as the fallback
   - `assign irq[11] = ne2k_irq;` (replacing the `assign irq[11] = 0;` at
     `rtl/system.v:203`), with a mux for the selectable IRQ
   - `ne2k_wait` into `bus_wait` if the core ever needs to stall
3.3 `ao486.sv`: `CONF_STR` additions under `P2,Hardware`:
   - `P2oXY,Network,Off,On;`
   - `P2oZ..,NE2000 I/O,300h,280h,320h,340h,360h;`
   - `P2o..,NE2000 IRQ,11,3,5,10;`
   (exact status bits assigned when writing the code; document them here)
3.4 `files.qip`: add `rtl/soc/ne2000/ne2000.qip`.
3.5 MAC address: derive deterministically from the DE10-Nano's own MAC or a
    stored value, exposed by the HPS through the shared window, mirrored into
    the station PROM at reset.

**Test**

- T3.1 (sim) New `sim/iverilog/ne2000/tb_ne2000_isa.v`: drives `iobus`-shaped
  cycles. Assert byte reads of page-0 `0x0A/0x0B` return `0x50/0x70`; a word
  access to `base+0x10` completes in one `bus_io32` transfer; a read of
  `base+0x18` resets the NIC and sets `ISR.RST`. **Pass = all three.**
- T3.2 (sim) `sim/verilator/soc`-style system bench: an x86-style I/O sequence
  (probe, reset, read PROM, program `DCR/RCR/TCR/PSTART/PSTOP/BNRY/CURR`,
  start) leaves `CR=0x22`. **Pass = register dump matches a reference NE2000
  init trace.**
- T3.3 (sim) IRQ path: force `ISR.PRX` with `IMR.PRXE` set, assert `irq[11]`
  rises and the PIC sees it; clear `ISR`, assert it falls. **Pass = clean
  edges, no stuck IRQ.**
- T3.4 (hardware) DOS: run `sw/nettest/NE2KTEST.EXE` (Open Watcom, `wmake`).
  It checks the reset port, the RTL8019 ID at `0x30A`/`0x30B`, register
  read-back, the station PROM/MAC, and an 8-word write/read-back through the
  16-bit data port — then dumps the debug aperture. A byte-swapped data port is
  named explicitly rather than left as a mystery. **Pass = every check passes;
  HPS comm status is expected to read `0x00` until Phase 4.**
- T3.5 (build) Quartus fit + timing versus the Phase 0 baseline. **Pass = fits
  with margin and no new failing paths.** (Watch this closely: the Minimig
  build sits at `-0.217 ns` and a 16KB packet RAM is not free.)

### Phase 4 — Wire the proven transport to the core — **IN PROGRESS**

**Step 1 done:** `ne2000_dma_mux.v` shares the single `eth_dma_*` master between
the device model (priority) and the bring-up probe; the core's transport is no
longer tied off. Covered by `tb_ne2000_dma_mux.v` — the property that matters is
that a completion is never lost, duplicated, or delivered to the master that did
not issue it, since `eth_dma_ready` is a single pulse.

**Step 2 done, and it found a defect.** `tb_ne2000_no_host.v` builds the shipped
chain and runs a full driver sequence under two hostile conditions: (A) DDR
works but no host daemon exists, (B) the DDR port is dead with `waitrequest`
stuck high. Every guest access retires in both, **worst latency 3 cycles**, so
the A2065 circular-wait class cannot occur here — guest registers and data-port
accesses are serviced locally and all shared-memory traffic is background.

**BF-7 — transmit reports success when nothing was sent.**
With no host present, a normal transmit sequence leaves `ISR=0x42` and
`TSR=0x01`: `PTX`, "transmitted without error". With the DDR port dead it does
the same *while `tx_stage_pending` is still asserted* — success is reported
before the frame has finished staging, let alone been sent.

Impact: with the daemon not running, a guest driver believes every frame was
transmitted and packets silently vanish. During bring-up this is worse than a
hang, because it disguises a dead transport as a working NIC — Phase 6 would
show "ping fails" with a card claiming every send succeeded.

Cause: the TX completion path sets `TSR.PTX`/`ISR.PTX` from FPGA-side staging
rather than from the host's completion sequence. The ABI already carries
`TX_REQUEST_SEQ`/`TX_COMPLETE_SEQ` for exactly this, but with the window zeroed
both read 0 and compare equal, so completion looks satisfied immediately.

**Step 2b done — fixed, but not the way first proposed.** The obvious fix was to
wait for `TX_COMPLETE_SEQ` to advance. Reading the code first showed why that is
wrong: the immediate completion is deliberate, and the comment records what
happened when it was not —

> *Complete-on-command: report PTX immediately when the transmit is issued …
> the packet still stages to the HPS mailbox in the background … which otherwise
> overran the driver's transmit timeout ("No IRQ received / Transmit timeout")*

A 1500-byte frame is hundreds of `eth_dma` round trips. Waiting for real
completion would have re-introduced a bug someone already paid for.

What shipped instead keeps the fast path and gates only the **claim of success**
on whether a host exists at all:

```verilog
wire transport_alive = hps_signature_valid && (hps_heartbeat_seen != 32'h0);
```

With a live host: unchanged, `TSR.PTX` / `ISR.PTX` immediately. With no host:
`TSR.ABT` + `ISR.TXE`, so a driver sees a real transmit failure and can retry or
report a dead link. Verified in both hostile conditions by
`tb_ne2000_no_host.v`.

Two judgement calls worth recording:

- The gate deliberately does **not** require the heartbeat to have been seen to
  *advance*. That first version broke two vendored benches, and it was the gate
  that was wrong, not the benches: requiring an observed tick fails every
  transmit in the first poll window and any host that is merely between ticks.
  Signature + non-zero heartbeat is the real difference between "nobody is
  there" and "somebody is".
- **Known gap:** a daemon that dies leaving its signature behind still looks
  alive. Startup window-clear (item 4.4) covers the common case; catching a
  *stopped* host needs heartbeat-staleness tracking, worth adding when the
  daemon lands in Phase 5.

**Step 3 done — publish, don't adopt.**

*Ordering was already right.* The TX path stages the whole frame through
`BG_WRITE_TX_BUF_*` and only reaches `BG_WRITE_TX_SEQ_REQ` when
`bg_tx_bytes_remaining` hits zero, so `TX_REQUEST_SEQ` is published after its
payload. Likewise the RX head advances only after the frame has been copied into
the ring. Verified by reading the FSM; no change needed.

*Ownership was not.* `BG_READ_RX_HEAD_WAIT` re-adopted `RX_QUEUE_HEAD` from the
window on **every poll**, despite the ABI naming it the FPGA-consumed index.
That makes our own read pointer follow whatever is in shared memory — and that
window genuinely comes up as uninitialised DDR (observed as random ASCII before
the first clear). Now the local value is authoritative, the read is kept only so
the DMA sequence the HPS sees is unchanged, and what the window claimed is
recorded for diagnostics.

*Reset publish added.* New `BG_INIT_HEAD_REQ`/`BG_INIT_HEAD_WAIT` states publish
head = 0 once before anything is consumed, so a core reload cannot leave a
still-running daemon reading a stale consumer index. Dedicated states, not a
reuse of `BG_WRITE_RX_HEAD_*`: that path's completion logic assumes it is
mid-drain and tried to consume a frame that did not exist, which also starved
TX. The vendored RX benches caught it immediately.

**Residual, not yet fixed:** after a core reload with the daemon still running,
the FPGA starts at head = 0 while the daemon's tail may be further on, so a few
frames already in the queue would be delivered again as stale. The clean fix is
to read the tail during init and start at `head = tail`, discarding the backlog.
Deferred because it needs its own test; the daemon-side window clear covers the
daemon-restart case, which is the common one.

**Step 4 done — owner-specific flag lanes.**

The FPGA published its flags with a read-modify-write of a word both sides
write: `(bg_flags_word & ETH_HPS_FLAG_MASK) | fpga_owned_flags`. Anything the
HPS set between the read and the write was silently clobbered.

Fixed by splitting the word by **byte lane** rather than relocating it: FPGA
bits moved to the logical high byte (`TX_REQ` 0x0200, `IRQ` 0x0800, `ENABLED`
0x2000), HPS bits stay in the low byte (`RESET` 0x0001, `RX_AVAIL` 0x0004). The
FPGA now writes with only its own lane enabled and no read at all, so there is
nothing left to race. Keeping the offset unchanged meant the 11 vendored benches
that reference the flag word needed no edits.

The FPGA also no longer clears the HPS's `RX_AVAIL` — that was writing another
owner's bit. RX discovery uses the head/tail indices, not that hint, so nothing
depends on it; the daemon manages its own flag.

Proven by `tb_ne2000_flag_owner.v`: with `RX_AVAIL` set by a simulated daemon,
the FPGA publishes `ENABLED` and the HPS bit survives. Under the old code that
byte read back as zero.

**Lane mapping is now measured, not assumed.** The core pre-swaps before handing
a word to the mailbox, which swaps again, so a core-logical word lands in the
window **low byte first**: window byte +0 is the logical low byte, +1 the high
byte. My first version of the bench had this inverted and failed — the RTL was
right. Worth carrying into Phase 5: `sw/nettest/shmtest.py` currently reads
16-bit values as big-endian, which matched the probe path but has **not** been
checked against the core's convention. The daemon must be written against the
measured mapping, not against that helper.

**Step 5 done — host-provisioned station MAC.** Closes item 3.5.

**Scheme:** overlay the last two bytes of the board's real NIC MAC onto the
card's own virtual MAC. The prefix `52:54:05:04` stays fixed — unicast (bit0 of
byte 0 clear) and locally administered (bit1 set) — and the tail makes the
address unique per board, so two ao486 MiSTers on one LAN no longer answer to
the same address. The interface is whichever the daemon bridges, `eth0` or
`eth1`.

Measured on hardware: `eth0 = 72:2C:1D:CE:FA:25` → NE2000 `52:54:05:04:FA:25`.

**FPGA:** new `BG_INIT_MAC_REQ`/`WAIT` states read the three MAC words from
`ETH_SHM_CTRL_MAC` once at init, straight after the head publish. The address is
adopted only if it is non-zero, unicast and locally administered; a zeroed or
uninitialised window fails all three and the built-in default stands, so the
card still works with no host at all.

**HPS:** `sw/nettest/shmtest.py mac [iface]` derives and publishes it, and is
what proved the scheme on hardware.

`tb_ne2000_mac.v` runs the whole path: host publishes, core adopts at init, and
the guest reads the provisioned address out of the **station PROM** via remote
DMA — which is where every driver actually gets its MAC.

**The byte-order trap I flagged in step 4 duly sprang.** `bg_dma_hps_word` has
already been through `hps_u16_from_dma`, so it is in host order; I swapped it a
second time, which put MAC[1] where MAC[0] belongs. The validity rule then
rejected the address for not being locally administered and the default was
kept — the failure was safe and loud rather than silent corruption, but it cost
a debugging round. Anything reading host-written words must use
`bg_dma_hps_word` as-is.

**Phase 4 build + instrumentation cleanup — 2026-07-29**

The first Phase 4 build fit at **41,108 ALMs (98%)** and pushed two
previously-passing clock domains negative (`pll_hdmi` −0.409, `emu|pll
counter[4]` −0.088). Not deployable.

The cause was not the new logic. Every earlier ALM figure for this core was
measured with the transport **tied off** (`eth_dma_ready = 1'b0`, outputs
unconnected), so Quartus pruned the whole background FSM and everything feeding
it. `ne2000_isa` "cost" 1,715 ALMs in Phase 3 and 5,974 once the transport was
connected — the earlier number was mostly dead logic, and the "+1,600 ALMs,
comfortable headroom" reported at T3.5 understated the real cost.

Removed the inherited Minimig diagnostic instrumentation, which existed to debug
a transport fault this port does not have: `frame_wr_csum[0:255]` (a 256×16
array explicitly forced into logic — ~4,096 registers plus mux tree), the
running checksums (`ring_wr_csum`, `dp_rd_csum`, `bg_rx_csum_*`), the per-frame
read-corruption comparator (`rd_corrupt`, `rd_checked`, `rd_bad_*`) and the
frame/page counters. Sync slots 40–49 keep their addresses and now publish
`0x0000`. None of it was in the data path.

| | 98% build | after cleanup | Phase 0 baseline |
|---|---|---|---|
| ALMs | 41,108 (98%) | **36,891 (88%)** | 34,679 (83%) |
| CPU domain setup | −6.394 / TNS −36,379 | **−5.877 / TNS −24,614** | −6.829 / TNS −20,696 |
| `pll_hdmi` | **−0.409** | **+0.054** | +0.231 |
| `emu\|pll counter[4]` | **−0.088** | **+0.824** | +0.998 |
| `h2f_user0_clk` | +0.427 | +1.526 | +1.371 |

No previously-passing domain is negative, so the Phase 0 criterion is met again.
`pll_hdmi` at +0.054 ns is thin and worth watching if more logic lands.

**Cost accepted:** four benches asserted the probes themselves (checksum
comparisons, `rd_corrupt == 0`, the published slot at `0x110A`). Those specific
assertions were removed. The benches still verify the RX ring byte-exactly
against expected packet contents — the check that matters — but a redundant
second path that re-derived the same conclusion via checksums is gone. That is a
real reduction in belt-and-braces coverage, taken deliberately for ~4.2k ALMs
and timing closure.

Deployed as `ao486_ne2000_p4.rbf` (md5 `b3af6652…`, verified on the SD card).

**Phase 4 verified on hardware — 2026-07-29, `ao486_ne2000_p4.rbf`**

```
reset port        ISR.RST set          [ok]
RTL8019 ID        50 70                [ok]
BNRY read-back    46                   [ok]
8-bit data port   AA BB                [ok]
16-bit data port  1234 A55A            [ok]
station PROM MAC  52:54:05:04:FA:25    [ok]   <- host-provisioned
debug aperture    hbLo = B1 (non-zero: HPS heartbeat is being sampled)
PASSED
```

The MAC is the board's real `eth0` tail (`72:2C:1D:CE:FA:25`) overlaid onto the
card's virtual address, read by the guest from the station PROM — the path a
driver actually uses. Item 3.5 closed; two ao486 MiSTers on one LAN no longer
share an address.

Phase 4 is complete: transport wired with arbitration, guest-never-waits proven
(3-cycle worst latency with DDR dead), BF-7 fixed, ownership discipline applied
to indices and flags, MAC provisioned. Nothing has yet put a frame on the wire —
that is Phase 5.

### Phase 5 — standalone daemon — **DONE: both directions proven on hardware (guest TX to wire, guest RX from ring)**

`sw/nettest/ne2000d.py`, deployed to `/media/fat/Scripts/`. Python and
standalone on purpose: this is the first-packet implementation, meant to prove
the protocol. The production version belongs in Main_MiSTer's poll loop.

**Two byte-order bugs found before a line of daemon logic was written**, exactly
where step 4 said to look:

1. 16-bit values were big-endian in `shmtest.py`; the core is **little-endian**
   (`window[X] = v[7:0]`).
2. 32-bit slots had their halves swapped — the core assembles
   `{word@off+2, word@off}`, so the **low** half sits at the base offset.

Neither was visible through the shm probe, which passes DMA data through
unswapped while the core applies `hps_u16_from_dma`; probe round-trips agreed
with the wrong convention, which is why the Phase 1 gate passed anyway. The only
symptom was the core never setting `FPGA_SIGNATURE`. After the fix the core
publishes status **`0x1F00`** — `SAMPLED | SIGNATURE | HEARTBEAT | HB_CHANGED |
COMM_OK`.

**TX — proven on the wire.**

```
52:54:05:04:fa:25 > ff:ff:ff:ff:ff:ff, ethertype ARP, length 60
```

Source is the derived MAC. The daemon reads `TX_REQUEST_SEQ`, sends the staged
frame, and only then writes `TX_COMPLETE_SEQ` — an ack before the send would tell
the guest a frame went out that had not.

**RX — produce side proven.** Real LAN multicast lands in the ring: slot 0
payload at `0x9000`, slot 1 at `0x9600` (stride 1536 as the core computes it),
length at `0x2C20 + slot*2`. Payload and length are written **before** the tail
advances. Counters after a quiet minute: `rx 15/1344B (full 53)` — the ring
filled to 15 usable slots and then dropped, because head stayed 0: the guest's
NIC was never started, so the FPGA has nothing to consume with. Dropping rather
than overwriting unconsumed slots is the correct behaviour.

The daemon never writes `RX_QUEUE_HEAD` and never clears its own `RX_AVAIL`
except as a hint — ownership as defined in step 4.

**Guest-originated transmit — PROVEN on the wire, 2026-08-03.** `NE2KSEND.COM`
(assembled on `cross-compiler.broadband`, back online; the MiSTer still has no
`nasm`) builds a broadcast ARP at page 0x40, fires TXP, and the daemon puts it on
eth0. Independent `tcpdump` on the MiSTer:

```
52:54:05:04:03:02 > ff:ff:ff:ff:ff:ff, ethertype ARP, length 60: who-has 0.0.0.0
```

Src MAC, ethertype and length correct; ARP decodes clean in Wireshark = byte
order correct end to end (guest DOS → core → DMA → daemon → wire). Capture kept
at `sw/nettest/evidence/ne2ksend_guest_tx_20260803.pcap`.

**BF-8 — TX_REQUEST_SEQ collided across a guest soft reset.** First run of
`NE2KSEND` went out; every later run silently did not, while the guest still
printed "SENT". Cause: `NE2KSEND` (like any driver) begins with a reset-port
read, and `apply_nic_reset()` zeroed `tx_request_seq`. So every run after a reset
re-published seq=1; the daemon tracks the last seq it sent and only transmits on a
change, so seq=1==1 was dropped as a duplicate. The BF-7 complete-on-command fast
path still reported `TSR.PTX`, so the loss was invisible from DOS — worse than a
hang. Diagnosed from the daemon's `tx` counter refusing to advance past 1 while
the guest reported success.

Fix: `tx_request_seq` is a transport-lifetime counter, not a NIC-lifetime one. It
is cleared only on hard core reset (which also clears the shared window), never on
a guest soft reset. Regression `tb_ne2000_tx_seq.v` seeds a live host, transmits
twice with a reset-port read between, and asserts the seq advances 1→2; it fails
1→1 with the clear reintroduced. Suite now **pass=28 xfail=1 fail=0**.

Rebuilt and deployed as `ao486_ne2000_20260803_seqfix.rbf` (md5
`292ca435a90dacfc4856a87d1b65bd3b`). Fit 37,271 ALMs (89%), M10K 452 (82%),
worst setup −5.590 ns on the already-failing CPU domain (better than baseline
−6.829), every other domain positive, 0 errors. **Hardware confirms the fix:**
six back-to-back `NE2KSEND` runs against one un-restarted daemon each advanced the
seq and each egressed (daemon `tx 6/360B`); three are captured in
`/media/usb0/test.pcap`. Under the old code only the first would have left.

**Guest RX-consume — PROVEN on hardware, 2026-08-03.** `NE2KRECV.COM` (also built
on `cross-compiler.broadband`) starts the NIC for receive, which is what makes the
FPGA drain its shared-memory RX queue into the packet-RAM ring and advance CURR.
It then walks BNRY→CURR, reads each packet's 4-byte ring header + Ethernet header
via remote DMA, prints length / dst / src / ethertype, and advances BNRY. A run
read **8 frames** out of the ring (indices 1..8), each with a distinct non-zero
length and distinct dst/src MAC — real varied LAN traffic, not zeros or open-bus —
drained BNRY behind them, and reported "OK - guest consumed frames from the ring."

That closes the last guest-visible path: **both directions are now proven on
silicon** — guest TX to the wire and guest RX out of the ring. What remains for
this phase is only robustness (heartbeat-staleness) and the move off the
throwaway Python daemon into Main_MiSTer (Phase 5 proper, below).

All four bring-up tools now ship on the floppy
`build/NE2KTEST.img` → `/media/fat/games/AO486/NE2KTEST.img`: `NE2KTEST` (card
probe), `SHMPROBE` (window probe), `NE2KSEND` (guest TX), `NE2KRECV` (guest RX).

**Process note:** two daemon instances ran simultaneously for one test because
`pkill` does not exist on MiSTer's busybox and the kill silently failed. Both
enqueued the same frames, which showed up as identical payloads in consecutive
slots. Use `ps | grep | xargs kill` here.

**Host liveness contract (FPGA ⇄ daemon)** — written in step 3 so both ends are
built against the same rules; the FPGA staleness check lands with the daemon in
Phase 5.

The daemon must:

1. On startup, **clear the whole 64 KB window** before publishing anything, so
   no state from a previous session or a previous core is ever adopted.
2. Write the signature `0xCAFEBABE` at `0x108C` *after* the clear.
3. Increment a `u32` heartbeat at `0x1088` on **every poll pass**. No timer or
   thread required — one 64-bit DDR write beside the packet work.
4. On clean shutdown, zero the signature. Best-effort only: a killed daemon
   never runs cleanup, which is precisely why the heartbeat exists.

The FPGA may assume:

- `signature valid && heartbeat != 0` ⇒ a host has published itself. This is
  what gates transmit honesty today (BF-7).
- Heartbeat **unchanged across the staleness window** ⇒ the host is gone. Not
  yet implemented; this is the part that catches a *crashed* daemon, whose
  signature is left behind and would otherwise read as alive forever.

**The staleness threshold must be generous — hundreds of milliseconds.**
MiSTer's Main is single-threaded and its poll can stall for tens of milliseconds
inside the IDE handler. A tight threshold would declare a healthy daemon dead
mid-transfer and start aborting valid frames: the same hazard as the A2065 IDE
deadlock, reached from the other direction. The condition being detected is
permanent, so reacting quickly buys nothing.

The FPGA must never block a guest access waiting on any of this. Liveness only
changes what is *reported*, never whether a cycle retires — see
`tb_ne2000_no_host.v`.


**Work**

4.1 Connect `ne2000_core`'s `eth_dma_*` master to the Phase 1 transport.
4.2 Publish the register/status mirror from reset and after register writes and
    remote-DMA completion (the Minimig fix: do not gate mirror publication on
    `CR.STA`).
4.3 Implement bounded timeouts on every blocking handshake (the top lesson
    recorded in the Minimig plan: a missing register-path timeout wedged the
    bridge until core reload).
4.4 Clear stale mailbox state at startup, on core load and on daemon restart.
4.5 Replace the shared read/modify/write flag word with owner-specific slots
    (the Minimig doc lists this as still-actionable technical debt — do not
    inherit it).

**Test**

- T4.1 (sim) Port `eth_status_write_cdc_tb`, `eth_mailbox_wide_tb`,
  `eth_rx_bg_tb`, `eth_rx_concurrent_tb`. **Pass = all report PASS.**
- T4.2 (sim) New timeout bench: stall the transport mid-handshake and assert
  the core recovers within the bounded window and sets an error status bit
  rather than hanging. **Pass = no deadlock.**
- T4.3 (hardware) Debug aperture reports `ETH_STATUS_FPGA_COMM_OK`, a non-zero
  `CR` mirror, and a `CURR` mirror after a guest NIC init. **Pass = all
  three.**
- T4.4 (hardware) Kill and restart the HPS daemon with a TX request pending:
  the frame is either transmitted exactly once or cleanly failed — never
  duplicated, never stranded. **Pass = TX sequence numbers reconcile.**

### Phase 5 — Main_MiSTer daemon

**Work**

5.1 Generalise `minimig_eth.cpp` → `support/ne2000/mister_ne2000.cpp` with a
    per-core profile (MAC policy, RX filtering policy, window base).
5.2 Core-name gating so the daemon only runs for cores that declare a NIC.
5.3 Regenerate the ABI header and keep `check_abi.py` in CI.
5.4 OSD-visible link status and an interface-selection override
    (`MINIMIG_ETH_IFACE` equivalent, renamed).

**Test**

- T5.1 (host) `python3 sim/check_abi.py` — every offset in the header matches
  the RTL parameters. **Pass = all checks green.**
- T5.2 (hardware) Daemon starts only for ao486 and Minimig, not for unrelated
  cores. **Pass = verified by log inspection on three cores.**
- T5.3 (hardware) `tcpdump` on the DE10-Nano host interface shows frames
  emitted by the guest with the correct source MAC, correct length, and no
  byte swapping. **Pass = a guest-generated ARP request decodes cleanly in
  Wireshark.**

### Phase 6 — Guest bring-up — **6.1a/b/c PASS on hardware 2026-08-04**

**T6.1a/b/c PASS.** DOS guest, Crynwr `NE2000.COM` v11.4.3 at int `0x60`, IRQ 11,
I/O `0x300` + mTCP `2025-01-10`, native ARM daemon `ne2000d.arm` bridging `eth0`:
the driver loaded and reported the host-provisioned MAC `52:54:05:04:FA:25`,
`dhcp` obtained a lease from the LAN server first try, and `ping` to the gateway
replied. A real driver and a real TCP/IP stack on the LAN through the FPGA NIC.

Getting there took **BF-9**, the last and deepest bug:

**BF-9 — the 64-bit wide DDR read reads back as zeros on real hardware.** A
received frame landed in packet RAM with a correct ring header but a fully zeroed
payload, so DHCP OFFERs (342 B = 2 pages) were never seen while 1-page ARP/ICMP
sometimes squeaked through. It defeated a long chain of wrong guesses because
**every layer passed in simulation** — the core-direct read, the read through the
real `iobus` + `ne2000_isa`, the multi-page ring write (lensweep). The isolation
that cracked it was a set of loopback tools driven by a daemon `--loopback`
mode: `NE2KLOOP` (read a synthetic N-byte frame back and transmit the result to
the daemon's console, past the OSD font) showed *header correct, payload all
`00`*; `NE2KMEM` (pure packet-RAM data-port round-trip, no RX/DDR) read back
`00 01 02 … 2f` perfectly — proving the data-port READ was fine and the payload
was simply never written. The only RX-payload-specific path is the mailbox
**64-bit wide DDR read** (`eth_dma_rdata64`); narrow DDR reads (heartbeat,
signature, RX length) and wide DDR *writes* (TX staging) all work, so only the
wide READ was implicated. First fix: `ne2000_core` gained `RX_WIDE_READ`,
temporarily routing RX payload through the proven narrow word path — byte-exact
but slow, which got DHCP/ping/Win95 working but overflowed the ring (and crashed
Win95) on a sustained line-rate download.

**BF-9 real root cause — a missing top-level wire, not the mailbox.** A hardware
probe (a sync slot mirroring `bg_wide_buf`, the wide-read result, into the window)
showed the wide read returning **all zeros**, pointing at the read/capture rather
than the write burst. The mailbox's 64-bit read output was simply **never
connected to the core**: `ao486.sv` left `.eth_dma_rdata64()` empty with no
`eth_dma_rdata64` wire, and `rtl/system.v` had no such input port — so the core's
`eth_dma_rdata64` was a constant zero. Narrow reads worked because they use the
16-bit `eth_dma_rdata`, which was wired. **Every sim bench passed** because they
instantiate the mux/mailbox directly and hand-wire the 64-bit bus; nothing
exercised the `ao486.sv`→`system.v` port list. Fix: declare the wire, connect the
mailbox output, pass it into the `system` instance, add the port to `system.v`,
and set `RX_WIDE_READ = 1'b1`. Fast wide RX confirmed byte-exact on hardware
(`NE2KLOOP` read back the full pattern via the wide path). Deployed as
`ao486_ne2000_20260804_widefix.rbf`.

Tools kept: daemon `--loopback [--loopsize N]`, `sw/nettest/NE2KLOOP.COM`,
`sw/nettest/NE2KMEM.COM`, and the sim benches `tb_ne2000_rx_multipage.v`,
`tb_ne2000_isa_rx.v`, `tb_ne2000_iobus_rx.v` (the last puts the real `iobus` in
the path). Suite: **pass=31 xfail=1 fail=0**. Core deployed as
`ao486_ne2000_20260804_narrowrx.rbf`.

**Work / test, in increasing order of difficulty:**

6.1 **DOS packet driver** — Crynwr/`NE2000.COM` at `0x60`, then mTCP.
  - T6.1a `ne2000 0x60 11 0x300` loads and reports the MAC. **PASS.**
  - T6.1b `dhcp.exe` obtains a lease. **PASS — lease first try.**
  - T6.1c `ping.exe` to the LAN gateway. **PASS.**
  - T6.1d `ftp.exe` pulls a 10 MB file; verify checksum against the source.
    **Pass = byte-identical, which is the real end-to-end byte-order proof.**
    (Not yet run — needs an FTP server + a longer sustained transfer, which is
    also the real stress test of the narrow RX path.)
6.2 **Windows 95/98** — in-box "Novell/Anthem NE2000 Compatible" driver.
  **Working on hardware 2026-08-04:** Windows 95 with the in-box NE2000 driver
  networks over the card. This is a much harder RX exercise than mTCP -- NDIS is
  IRQ-driven and runs a full protected-mode TCP/IP stack -- so it confirms the
  narrow-RX core (BF-9 fix) and the native daemon hold up under a real OS stack,
  not just a single-threaded DOS client. Remaining sub-checks (T6.2a-c:
  resource-conflict-free, Samba file copy with checksums, 10-min sustained
  transfer) still to be ticked off formally.
  - T6.2a Device manager shows no resource conflict.
  - T6.2b TCP/IP: browse a Samba share, copy a file both directions, verify
    checksums.
  - T6.2c Sustained transfer for 10 minutes with no IRQ storm or hang.
6.3 **Windows NT 4.0** — in-box NE2000 driver; same checks as 6.2.
6.4 **IPX** — NetWare client or a DOS IPX game; **Pass = two MiSTers, or a
    MiSTer and a PC emulator, see each other.**
6.5 **Linux** (`ne` + `8390` modules) — `ip link`, `ping`, `scp` a large file.
6.6 **Stress** — `eth_rx_flood`-style LAN broadcast storm while the guest is
    idle: **Pass = no ring corruption, no lockup, `CURR`/`BNRY` stay coherent,
    counters advance sanely.**

### Phase 7 — Performance, timing, resources

**Work**

7.1 Measure throughput (mTCP FTP, Win9x SMB copy) and CPU cost at several ao486
    CPU clock presets.
7.2 Tune: RX batching, BPF filter aggressiveness, broadcast denoise, GSO split
    thresholds — all already present in the daemon.
7.3 Close timing; if the packet RAM or the mailbox CDC is the critical path,
    consider pipelining the data port or moving the mailbox to a slower clock.
7.4 Recheck fitter headroom; make the debug aperture and any tracing
    compile-time removable for release builds.

**Test**

- T7.1 Throughput table recorded for `486DX-33MHz` and `MAX` presets.
- T7.2 `quartus_sh --flow compile ao486` with positive setup **and** hold slack.
- T7.3 Resource delta versus Phase 0 baseline documented and accepted.

### Phase 8 — Upstreaming

8.1 Core PR to `MiSTer-devel/ao486_MiSTer` (RTL + `CONF_STR` + docs).
8.2 `sys/` port additions proposed to `MiSTer-devel/Template_MiSTer` so other
    cores get the mailbox ports without forking (or drop them entirely if
    Path B won at Phase 1).
8.3 Main_MiSTer PR for the daemon.
8.4 Feed the transport findings back to `apolkosnik/Minimig-AGA_MiSTer`.
8.5 User documentation: OSD options, driver sources, per-OS setup notes.

---

## 5. Test strategy summary

| Level | Tool | What it proves | Runs when |
|---|---|---|---|
| Unit RTL | Icarus (`sim/iverilog/ne2000/`) | register semantics, ring, remote DMA, BOS, TPSR bounds, mailbox lanes | every commit |
| Refactor equivalence | ported Minimig benches vs Amiga glue | the extraction changed nothing | Phase 2 only, then as regression |
| Bus integration | Verilator system bench | ao486 I/O cycles, `bus_io32`, IRQ, `bus_wait` | every commit touching `system.v` |
| ABI | `check_abi.py` | RTL and HPS agree on every offset | every commit + CI |
| Synthesis | Quartus | fit, timing, RAM inference | before each hardware test |
| Transport hardware | DOS probe + HPS daemon | FPGA and HPS touch the same bytes | Phase 1 gate, re-run each hardware build |
| End-to-end | mTCP / Win9x / NT / Linux + tcpdump | real frames, correct byte order, no loss | Phase 6 |
| Stress | LAN broadcast flood, 10-minute transfers | ring and IRQ stability | Phase 6/7 |

Rule of thumb inherited from the Minimig effort: **every hardware claim needs a
bit the guest can read.** The debug aperture exists so that a failure can be
split into "transport dead" vs "mirror sequence wrong" vs "device model wrong"
without a logic analyser.

---

## 6. Risks

| # | Risk | Impact | Mitigation |
|---|---|---|---|
| R1 | DDR mailbox never proves out on hardware (current Minimig state) | Blocks everything | Phase 1 gate before any NIC work; Path B (`hps_ext`) as a pre-designed fallback |
| R2 | Byte-order bugs that only appear on real traffic | Silent corruption, hard to debug | `DCR.BOS` bench + Phase 6 large-file checksum test; frames stored in wire order everywhere |
| R3 | Fitter blow-up (Minimig saw 93k vs 83k nodes) | Build fails | Keep split `mem_l`/`mem_u` M10K inference; check resources at Phase 2 and Phase 3 |
| R4 | Timing regression on an already tight ao486 build | Instability | Baseline in Phase 0; timing checked at every synthesis gate; pipeline the data port if needed |
| R5 | `sys/` fork drifts from upstream Template | Merge pain forever | Propose ports upstream (8.2), or prefer Path B which needs no `sys/` change |
| R6 | Main_MiSTer PR stalls | Core unusable by end users | Ship a documented local build; keep the daemon a small, isolated, core-gated file |
| R7 | IRQ conflicts with COM2/SB/GUS in some configurations | Guest driver failures | Default IRQ 11 (currently hardwired 0); make it OSD-selectable |
| R8 | ao486 CPU too slow to keep up with LAN broadcast load | Guest becomes unusable on a busy LAN | Reuse the daemon's kernel BPF filter and broadcast denoise; measure in Phase 7 |
| R9 | Extraction changes NE2000 behaviour subtly | Regression against a working Amiga implementation | T2.1 equivalence testing against the unmodified Amiga glue |

---

## 7. Open decisions

1. **Path A vs Path B** — decided by the Phase 1 hardware gate, not by
   preference.
2. **Debug aperture in release builds** — proposed compile-time off; confirm.
3. **MAC address policy** — derived from the board MAC, stored in a config
   file, or OSD-entered? Affects the daemon and the station PROM contents.
4. **Two NICs?** Out of scope for v1, but the core should not hardwire a single
   instance.
5. **Where the reusable core lives** — `ao486_MiSTer/rtl/soc/ne2000/` for v1,
   with an eye to a standalone repo other cores can submodule (goal G2).

---

## Appendix A — NE2000 register map (page 0, for reference)

| Offset | Read | Write |
|---|---|---|
| 0x00 | CR | CR |
| 0x01 | CLDA0 | PSTART |
| 0x02 | CLDA1 | PSTOP |
| 0x03 | BNRY | BNRY |
| 0x04 | TSR | TPSR |
| 0x05 | NCR | TBCR0 |
| 0x06 | FIFO | TBCR1 |
| 0x07 | ISR | ISR |
| 0x08 | CRDA0 | RSAR0 |
| 0x09 | CRDA1 | RSAR1 |
| 0x0A | 8019ID0 (`0x50`) | RBCR0 |
| 0x0B | 8019ID1 (`0x70`) | RBCR1 |
| 0x0C | RSR | RCR |
| 0x0D | CNTR0 | TCR |
| 0x0E | CNTR1 | DCR |
| 0x0F | CNTR2 | IMR |
| 0x10 | remote DMA data port | remote DMA data port |
| 0x1F | reset | reset |

Page 1: PAR0-5, CURR, MAR0-7. Page 2 is diagnostic read-back. This matches what
`rtl/ethernet.v` already implements.

## Appendix B — Shared-window ABI (inherited, offsets from window base)

`0x1000` flags · `0x1004` register mirror · `0x104C` MAC · `0x1052` status ·
`0x1054` stats · `0x1088` HPS heartbeat · `0x108C` signature (`0xCAFEBABE`) ·
`0x1100` device state/debug mirror · `0x2000` TX buffer · `0x2600` RX buffer ·
`0x2C00` packet info (TX request addr/len/seq, RX queue head/tail) ·
`0x3000` 16KB packet-RAM backing store · `0x7000` debug · `0x9000` RX queue
payloads (16 slots).

Status bits of note: `0x0004` link up, `0x0100` FPGA sampled heartbeat,
`0x0200` signature seen, `0x0400` heartbeat non-zero, `0x0800` heartbeat
advancing, `0x1000` comm OK, `0x2000` RX active, `0x4000` TX pending.

Full definitions: `extra/minimig_eth_abi.h` in the Minimig branch.

## Appendix C — Baseline measurements

Recorded 2026-07-27 on the development host (macOS, Darwin 25.5.0).

### Repository state

| | |
|---|---|
| ao486 base | `4ba37bed0127cd03a35725f7f2917c271d5458f3` (master, 2026-07-16) |
| Working branch | `ne2000` |
| Vendored Minimig | `9598b936e35dbd38ec49388ce9b393f8550885e6` (`Ethernet_shmem2`, 2026-06-29) |

### Toolchain

| Tool | Version | Where | Status |
|---|---|---|---|
| Icarus Verilog | 13.0 (v13_0) | dev host (macOS) | working |
| Verilator | 5.050 | dev host (macOS) | working |
| Quartus Prime Lite | 17.0.0 Build 595 | `nshearman@192.168.1.65`, `/opt/altera/17.0/quartus/bin` | working |

Build host: Ubuntu 18.04, 6 cores, 7 GB RAM, 128 GB free. Quartus 17.0 is the
MiSTer-standard version. Tree is synced with:

```bash
rsync -az --delete --exclude .git --exclude releases --exclude 'sim/iverilog/ne2000/build' ./ nshearman@192.168.1.65:~/ao486_ne2000/
```

Long compiles must be run detached (`nohup ... &`) and polled — the SSH tool
times out well before a full compile finishes.

### NE2000 core, synthesised standalone (Cyclone V 5CSEBA6U23I7)

| Metric | Value |
|---|---|
| Registers | 6,238 |
| Block memory bits | 131,072 (16 KB packet RAM) |
| Packet RAM mapping | 2 × M10K, true dual port, 8192 × 8 — none in logic |
| ALMs | not reported by Analysis & Synthesis alone; comes from the Phase 3 fit |

### Simulation baseline

| Suite | Result |
|---|---|
| Vendored NE2000 benches (`make -C sim/iverilog/ne2000 baseline`) | pass=18, xfail=1 (BF-1), fail=0, skipped=3 (BF-2) — exit 0 |
| `sim/iverilog/pic` (upstream) | does not build under Icarus 13 (BF-2) |
| Verilator lint `rtl/soc/iobus.v`, `rtl/soc/pic.v` | clean |

### Synthesis baseline — CAPTURED 2026-07-27

Stock tree (nothing NE2000 in `files.qip`), `quartus_sh --flow compile ao486`,
Quartus 17.0.0 Lite, device 5CSEBA6U23I7. Reports preserved on the build host at
`/tmp/ne2k_baseline/`.

| Metric | Baseline | Of available |
|---|---|---|
| Logic utilization (ALMs) | 34,679 | 41,910 (**83 %**) |
| Total registers | 34,751 | |
| Block memory bits | 3,235,560 | 5,662,720 (57 %) |
| RAM blocks (M10K) | 436 | 553 (**79 %**) |
| DSP blocks | 41 | 112 (37 %) |
| PLLs | 3 | 6 |
| `.rbf` | 4,190,484 bytes | |
| Fitter | Successful | |

Worst setup slack by clock (Slow 1100 mV 85 °C):

| Clock | Slack | TNS |
|---|---|---|
| `emu\|pll ... counter[0]\|divclk` (CPU) | **-6.829 ns** | -20,695.823 |
| `pll_hdmi ... counter[0]\|divclk` | +0.231 ns | 0 |
| `emu\|pll ... counter[4]\|divclk` | +0.998 ns | 0 |
| `sysmem ... h2f_user0_clk` | +1.371 ns | 0 |

**The stock tree does not meet timing on the CPU clock domain.** This is
upstream master with no NE2000 in it, so it is a property of ao486 as it ships,
not of this work — the core's fastest CPU presets are documented as unstable and
the OSD says so. Two consequences for this plan:

1. The T3.5 and T7.2 pass criterion cannot be "positive slack". It is **"no
   worse than baseline"**: `-6.829 ns` worst setup and `-20,695.823` TNS on
   `counter[0]`, with every other domain staying positive.
2. Headroom is genuinely tight: 83 % ALMs and 79 % M10K before adding anything.
   The NE2000 core needs 2 M10K for packet RAM (measured standalone), which is
   affordable, but the ALM cost is the number to watch in T3.5.

## Appendix D — Source inventory

Reused (from `apolkosnik/Minimig-AGA_MiSTer` @ `Ethernet_shmem2`, `9598b93`,
GPL — attribution and licence text must be carried over):
`rtl/ethernet.v`, `rtl/eth_ddr3_mailbox.v`, `rtl/eth_avalon_arbiter.v`,
`rtl/eth_dma_addr_map.v`, `extra/minimig_eth.cpp`, `extra/minimig_eth.h`,
`extra/minimig_eth_abi.h`, `sim/eth_*_tb.v`, `sim/check_eth_abi.py`,
`NE2000_HPS_FPGA_COMM_PLAN.md` (design rationale).

New in ao486: `rtl/soc/ne2000/ne2000_core.v`, `ne2000_isa.v`, `ne2000.qip`,
transport module (Path A or B), `sim/iverilog/ne2000/*`, `sw/nettest/probe.c`,
`rtl/system.v` and `ao486.sv` edits, optional `sys/` fork.

Upstream references:
- ao486 core — https://github.com/MiSTer-devel/ao486_MiSTer
- Minimig Ethernet branch — https://github.com/apolkosnik/Minimig-AGA_MiSTer/tree/Ethernet_shmem2
- MiSTer networking wiki — https://github.com/MiSTer-devel/Main_MiSTer/wiki/Internet-and-console-connection-from-supported-cores
- NE2000 NIC discussion — https://misterfpga.org/viewtopic.php?p=100179
