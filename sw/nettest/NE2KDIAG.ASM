; NE2KDIAG.COM - combined NE2000 diagnostic suite for the MiSTer ao486 core.
;
; Modelled on the A2065 project's Lance-Test (Commodore's official LANCE
; manufacturing diagnostic, see ~/Development/amiga/A2065/lance-test) and its
; `diags` command: several chip-only self-tests, each PASS/FAIL, one verdict
; at the end. Everything here is local to the card -- no HPS transport, no
; packet driver, nothing reaches the wire -- so a failure has one meaning.
;
;   1. buffer memory   packet RAM (0x4000-0x7FFF) pattern test: incrementing
;                       words, then 0x5555/0xAAAA and 0xAAAA/0x5555
;                       alternating, written and read back through the
;                       16-bit remote-DMA data port
;   2. interrupt        hooks IRQ11 (INT 0x73), forces a TCR.LB=01 internal
;                       loopback transmit with IMR.PTXE|PRXE enabled, checks
;                       the handler actually runs
;   3. internal loopback  TCR.LB=01: send/receive N small frames entirely
;                       inside the chip, byte-exact readback each time -- the
;                       RTL fix this test proves is the local packet-RAM copy
;                       added to ne2000_core.v (BG_LOOP_* states)
;
;   Usage:  NE2KDIAG [base]      base in hex, default 300
;
;   Build:  nasm -f bin -o NE2KDIAG.COM NE2KDIAG.ASM
;
; Not yet run on real hardware -- assembled and reviewed only. Test 2 touches
; the PIC and the IVT; it saves and restores both unconditionally (including
; on a timeout), so a failure there should never leave DOS in a bad state,
; but treat a first run the way any new bring-up tool gets treated: watch it.

BITS 16
ORG 0x100

%define DEF_BASE 0x300
%define LOOP_LEN 32             ; loopback frame size, bytes (even)
%define LOOP_COUNT 20           ; loopback iterations

; ---------------------------------------------------------------------------
start:
        cld
        call    parse_cmdline

        mov     dx, m_banner
        call    putstr
        mov     ax, [base]
        call    puthex16
        call    crlf
        call    crlf

        ; Card presence gate, same shape as NE2KTEST: no point running the
        ; suite against a card that isn't decoded.
        mov     bx, 0x00
        mov     al, 0x21                ; CR: stop, page 0, abort DMA
        call    outb_off
        mov     bx, 0x0A
        call    inb_off
        cmp     al, 0x50
        jne     .no_card
        mov     bx, 0x0B
        call    inb_off
        cmp     al, 0x70
        jne     .no_card

        call    test_membuf
        call    test_irq
        call    test_loop
        jmp     .finish

.no_card:
        mov     dx, m_nocard
        call    putstr
        call    bump_fail
.finish:
        call    summary
        mov     al, [fails]
        cmp     al, 0
        je      .exit_ok
        mov     al, 1
.exit_ok:
        mov     ah, 0x4C
        int     0x21

; ---------------------------------------------------------------------------
; Port helper: BX = offset from base  ->  DX = absolute port
setport:
        mov     dx, [base]
        add     dx, bx
        ret

outb_off:                               ; write AL to base+BX
        push    ax
        call    setport
        pop     ax
        out     dx, al
        ret

inb_off:                                ; read base+BX into AL
        call    setport
        in      al, dx
        ret

short_delay:
        push    cx
        mov     cx, 0x0400
.spin:  loop    .spin
        pop     cx
        ret

; ---------------------------------------------------------------------------
; Arm remote DMA: AX = NIC address, CX = byte count, BL = 0 read / 1 write,
; BH = DCR value. Same helper as NE2KTEST.ASM.
arm_dma:
        push    ax
        push    cx
        push    bx

        mov     [tmp_addr], ax
        mov     [tmp_cnt], cx
        mov     [tmp_dir], bl
        mov     [tmp_dcr], bh

        mov     bx, 0x00
        mov     al, 0x21
        call    outb_off
        mov     bx, 0x0E
        mov     al, [tmp_dcr]
        call    outb_off
        mov     bx, 0x0A
        mov     al, [tmp_cnt]
        call    outb_off
        mov     bx, 0x0B
        mov     al, [tmp_cnt+1]
        call    outb_off
        mov     bx, 0x08
        mov     al, [tmp_addr]
        call    outb_off
        mov     bx, 0x09
        mov     al, [tmp_addr+1]
        call    outb_off

        mov     bx, 0x00
        mov     al, 0x0A                ; STA | RD0 (remote read)
        cmp     byte [tmp_dir], 0
        je      .go
        mov     al, 0x12                ; STA | RD1 (remote write)
