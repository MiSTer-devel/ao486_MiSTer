; NE2KPEEK.COM - passive NE2000 register dump. NO destructive writes -- unlike
; NE2KTEST, this does NOT reset the card, so it can inspect exactly the state
; a failed test left behind, run immediately afterward at the same prompt.
; The only write is forcing CR to page 0 after reporting its as-found value,
; which every other tool here already does mid-test without incident.
;
; Note what real DP8390 hardware actually allows: RCR/TCR/DCR/IMR share their
; offsets with different READ-only registers (RSR/CNTR0/CNTR1/CNTR2) -- they
; are write-only and cannot be read back at all, on real silicon or here. This
; dumps what IS readable: CR (as found), BNRY, TSR, ISR, CRDA0/1 (current
; remote-DMA address -- reveals a stuck mid-transfer), RTL8019 ID, RSR,
; CNTR0-2, and via page 1: CURR, PAR0-5.
;
;   Usage:  NE2KPEEK [base]      base in hex, default 300
;   Build:  nasm -f bin -o NE2KPEEK.COM NE2KPEEK.ASM

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

        ; Report CR exactly as found (page bits tell us what the failed test
        ; left selected), then force page 0 so the reads below are well-
        ; defined. This is the only write in the whole tool.
        mov     bx, 0x00
        call    inb_off
        mov     dx, m_cr
        call    putstr
        call    puthex8
        call    crlf
        and     al, 0x3F                ; keep STP/STA/TXP/RD2:0, force page 0
        mov     bx, 0x00
        call    outb_off

        mov     si, page0_list
        mov     cx, page0_count
        call    dump_list

        ; Page 1: CURR (offset 7), PAR0-5 (offsets 1-6).
        mov     bx, 0x00
        mov     al, 0x62                ; page1, keep STA
        call    outb_off

        mov     si, page1_list
        mov     cx, page1_count
        call    dump_list

        mov     bx, 0x00
        mov     al, 0x22                ; back to page0, STA
        call    outb_off

        mov     ah, 0x4C
        int     0x21

; ---------------------------------------------------------------------------
setport:
        mov     dx, [base]
        add     dx, bx
        ret

outb_off:
        push    ax
        call    setport
        pop     ax
        out     dx, al
        ret

inb_off:
        call    setport
        in      al, dx
        ret

; Walk a table of (offset, name-ptr) pairs, DS:SI, CX entries. Each entry is
; 3 bytes: offset (1 byte), name pointer (word, '$'-terminated string).
dump_list:
.next:
        push    cx
        lodsb                           ; AL = offset
        mov     bl, al
        xor     bh, bh
        push    bx
        lodsw                           ; AX = name pointer
        mov     dx, ax
        call    putstr
        pop     bx
        call    inb_off
        call    puthex8
        call    crlf
        pop     cx
        loop    .next
        ret

; ---------------------------------------------------------------------------
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

m_banner        db      'NE2KPEEK - ao486 NE2000 passive register dump, I/O base 0x$'
m_cr            db      'CR (as found)  = $'

page0_list:
        db 0x03
        dw n_bnry
        db 0x04
        dw n_tsr
        db 0x07
        dw n_isr
        db 0x08
        dw n_crda0
        db 0x09
        dw n_crda1
        db 0x0A
        dw n_id0
        db 0x0B
        dw n_id1
        db 0x0C
        dw n_rsr
        db 0x0D
        dw n_cntr0
        db 0x0E
        dw n_cntr1
        db 0x0F
        dw n_cntr2
page0_count equ 11

page1_list:
        db 0x07
        dw n_curr
        db 0x01
        dw n_par0
        db 0x02
        dw n_par1
        db 0x03
        dw n_par2
        db 0x04
        dw n_par3
        db 0x05
        dw n_par4
        db 0x06
        dw n_par5
page1_count equ 7

n_bnry   db '  BNRY   = $'
n_tsr    db '  TSR    = $'
n_isr    db '  ISR    = $'
n_crda0  db '  CRDA0  = $'
n_crda1  db '  CRDA1  = $'
n_id0    db '  ID0    = $'
n_id1    db '  ID1    = $'
n_rsr    db '  RSR    = $'
n_cntr0  db '  CNTR0  = $'
n_cntr1  db '  CNTR1  = $'
n_cntr2  db '  CNTR2  = $'
n_curr   db '  CURR   = $'
n_par0   db '  PAR0   = $'
n_par1   db '  PAR1   = $'
n_par2   db '  PAR2   = $'
n_par3   db '  PAR3   = $'
n_par4   db '  PAR4   = $'
n_par5   db '  PAR5   = $'
