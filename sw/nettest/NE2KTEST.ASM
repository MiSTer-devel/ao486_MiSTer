; NE2KTEST.COM - NE2000 bring-up probe for the MiSTer ao486 core.
;
; Hardware test T3.4 of NE2000_AO486_PLAN.md. Freestanding 16-bit DOS .COM:
; no libc, no runtime, runs in pure DOS and in a Win9x DOS box.
;
; Everything it does is local to the card - no HPS transport, no driver, no
; packet reaches the wire. It answers bring-up questions in order:
;
;   1. reset port        read base+0x18, ISR.RST must set
;   2. card decoded      RTL8019 ID at base+0x0A / +0x0B = 50 70
;   3. registers hold    BNRY write / read-back
;   4. 8-bit data port   AA,BB written and read back (the BF-6 regression)
;   5. 16-bit data port  words written and read back  <- DEBUG.EXE cannot do this
;   6. station PROM      remote DMA from 0x0000, prints the MAC
;   7. debug aperture    base+0x20..0x26 transport state
;
;   Usage:  NE2KTEST [base]      base in hex, default 300
;
;   Build:  nasm -f bin -o NE2KTEST.COM NE2KTEST.ASM

BITS 16
ORG 0x100

%define DEF_BASE 0x300

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

        call    test_reset
        call    test_id
        cmp     byte [card_ok], 0
        je      .no_card

        call    test_regs
        call    test_byte_mode
        call    test_word_mode
        call    test_prom
        call    dump_debug
        jmp     .finish

.no_card:
        mov     dx, m_nocard
        call    putstr
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

; Write AL to base+BX
outb_off:
        push    ax
        call    setport
        pop     ax
        out     dx, al
        ret

; Read base+BX into AL
inb_off:
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
; 1. Reset port
test_reset:
        mov     bx, 0x18
        call    inb_off                 ; read of reset port triggers reset
        call    short_delay

        mov     bx, 0x07
        call    inb_off                 ; ISR
        test    al, 0x80                ; ISR.RST
        jz      .fail

        mov     dx, m_reset_ok
        call    putstr
        jmp     .clear
.fail:
        mov     dx, m_reset_bad
        call    putstr
        call    bump_fail
.clear:
        mov     bx, 0x07
        mov     al, 0xFF
        call    outb_off                ; clear ISR
        ret

; ---------------------------------------------------------------------------
; 2. RTL8019 ID
test_id:
        mov     bx, 0x00
        mov     al, 0x21                ; CR: stop, page 0, abort DMA
        call    outb_off

        mov     bx, 0x0A
        call    inb_off
        mov     [id0], al
        mov     bx, 0x0B
        call    inb_off
        mov     [id1], al

        mov     dx, m_id
        call    putstr
        mov     al, [id0]
        call    puthex8
        mov     dl, ' '
        call    putch
        mov     al, [id1]
        call    puthex8

        cmp     byte [id0], 0x50
        jne     .bad
        cmp     byte [id1], 0x70
        jne     .bad
        mov     dx, m_ok
        call    putstr
        mov     byte [card_ok], 1
        ret
.bad:
        mov     dx, m_bad
        call    putstr
        call    bump_fail
        mov     byte [card_ok], 0
        ret

; ---------------------------------------------------------------------------
; 3. Register read-back
test_regs:
        mov     bx, 0x00
        mov     al, 0x21
        call    outb_off
        mov     bx, 0x01                ; PSTART
        mov     al, 0x46
        call    outb_off
        mov     bx, 0x02                ; PSTOP
        mov     al, 0x80
        call    outb_off
        mov     bx, 0x03                ; BNRY
        mov     al, 0x46
        call    outb_off

        mov     bx, 0x03
        call    inb_off
        mov     ah, al

        mov     dx, m_regs
        call    putstr
        mov     al, ah
        push    ax
        call    puthex8
        pop     ax
        cmp     al, 0x46
        jne     .bad
        mov     dx, m_ok
        call    putstr
        ret
.bad:
        mov     dx, m_bad
        call    putstr
        call    bump_fail
        ret