.go:
        call    outb_off
        call    short_delay

        pop     bx
        pop     cx
        pop     ax
        ret

; ---------------------------------------------------------------------------
; Test 1: buffer memory pattern test (Lance-Test Test 1 equivalent).
; The card is CR-stopped (STA=0) for the whole test, same reasoning as Lance:
; with the receiver/transmitter idle, packet RAM is exclusively the host's.
test_membuf:
        mov     dx, m_membuf
        call    putstr

        mov     bx, 0x00
        mov     al, 0x21                ; CR: stop
        call    outb_off

        ; total_mismatch accumulates across phases; membuf_verify uses BP as
        ; its OWN per-phase counter and returns with it still loaded, so
        ; accumulating in BP here would double-count -- use memory instead.
        mov     word [total_mismatch], 0

        mov     byte [phase], 0
        call    membuf_write
        call    membuf_verify
        mov     ax, [mismatch]
        add     [total_mismatch], ax

        mov     byte [phase], 1
        call    membuf_write
        call    membuf_verify
        mov     ax, [mismatch]
        add     [total_mismatch], ax

        mov     byte [phase], 2
        call    membuf_write
        call    membuf_verify
        mov     ax, [mismatch]
        add     [total_mismatch], ax

        cmp     word [total_mismatch], 0
        jne     .bad
        mov     dx, m_ok
        call    putstr
        ret
.bad:
        mov     dx, m_bad
        call    putstr
        call    bump_fail
        ret

; Pattern for word index CX (0..8191), phase 0/1/2 from [phase] -> AX.
;   phase 0: incrementing, word[n] = n * 0x1001 (mod 65536)
;   phase 1: 0x5555/0xAAAA alternating (even/odd)
;   phase 2: 0xAAAA/0x5555 alternating (the complement of phase 1)
pattern_word:
        cmp     byte [phase], 0
        jne     .p1
        mov     ax, cx
        mov     dx, 0x1001
        mul     dx
        ret
.p1:
        cmp     byte [phase], 1
        jne     .p2
        test    cl, 1
        jz      .a5555
        mov     ax, 0xAAAA
        ret
.a5555:
        mov     ax, 0x5555
        ret
.p2:
        test    cl, 1
        jz      .aAAAA
        mov     ax, 0x5555
        ret
.aAAAA:
        mov     ax, 0xAAAA
        ret

; Write the whole 16KB packet RAM (8192 words) with pattern_word().
membuf_write:
        mov     ax, 0x4000
        mov     cx, 0x4000              ; byte count
        mov     bx, 0x0101              ; write, DCR word mode
        call    arm_dma

        xor     cx, cx
.loop:
        call    pattern_word
        push    cx
        push    ax
        mov     bx, 0x10
        call    setport
        pop     ax
        out     dx, ax
        pop     cx
        inc     cx
        cmp     cx, 0x2000
        jb      .loop
        call    short_delay
        ret

; Read the whole 16KB back and compare against pattern_word(); mismatch
; count -> [mismatch].
membuf_verify:
        mov     ax, 0x4000
        mov     cx, 0x4000
        mov     bx, 0x0100              ; read
        call    arm_dma

        xor     cx, cx
        xor     bp, bp
.loop:
        push    cx
        call    pattern_word            ; AX = expected
        push    ax
        mov     bx, 0x10
        call    setport
        in      ax, dx                  ; AX = got
        pop     dx                      ; DX = expected
        cmp     ax, dx
        je      .ok
        inc     bp
.ok:
        pop     cx
        inc     cx
        cmp     cx, 0x2000
        jb      .loop
        mov     [mismatch], bp
        ret

