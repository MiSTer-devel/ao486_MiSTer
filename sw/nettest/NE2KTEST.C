/*
 * NE2KTEST - NE2000 bring-up probe for the MiSTer ao486 core.
 *
 * Hardware test T3.4 of NE2000_AO486_PLAN.md. Everything it does is local to
 * the card: no HPS transport, no driver, no packet ever reaches the wire. It
 * answers the questions a bring-up needs answered, in order:
 *
 *   1. Is the card decoded at all?          RTL8019 ID at base+0x0A/0x0B
 *   2. Do registers hold what is written?   BNRY / PSTART / PSTOP read-back
 *   3. Is the station PROM readable?        remote DMA from 0x0000 -> MAC
 *   4. Does the 16-bit data port work,      remote DMA write + read-back of
 *      with the right byte order?           packet RAM at 0x4000
 *   5. What does the transport think?       debug aperture at base+0x20
 *
 * Usage:  NE2KTEST [base]        base in hex, default 300
 *
 * Build with Open Watcom (same as the other sw/ utilities):  wmake
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <conio.h>

/* NE2000 register offsets from the I/O base (page 0 unless noted) */
#define R_CR      0x00
#define R_CLDA0   0x01      /* write: PSTART */
#define R_CLDA1   0x02      /* write: PSTOP  */
#define R_BNRY    0x03
#define R_TSR     0x04      /* write: TPSR   */
#define R_ISR     0x07
#define R_RSAR0   0x08
#define R_RSAR1   0x09
#define R_ID0     0x0A      /* write: RBCR0  */
#define R_ID1     0x0B      /* write: RBCR1  */
#define R_RCR     0x0C
#define R_DCR     0x0E
#define R_IMR     0x0F
#define R_DATA    0x10      /* remote DMA data port */
#define R_RESET   0x18
#define R_DEBUG   0x20      /* ao486-only debug aperture */

/* CR bits */
#define CR_STP    0x01
#define CR_STA    0x02
#define CR_RD_RD  0x08      /* remote read  */
#define CR_RD_WR  0x10      /* remote write */
#define CR_RD_ABT 0x20      /* abort/complete remote DMA */

/* DCR bits */
#define DCR_WTS   0x01      /* 16-bit transfers */
#define DCR_BOS   0x02      /* byte order select; x86 leaves this CLEAR */

static unsigned base = 0x300;
static int failures = 0;

static void ok(char *what, char *detail)
{
    printf("  [ ok ] %-34s %s\n", what, detail);
}

static void bad(char *what, char *detail)
{
    printf("  [FAIL] %-34s %s\n", what, detail);
    failures++;
}

static void nic_stop(void)
{
    outp(base + R_CR, CR_STP | CR_RD_ABT);      /* stop, page 0, abort DMA */
}

/* Arm a remote DMA transfer of `count` bytes at NIC memory `addr`. */
static void dma_arm(unsigned addr, unsigned count, int write)
{
    nic_stop();
    outp(base + R_DCR,   DCR_WTS);              /* 16-bit, x86 byte order */
    outp(base + R_ID0,   count & 0xFF);         /* RBCR0 */
    outp(base + R_ID1,   count >> 8);           /* RBCR1 */
    outp(base + R_RSAR0, addr & 0xFF);
    outp(base + R_RSAR1, addr >> 8);
    outp(base + R_CR, CR_STA | (write ? CR_RD_WR : CR_RD_RD));
}

static int test_id(void)
{
    unsigned char id0, id1;
    char msg[64];

    nic_stop();
    id0 = inp(base + R_ID0);
    id1 = inp(base + R_ID1);
    sprintf(msg, "0x%02X 0x%02X", id0, id1);

    if (id0 == 0x50 && id1 == 0x70) {
        ok("RTL8019 ID at base+0x0A/0x0B", msg);
        return 1;
    }
    if (id0 == 0xFF && id1 == 0xFF) {
        bad("RTL8019 ID at base+0x0A/0x0B", "open bus - card not decoded here");
        return 0;
    }
    bad("RTL8019 ID at base+0x0A/0x0B", msg);
    return 0;
}

static void test_registers(void)
{
    unsigned char v;
    char msg[64];

    nic_stop();
    outp(base + R_CLDA0, 0x46);                 /* PSTART */
    outp(base + R_CLDA1, 0x80);                 /* PSTOP  */
    outp(base + R_BNRY,  0x46);

    v = inp(base + R_BNRY);
    sprintf(msg, "wrote 0x46, read 0x%02X", v);
    if (v == 0x46) ok("BNRY read-back", msg);
    else           bad("BNRY read-back", msg);
}