; ---------------------------------------------------------------------------
; Arm remote DMA: AX = NIC address, CX = byte count, BL = 0 read / 1 write,
; BH = DCR value
arm_dma:
        push    ax
        push    cx
        push    bx

        mov     [tmp_addr], ax
        mov     [tmp_cnt], cx
        mov     [tmp_dir], bl
        mov     [tmp_dcr], bh

        mov     bx, 0x00                ; CR: stop, page 0, abort
        mov     al, 0x21
        call    outb_off
        mov     bx, 0x0E                ; DCR
        mov     al, [tmp_dcr]
        call    outb_off
        mov     bx, 0x0A                ; RBCR0
        mov     al, [tmp_cnt]
        call    outb_off
        mov     bx, 0x0B                ; RBCR1
        mov     al, [tmp_cnt+1]
        call    outb_off
        mov     bx, 0x08                ; RSAR0
        mov     al, [tmp_addr]
        call    outb_off
        mov     bx, 0x09                ; RSAR1
        mov     al, [tmp_addr+1]
        call    outb_off

        mov     bx, 0x00                ; CR: start + remote read/write
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
; 4. 8-bit data port round trip (BF-6 regression)
test_byte_mode:
        mov     ax, 0x4000
        mov     cx, 4
        mov     bx, 0x0001              ; BL=1 write, BH=0x00 DCR byte mode
        call    arm_dma

        mov     bx, 0x10
        mov     al, 0xAA
        call    outb_off
        mov     bx, 0x10
        mov     al, 0xBB
        call    outb_off
        call    short_delay

        mov     ax, 0x4000
        mov     cx, 4
        mov     bx, 0x0000              ; read, byte mode
        call    arm_dma

        mov     bx, 0x10
        call    inb_off
        mov     [got0], al
        mov     bx, 0x10
        call    inb_off
        mov     [got1], al

        mov     dx, m_byte
        call    putstr
        mov     al, [got0]
        call    puthex8
        mov     dl, ' '
        call    putch
        mov     al, [got1]
        call    puthex8

        cmp     byte [got0], 0xAA
        jne     .bad
        cmp     byte [got1], 0xBB
        jne     .bad
        mov     dx, m_ok
        call    putstr
        ret
.bad:
        mov     dx, m_bad
        call    putstr
        call    bump_fail
        cmp     byte [got0], 0xBB
        jne     .done
        cmp     byte [got1], 0xAA
        jne     .done
        mov     dx, m_swapped
        call    putstr
.done:
        ret

; ---------------------------------------------------------------------------
; 5. 16-bit data port round trip - the path DEBUG.EXE cannot reach
test_word_mode:
        mov     ax, 0x4000
        mov     cx, 8
        mov     bx, 0x0101              ; BL=1 write, BH=0x01 DCR WTS=1, BOS=0
        call    arm_dma

        mov     si, patterns
        mov     cx, 4
.wr:
        lodsw
        push    cx
        push    ax
        mov     bx, 0x10
        call    setport
        pop     ax
        out     dx, ax                  ; 16-bit OUT
        pop     cx
        loop    .wr
        call    short_delay

        mov     ax, 0x4000
        mov     cx, 8
        mov     bx, 0x0100              ; read, WTS=1
        call    arm_dma

        mov     di, results
        mov     cx, 4
.rd:
        push    cx
        mov     bx, 0x10
        call    setport
        in      ax, dx                  ; 16-bit IN
        stosw
        pop     cx
        loop    .rd

        ; compare
        mov     si, patterns
        mov     di, results
        mov     cx, 4
        xor     bp, bp
.cmp:
        lodsw
        mov     bx, ax
        mov     ax, [di]
        add     di, 2
        cmp     ax, bx
        je      .next
        inc     bp
.next:
        loop    .cmp

        mov     dx, m_word
        call    putstr
        mov     ax, [results]
        call    puthex16
        mov     dl, ' '
        call    putch
        mov     ax, [results+2]
        call    puthex16

        cmp     bp, 0
        jne     .bad
        mov     dx, m_ok
        call    putstr
        ret
.bad:
        mov     dx, m_bad
        call    putstr
        call    bump_fail
        ; name the classic failure: bytes within each word swapped
        mov     ax, [results]
        xchg    al, ah
        cmp     ax, [patterns]
        jne     .done
        mov     dx, m_swapped
        call    putstr
.done:
        ret

; ---------------------------------------------------------------------------
; 6. Station PROM -> MAC
test_prom:
        mov     ax, 0x0000
        mov     cx, 32
        mov     bx, 0x0100              ; read, WTS=1
        call    arm_dma

        mov     di, prombuf
        mov     cx, 16