; ---------------------------------------------------------------------------
; Test 2: interrupt test (Lance-Test Test 3 equivalent). Forces a TCR.LB=01
; internal-loopback transmit with IMR enabled and checks IRQ11 actually
; reaches a handler we install for the duration.
test_irq:
        mov     dx, m_irq
        call    putstr

        in      al, 0x21
        mov     [pic1_mask], al
        in      al, 0xA1
        mov     [pic2_mask], al
        call    install_isr

        in      al, 0xA1                ; unmask IRQ11 (slave bit 3)
        and     al, 0xF7
        out     0xA1, al
        in      al, 0x21                ; unmask IRQ2 cascade (master bit 2)
        and     al, 0xFB
        out     0x21, al

        mov     word [irq_count], 0

        mov     bx, 0x00
        mov     al, 0x21                ; CR: stop
        call    outb_off
        mov     bx, 0x0C
        mov     al, 0x04                ; RCR: enable (latches rx_poll_enabled)
        call    outb_off
        mov     bx, 0x01
        mov     al, 0x46                ; PSTART
        call    outb_off
        mov     bx, 0x02
        mov     al, 0x80                ; PSTOP
        call    outb_off

        ; BNRY = CURR-1 (standard DP8390 convention -- see bnry_from_curr),
        ; not a fixed PSTART constant -- see test_loop for why (defensive
        ; here too: this runs before test_loop today, but nothing should
        ; depend on that ordering).
        mov     bx, 0x00
        mov     al, 0x62                ; CR: page1
        call    outb_off
        mov     bx, 0x07
        call    inb_off                 ; AL = CURR
        mov     [curr_before], al
        mov     bx, 0x00
        mov     al, 0x21                ; CR: page0, stop
        call    outb_off
        call    bnry_from_curr          ; AL = CURR-1, wrapped
        mov     bx, 0x03
        call    outb_off

        mov     bx, 0x0D
        mov     al, 0x02                ; TCR: LB=01 internal loopback
        call    outb_off
        mov     bx, 0x07
        mov     al, 0xFF                ; clear ISR
        call    outb_off
        mov     bx, 0x0F
        mov     al, 0x03                ; IMR: PRXE | PTXE
        call    outb_off

        mov     ax, 0x4000
        mov     cx, 32
        mov     bx, 0x0101
        call    arm_dma
        mov     cx, 16
.wfill:
        push    cx
        mov     bx, 0x10
        call    setport
        mov     ax, 0x1234
        out     dx, ax
        pop     cx
        loop    .wfill

        mov     bx, 0x04
        mov     al, 0x40                ; TPSR
        call    outb_off
        mov     bx, 0x05
        mov     al, 32                  ; TBCR0
        call    outb_off
        mov     bx, 0x06
        mov     al, 0                   ; TBCR1
        call    outb_off
        mov     bx, 0x00
        mov     al, 0x26                ; CR: STA | TXP
        call    outb_off

        mov     cx, 4000
.wait:
        cmp     word [irq_count], 0
        jne     .done
        push    cx
        call    short_delay
        pop     cx
        loop    .wait
.done:
        ; Mask the card BEFORE handing the vector back and unmasking the PIC:
        ; IMR was left enabling PRXE|PTXE and nothing here ever cleared it, so
        ; a card that fires again after this test would assert IRQ11 into
        ; whatever vector was there originally -- which knows nothing about
        ; the NE2000 and won't clear the source. Order matters: clear the
        ; source first, or there's a window where it's still live against the
        ; restored (foreign) vector.
        mov     bx, 0x0F
        mov     al, 0x00                ; IMR: disable
        call    outb_off
        mov     bx, 0x07
        mov     al, 0xFF                ; clear ISR
        call    outb_off

        mov     al, [pic1_mask]
        out     0x21, al
        mov     al, [pic2_mask]
        out     0xA1, al
        call    restore_isr
        mov     bx, 0x0D
        mov     al, 0x00                ; TCR: normal
        call    outb_off

        cmp     word [irq_count], 0
        jne     .ok
        mov     dx, m_bad
        call    putstr
        call    bump_fail
        ret
.ok:
        mov     dx, m_ok
        call    putstr
        ret

; Install irq_handler at INT 0x73 (IRQ11 on the AT cascade mapping),
; saving the previous vector.
install_isr:
        push    es
        xor     ax, ax
        mov     es, ax
        cli
        mov     ax, [es:0x1CC]
        mov     [old_isr_off], ax
        mov     ax, [es:0x1CE]
        mov     [old_isr_seg], ax
        mov     word [es:0x1CC], irq_handler
        mov     ax, cs
        mov     [es:0x1CE], ax
        sti
        pop     es
        ret