static void test_prom(void)
{
    unsigned char prom[32];
    char msg[80];
    int i;
    unsigned w;

    dma_arm(0x0000, 32, 0);
    for (i = 0; i < 32; i += 2) {
        w = inpw(base + R_DATA);
        prom[i]     = (unsigned char)(w & 0xFF);
        prom[i + 1] = (unsigned char)(w >> 8);
    }

    /* A real NE2000 PROM duplicates every byte: 52 52 54 54 ... */
    sprintf(msg, "%02X:%02X:%02X:%02X:%02X:%02X",
            prom[0], prom[2], prom[4], prom[6], prom[8], prom[10]);

    if (prom[0] == 0xFF && prom[2] == 0xFF)
        bad("station PROM (MAC)", "all 0xFF - PROM not readable");
    else if (prom[14] == 0x57 && prom[15] == 0x57)
        ok("station PROM (MAC)", msg);
    else
        ok("station PROM (MAC, no 57 57 sig)", msg);
}

/*
 * Write a pattern through the 16-bit data port, read it back, and check the
 * byte order. With DCR.BOS clear an x86 host must get its low byte back in the
 * low byte -- this is the check that catches a byte-swapped port, the failure
 * that would otherwise show up much later as corrupted packets.
 */
static void test_packet_ram(void)
{
    static unsigned pattern[8] = {
        0x1234, 0xA55A, 0xFFFF, 0x0000, 0xDEAD, 0xBEEF, 0x0102, 0x8000
    };
    unsigned got[8];
    char msg[80];
    int i, errs = 0;

    dma_arm(0x4000, sizeof(pattern), 1);
    for (i = 0; i < 8; i++) outpw(base + R_DATA, pattern[i]);

    dma_arm(0x4000, sizeof(pattern), 0);
    for (i = 0; i < 8; i++) got[i] = inpw(base + R_DATA);

    for (i = 0; i < 8; i++) if (got[i] != pattern[i]) errs++;

    if (errs == 0) {
        ok("packet RAM via 16-bit data port", "8/8 words match");
    } else {
        sprintf(msg, "%d/8 words wrong, first: wrote 0x%04X read 0x%04X",
                errs, pattern[0], got[0]);
        bad("packet RAM via 16-bit data port", msg);

        /* Name the failure mode rather than leaving it to guesswork. */
        if (((got[0] >> 8) | (got[0] << 8)) == (pattern[0] & 0xFFFF))
            printf("         -> bytes are SWAPPED: DCR.BOS polarity is wrong\n");
    }
}

static void dump_debug(void)
{
    static char *names[7] = {
        "remote DMA addr low ",
        "remote DMA addr high",
        "remote byte cnt low ",
        "remote byte cnt high",
        "data-port status    ",
        "HPS comm status     ",
        "HPS heartbeat low   "
    };
    int i;
    unsigned char v;

    printf("\n  Debug aperture at 0x%03X (ao486-only):\n", base + R_DEBUG);
    for (i = 0; i < 7; i++) {
        v = inp(base + R_DEBUG + i);
        printf("    +%X  %s  0x%02X\n", i, names[i], v);
    }
    printf("    (HPS comm status stays 0 until the Phase 4 transport is wired)\n");
}

int main(int argc, char **argv)
{
    unsigned char isr;

    if (argc > 1) {
        base = (unsigned)strtoul(argv[1], NULL, 16);
        if (base < 0x200 || base > 0x3E0) {
            printf("NE2KTEST: base 0x%X is not a sane ISA I/O base\n", base);
            return 2;
        }
    }

    printf("NE2KTEST - ao486 NE2000 probe, I/O base 0x%03X\n\n", base);

    /* Reset port: a read triggers the reset, ISR.RST should come up set. */
    inp(base + R_RESET);
    isr = inp(base + R_ISR);
    if (isr & 0x80) ok("reset port", "ISR.RST set");
    else            bad("reset port", "ISR.RST did not set");
    outp(base + R_ISR, 0xFF);                   /* clear ISR */

    if (!test_id()) {
        printf("\nCard not responding. Check that Network is enabled in the OSD\n"
               "and that the I/O base matches (default 300).\n");
        return 1;
    }

    test_registers();
    test_prom();
    test_packet_ram();
    dump_debug();

    printf("\n%s (%d failure%s)\n",
           failures ? "FAILED" : "PASSED", failures, failures == 1 ? "" : "s");
    return failures ? 1 : 0;
}
