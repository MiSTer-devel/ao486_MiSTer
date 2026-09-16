# NE2000 simulation harness

Everything here drives `rtl/soc/ne2000/ne2000_core.v` through its generic host
port. There is no Amiga bus anywhere in the build — this is an ao486-only tree.

```bash
make check
```

Runs `regression/*_tb.v` plus every local `tb_*.v`. Exits non-zero on any
deviation from the expected result, including a known-fail bench that starts
passing.

Current: **pass=20 xfail=1 fail=0**. The xfail is BF-1, a defect present in the
imported device model (see `NE2000_AO486_PLAN.md`, Phase 0 baseline findings).

## `regression/` — converted Minimig benches

19 benches converted once from the vendored Minimig suite (ring wrap, RX flood,
length sweep, batching, concurrency, data-port contention, ACK starvation,
station MAC, status-write CDC, memory tests, mailbox lanes). They now instantiate
`ne2000_core` directly instead of the Amiga `ethernet_interface`; stimuli and
assertions are otherwise unchanged from the originals.

Two mechanical adaptations, noted in each file's header:

1. Port names follow the host port (`cpu_as` → `host_cyc_n`, `cpu_uds/lds` →
   `host_be_hi_n/host_be_lo_n`, `dtack_eth` → `host_ack_n`, and so on).
2. `DCR.BOS` is set where the originals left it clear. `ne2000_core` defaults to
   standard DP8390 byte-order polarity (`BOS_INVERT=1`), the opposite of the
   imported behaviour (finding BF-5), so setting BOS keeps the *physical* byte
   order under test identical — the data expectations never changed.

The vendored originals (apolkosnik/Minimig-AGA_MiSTer, branch Ethernet_shmem2,
commit 9598b936, GPL) are not carried in this tree; see `NE2000_AO486_PLAN.md`
for the extraction record.

Three vendored benches were dropped, not converted: they instantiate `gary`,
`cpu_wrapper` and `amiga_clk`, i.e. they test the Amiga glue that ao486 replaces.
Their ao486 counterparts are the Phase 3 benches T3.1–T3.3.

## Local benches

Drop `tb_<name>.v` here and run:

```bash
make tb_<name>
```

| Bench | Phase | Proves |
|---|---|---|
| `tb_ne2000_bos.v` | 2 | ✅ `DCR.BOS` byte order, standard polarity (T2.2) |
| `tb_ne2000_tpsr.v` | 2 | ✅ `TPSR=0x40` with `PSTART=0x46` transmits (T2.3) |
| `tb_ne2000_isa.v` | 3 | ✅ ISA port decode, 16-bit data port, reset port, IRQ (T3.1, T3.3) |
| `tb_ne2000_iobus.v` | 3 | ✅ attach through the real `iobus.v`: cs timing, `bus_wait`, `bus_io32` (T3.2) |
| `tb_ne2000_timeout.v` | 4 | every blocking handshake escapes a stalled transport (T4.2) |

## Notes

- Icarus Verilog 13.0 and Verilator 5.050 verified on this tree.
- The mailbox/arbiter benches compile against the transport RTL under
  `rtl/soc/ne2000/`.
- The pre-existing ao486 benches under `sim/iverilog/*` do not build with modern
  Icarus (finding BF-2). System-level ao486 bus benches go on Verilator (T3.2).
- `build/` is scratch and git-ignored.