restore_isr:
        push    es
        xor     ax, ax
        mov     es, ax
        cli
        mov     ax, [old_isr_off]
        mov     [es:0x1CC], ax
        mov     ax, [old_isr_seg]
        mov     [es:0x1CE], ax
        sti
        pop     es
        ret

; ISR: read ISR (write-1-to-clear the bits seen), count it, EOI both PICs.
irq_handler:
        push    ax
        push    bx
        push    dx
        push    ds
        mov     ax, cs
        mov     ds, ax

        mov     bx, 0x07
        call    inb_off                 ; AL = ISR
        or      al, al
        jz      .no_bits
        push    ax
        mov     bx, 0x07
        call    outb_off                ; clear the bits we saw
        pop     ax
        inc     word [irq_count]
.no_bits:
        mov     al, 0x20
        out     0xA0, al                ; EOI slave
        out     0x20, al                ; EOI master

        pop     ds
        pop     dx
        pop     bx
        pop     ax
        iret

; ---------------------------------------------------------------------------
; Test 3: internal loopback (Lance-Test Test 2/5 equivalent) -- the test the
; ne2000_core.v BG_LOOP_* fix exists for. LOOP_COUNT frames, each byte-exact
; verified through the real remote-DMA data port.
test_loop:
        mov     dx, m_loop
        call    putstr

        mov     bx, 0x00
        mov     al, 0x21                ; CR: stop
        call    outb_off
        mov     bx, 0x0C
        mov     al, 0x04                ; RCR: enable
        call    outb_off
        mov     bx, 0x01
        mov     al, 0x46                ; PSTART
        call    outb_off
        mov     bx, 0x02
        mov     al, 0x80                ; PSTOP
        call    outb_off

        ; BNRY must mark the ring EMPTY relative to wherever CURR actually is
        ; right now, not a fixed PSTART constant -- test_irq leaves RCR/STA
        ; enabled with TCR back to normal during its own cleanup, so real LAN
        ; traffic keeps draining into this ring in the gap before this test
        ; re-engages loopback. A hardcoded BNRY=PSTART made the ring look
        ; almost entirely full to loop_ring_full_calc the moment CURR had
        ; already moved from real traffic (found on hardware: ISR.OVW set,
        ; CURR at 0x7F out of a PSTART..PSTOP range of 0x46..0x80, loopback
        ; silently skipped, guest polls forever for a PRX that never comes).
        ;
        ; BNRY = CURR-1, not BNRY = CURR: an equal producer/consumer index is
        ; genuinely ambiguous in a circular ring (could mean empty OR full),
        ; and ring_page_distance(from, from, ...) resolves that as 0 free --
        ; i.e. FULL, the opposite of what was intended (confirmed on hardware:
        ; BNRY==CURR==0x7F, ISR.OVW still set, still times out). BNRY trailing
        ; CURR by exactly one page is the standard DP8390 convention -- it's
        ; the exact relationship the reset default already uses
        ; (BNRY=PSTART, CURR=PSTART+1) -- and removes the ambiguity entirely.
        mov     bx, 0x00
        mov     al, 0x62                ; CR: page1
        call    outb_off
        mov     bx, 0x07
        call    inb_off                 ; AL = CURR
        mov     [curr_before], al
        mov     bx, 0x00
        mov     al, 0x21                ; CR: page0, stop
        call    outb_off
        call    bnry_from_curr          ; AL = CURR-1, wrapped
        mov     bx, 0x03
        call    outb_off

        mov     bx, 0x0D
        mov     al, 0x02                ; TCR: LB=01 internal loopback
        call    outb_off
        mov     bx, 0x07
        mov     al, 0xFF                ; clear ISR
        call    outb_off
        mov     bx, 0x00
        mov     al, 0x22                ; CR: STA, page 0
        call    outb_off

        mov     word [loop_iter], 0
.iter:
        mov     ax, [loop_iter]
        mov     [frame_seed], al

        mov     bx, 0x00
        mov     al, 0x62                ; CR: page 1
        call    outb_off
        mov     bx, 0x07
        call    inb_off                 ; AL = CURR
        mov     [curr_before], al
        mov     bx, 0x00
        mov     al, 0x22                ; CR: page 0, STA
        call    outb_off

        mov     ax, 0x4000
        mov     cx, LOOP_LEN
        mov     bx, 0x0101
        call    arm_dma
        mov     byte [bidx], 0
        mov     cx, LOOP_LEN/2