.rd:
        push    cx
        mov     bx, 0x10
        call    setport
        in      ax, dx
        stosw
        pop     cx
        loop    .rd

        mov     dx, m_prom
        call    putstr

        ; PROM duplicates every byte: MAC = low byte of words 0..5
        mov     si, prombuf
        mov     cx, 6
.pr:
        lodsw
        push    cx
        push    ax
        call    puthex8                 ; AL = MAC byte
        pop     ax
        pop     cx
        cmp     cx, 1
        je      .nosep
        mov     dl, ':'
        call    putch
.nosep:
        loop    .pr

        mov     al, [prombuf]
        cmp     al, 0xFF
        jne     .ok
        mov     al, [prombuf+2]
        cmp     al, 0xFF
        jne     .ok
        mov     dx, m_bad
        call    putstr
        call    bump_fail
        ret
.ok:
        mov     dx, m_ok
        call    putstr
        ret

; ---------------------------------------------------------------------------
; 7. Debug aperture
dump_debug:
        mov     dx, m_dbg
        call    putstr

        xor     si, si
.next:
        mov     dx, m_dbg_pfx
        call    putstr
        mov     ax, si
        add     al, '0'
        mov     dl, al
        call    putch
        mov     dl, ' '
        call    putch

        ; name table entries are 6 bytes each ("xxxx " + '$'); si*6 without
        ; using MUL, which would clobber DX
        mov     ax, si
        shl     ax, 1
        mov     bx, ax
        shl     ax, 1
        add     ax, bx
        add     ax, dbg_names
        mov     dx, ax
        call    putstr

        mov     bx, si
        add     bx, 0x20
        call    inb_off
        call    puthex8
        call    crlf

        inc     si
        cmp     si, 7
        jb      .next
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
; Command line: optional hex base
parse_cmdline:
        mov     si, 0x81
        mov     cl, [0x80]
        xor     ch, ch
        jcxz    .done
        xor     bx, bx                  ; accumulator
        xor     di, di                  ; digit count
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

; AL = ascii -> AL = value, CF set if not a hex digit
hexval:
        cmp     al, '0'
        jb      .no
        cmp     al, '9'
        ja      .alpha
        sub     al, '0'
        clc
        ret
.alpha:
        and     al, 0xDF                ; upper-case
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
; Output helpers
putstr:                                 ; DX = '$'-terminated string
        push    ax
        mov     ah, 0x09
        int     0x21
        pop     ax
        ret

putch:                                  ; DL = character
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

puthex8:                                ; AL = byte
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

puthex16:                               ; AX = word
        push    ax
        mov     al, ah
        call    puthex8
        pop     ax
        call    puthex8
        ret

puthex_nib:                             ; AL = 0..15
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
card_ok         db      0
id0             db      0
id1             db      0
got0            db      0
got1            db      0
tmp_addr        dw      0
tmp_cnt         dw      0
tmp_dir         db      0
tmp_dcr         db      0

patterns        dw      0x1234, 0xA55A, 0xDEAD, 0xBEEF
results         dw      0, 0, 0, 0
prombuf         times   16 dw 0

m_banner        db      'NE2KTEST - ao486 NE2000 probe, I/O base 0x$'
m_reset_ok      db      '  [ ok ] reset port         ISR.RST set',13,10,'$'
m_reset_bad     db      '  [FAIL] reset port         ISR.RST did not set',13,10,'$'
m_id            db      '  ..... RTL8019 ID          $'
m_regs          db      '  ..... BNRY read-back      $'
m_byte          db      '  ..... 8-bit data port     $'
m_word          db      '  ..... 16-bit data port    $'
m_prom          db      '  ..... station PROM (MAC)  $'
m_ok            db      '   [ ok ]',13,10,'$'
m_bad           db      '   [FAIL]',13,10,'$'
m_swapped       db      '         -> bytes are SWAPPED (BOS handling wrong)',13,10,'$'
m_nocard        db      13,10,'Card not responding. Enable Network in the OSD',13,10
                db      'and check the I/O base matches (default 300).',13,10,'$'
m_dbg           db      13,10,'  Debug aperture (ao486-only):',13,10,'$'
m_dbg_pfx       db      '    +$'
m_passed        db      'PASSED',13,10,'$'
m_failed        db      'FAILED, failure count 0x$'

; 7 names, 5 chars + '$' each, indexed by the *5 arithmetic above
dbg_names       db      'dmaL $'
                db      'dmaH $'
                db      'cntL $'
                db      'cntH $'
                db      'dpst $'
                db      'hpsc $'
                db      'hbLo $'