.wr:
        push    cx
        call    calc_byte               ; AL = byte(bidx)
        mov     bl, al
        inc     byte [bidx]
        call    calc_byte               ; AL = byte(bidx+1)
        mov     ah, al
        mov     al, bl
        inc     byte [bidx]
        push    ax
        mov     bx, 0x10
        call    setport
        pop     ax
        out     dx, ax
        pop     cx
        loop    .wr

        mov     bx, 0x04
        mov     al, 0x40                ; TPSR
        call    outb_off
        mov     bx, 0x05
        mov     al, LOOP_LEN            ; TBCR0
        call    outb_off
        mov     bx, 0x06
        mov     al, 0                   ; TBCR1
        call    outb_off
        mov     bx, 0x00
        mov     al, 0x26                ; CR: STA | TXP
        call    outb_off

        mov     cx, 4000
.wp:
        mov     bx, 0x07
        call    inb_off
        and     al, 0x03
        cmp     al, 0x03
        je      .got
        push    cx
        call    short_delay
        pop     cx
        loop    .wp
        mov     dx, m_loop_timeout
        call    putstr
        mov     ax, [loop_iter]
        call    puthex16
        call    crlf
        jmp     .fail
.got:
        mov     bx, 0x07
        mov     al, 0xFF                ; clear ISR
        call    outb_off

        mov     al, 0x04
        mov     ah, [curr_before]
        mov     cx, LOOP_LEN
        mov     bx, 0x0100              ; read
        call    arm_dma

        ; Store the raw received words first (no live compare) so a mismatch
        ; can be dumped in full -- diagnosing "how" it's wrong, not just that
        ; it is. This is a real-hardware-only failure: the bare ne2000_core
        ; testbench (tb_ne2000_loopback.v) proved this byte-exact, but that
        ; harness bypasses ne2000_isa/iobus entirely, so a bug specific to the
        ; real bus glue driven by the actual x86 CPU wouldn't show there.
        mov     di, got_buf
        mov     cx, LOOP_LEN/2
.rd:
        push    cx
        mov     bx, 0x10
        call    setport
        in      ax, dx
        stosw
        pop     cx
        loop    .rd

        mov     byte [bidx], 0
        mov     di, exp_buf
        mov     cx, LOOP_LEN
.expfill:
        call    calc_byte
        stosb
        inc     byte [bidx]
        loop    .expfill

        mov     si, got_buf
        mov     di, exp_buf
        mov     cx, LOOP_LEN
        xor     bp, bp
.cmp:
        lodsb
        mov     ah, al
        mov     al, [di]
        inc     di
        cmp     al, ah
        je      .cok
        inc     bp
.cok:
        loop    .cmp

        cmp     bp, 0
        je      .iter_ok
        mov     dx, m_loop_mismatch
        call    putstr
        mov     ax, [loop_iter]
        call    puthex16
        call    crlf
        mov     dx, m_exp
        call    putstr
        mov     si, exp_buf
        mov     cx, LOOP_LEN
        call    dump_bytes
        mov     dx, m_got
        call    putstr
        mov     si, got_buf
        mov     cx, LOOP_LEN
        call    dump_bytes
        jmp     .fail
.iter_ok:
        inc     word [loop_iter]
        cmp     word [loop_iter], LOOP_COUNT
        jb      .iter

        mov     bx, 0x0D
        mov     al, 0x00                ; TCR: normal
        call    outb_off
        mov     dx, m_ok
        call    putstr
        ret
.fail:
        mov     bx, 0x0D
        mov     al, 0x00                ; TCR: normal, even on failure
        call    outb_off
        mov     dx, m_bad
        call    putstr
        call    bump_fail
        ret

; Print CX hex bytes from DS:SI, space-separated, then CRLF.
dump_bytes:
.d:
        lodsb
        push    cx
        push    si
        call    puthex8
        mov     dl, ' '
        call    putch
        pop     si
        pop     cx
        loop    .d
        call    crlf
        ret

; AL = [curr_before] - 1, wrapped PSTART->PSTOP-1 (ring is PSTART=0x46,
; PSTOP=0x80 throughout this tool). BNRY trailing CURR by exactly one page
; is the standard DP8390 convention (see the callers for why BNRY==CURR is
; wrong, not just untested).
bnry_from_curr:
        mov     al, [curr_before]
        cmp     al, 0x46                ; PSTART
        jne     .no_wrap
        mov     al, 0x7F                ; PSTOP - 1
        ret
.no_wrap:
        dec     al
        ret

; AL = pattern byte for byte-index [bidx], seeded by [frame_seed].
calc_byte:
        mov     al, [bidx]
        add     al, [frame_seed]
        xor     al, 0x5A
        ret

; ---------------------------------------------------------------------------
summary:
        call    crlf
        mov     al, [fails]
        cmp     al, 0
        jne     .failed
        mov     dx, m_passed
        call    putstr
        ret
.failed:
        mov     dx, m_failed
        call    putstr
        mov     al, [fails]
        call    puthex8
        call    crlf
        ret

bump_fail:
        inc     byte [fails]
        ret

; ---------------------------------------------------------------------------
; Command line: optional hex base (identical to NE2KTEST.ASM)
parse_cmdline:
        mov     si, 0x81
        mov     cl, [0x80]
        xor     ch, ch
        jcxz    .done
        xor     bx, bx
        xor     di, di
.scan:
        lodsb
        cmp     al, ' '
        je      .cont
        cmp     al, 9
        je      .cont
        cmp     al, 0x0D
        je      .fin
        call    hexval
        jc      .fin
        shl     bx, 4
        or      bl, al
        inc     di
.cont:
        loop    .scan
.fin:
        cmp     di, 0
        je      .done
        mov     [base], bx
.done:
        ret

hexval:
        cmp     al, '0'
        jb      .no
        cmp     al, '9'
        ja      .alpha
        sub     al, '0'
        clc
        ret
.alpha:
        and     al, 0xDF
        cmp     al, 'A'
        jb      .no
        cmp     al, 'F'
        ja      .no
        sub     al, 'A' - 10
        clc
        ret
.no:
        stc
        ret

; ---------------------------------------------------------------------------
; Output helpers (identical to NE2KTEST.ASM)
putstr:
        push    ax
        mov     ah, 0x09
        int     0x21
        pop     ax
        ret

putch:
        push    ax
        mov     ah, 0x02
        int     0x21
        pop     ax
        ret

crlf:
        push    dx
        mov     dl, 0x0D
        call    putch
        mov     dl, 0x0A
        call    putch
        pop     dx
        ret

puthex8:
        push    ax
        push    dx
        push    ax
        shr     al, 4
        call    puthex_nib
        pop     ax
        and     al, 0x0F
        call    puthex_nib
        pop     dx
        pop     ax
        ret

puthex16:
        push    ax
        mov     al, ah
        call    puthex8
        pop     ax
        call    puthex8
        ret

puthex_nib:
        add     al, '0'
        cmp     al, '9'
        jbe     .emit
        add     al, 7
.emit:
        mov     dl, al
        call    putch
        ret

; ---------------------------------------------------------------------------
section .data

base            dw      DEF_BASE
fails           db      0

tmp_addr        dw      0
tmp_cnt         dw      0
tmp_dir         db      0
tmp_dcr         db      0

phase           db      0
mismatch        dw      0
total_mismatch  dw      0

pic1_mask       db      0
pic2_mask       db      0
old_isr_off     dw      0
old_isr_seg     dw      0
irq_count       dw      0

loop_iter       dw      0
curr_before     db      0
frame_seed      db      0
bidx            db      0
got_buf         times   LOOP_LEN db 0
exp_buf         times   LOOP_LEN db 0

m_banner        db      'NE2KDIAG - ao486 NE2000 diagnostic suite, I/O base 0x$'
m_membuf        db      '  ..... buffer memory       $'
m_irq           db      '  ..... interrupt (IRQ11)   $'
m_loop          db      '  ..... internal loopback   $'
m_ok            db      '   [ ok ]',13,10,'$'
m_bad           db      '   [FAIL]',13,10,'$'
m_loop_timeout  db      '         -> timeout on iteration 0x$'
m_loop_mismatch db      '         -> payload mismatch on iteration 0x$'
m_exp           db      '         expected: $'
m_got           db      '         got:      $'
m_nocard        db      '  Card not responding. Enable Network in the OSD',13,10
                db      '  and check the I/O base matches (default 300).',13,10,'$'
m_passed        db      'PASSED',13,10,'$'
m_failed        db      'FAILED, failure count 0x$'
