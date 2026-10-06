
; NE2KSEND.COM - transmit one frame from the ao486 NE2000 (Phase 5 TX test).
;
; Builds a broadcast frame at packet-RAM page 0x40 via the 16-bit data port,
; then triggers a transmit and reports TSR/ISR.
;
; With a live daemon the card should report TSR.PTX (0x01) and the frame should
; appear in tcpdump on the MiSTer. With no daemon it reports TSR.ABT (0x08) --
; that is BF-7 working, not a failure of this tool.
;
; Build: nasm -f bin -o NE2KSEND.COM NE2KSEND.ASM

BITS 16
ORG 0x100

%define BASE 0x300

start:
        cld
        mov     dx, m_banner
        call    putstr

        ; ---- reset + basic init ------------------------------------------
        mov     dx, BASE+0x18
        in      al, dx                  ; reset port
        call    delay
        mov     dx, BASE+0x07
        mov     al, 0xFF
        out     dx, al                  ; clear ISR

        mov     dx, BASE+0x00
        mov     al, 0x21                ; stop, page 0
        out     dx, al
        mov     dx, BASE+0x0E
        mov     al, 0x01                ; DCR: word mode, BOS=0 (x86)
        out     dx, al
        mov     dx, BASE+0x01
        mov     al, 0x46                ; PSTART
        out     dx, al
        mov     dx, BASE+0x02
        mov     al, 0x80                ; PSTOP
        out     dx, al
        mov     dx, BASE+0x03
        mov     al, 0x46                ; BNRY
        out     dx, al
        mov     dx, BASE+0x0D
        mov     al, 0x00                ; TCR: normal
        out     dx, al
        mov     dx, BASE+0x0C
        mov     al, 0x04                ; RCR: broadcast
        out     dx, al
        mov     dx, BASE+0x00
        mov     al, 0x22                ; start
        out     dx, al

        ; ---- remote DMA write of the frame into page 0x40 -----------------
        mov     dx, BASE+0x0A
        mov     al, FRAME_LEN
        out     dx, al                  ; RBCR0
        mov     dx, BASE+0x0B
        xor     al, al
        out     dx, al                  ; RBCR1
        mov     dx, BASE+0x08
        xor     al, al
        out     dx, al                  ; RSAR0 = 0x00
        mov     dx, BASE+0x09
        mov     al, 0x40
        out     dx, al                  ; RSAR1 = 0x40 -> 0x4000
        mov     dx, BASE+0x00
        mov     al, 0x12                ; start + remote write
        out     dx, al

        mov     si, frame
        mov     cx, FRAME_LEN/2
        mov     dx, BASE+0x10
.wr:    lodsw
        out     dx, ax                  ; 16-bit data port
        loop    .wr
        call    delay

        ; ---- transmit ------------------------------------------------------
        mov     dx, BASE+0x04
        mov     al, 0x40                ; TPSR = page 0x40
        out     dx, al
        mov     dx, BASE+0x05
        mov     al, FRAME_LEN
        out     dx, al                  ; TBCR0
        mov     dx, BASE+0x06
        xor     al, al
        out     dx, al                  ; TBCR1
        mov     dx, BASE+0x00
        mov     al, 0x26                ; STA | TXP
        out     dx, al

        ; ---- wait for the card to report -----------------------------------
        mov     cx, 0
.wait:  mov     dx, BASE+0x07
        in      al, dx
        test    al, 0x0A                ; PTX (0x02) or TXE (0x08)
        jnz     .done
        loop    .wait
.done:
        mov     dx, m_isr
        call    putstr
        mov     dx, BASE+0x07
        in      al, dx
        call    puthex8
        call    crlf

        mov     dx, m_tsr
        call    putstr
        mov     dx, BASE+0x04
        in      al, dx
        push    ax
        call    puthex8
        call    crlf
        pop     ax

        test    al, 0x01                ; TSR.PTX
        jz      .not_sent
        mov     dx, m_sent
        call    putstr
        jmp     .exit
.not_sent:
        test    al, 0x08                ; TSR.ABT
        jz      .nothing
        mov     dx, m_abort
        call    putstr
        jmp     .exit
.nothing:
        mov     dx, m_nothing
        call    putstr
.exit:
        mov     ah, 0x4C
        mov     al, 0
        int     0x21

delay:
        push    cx
        mov     cx, 0x4000
.d:     loop    .d
        pop     cx
        ret

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
        mov     dl, 13
        call    putch
        mov     dl, 10
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

puthex_nib:
        add     al, '0'
        cmp     al, '9'
        jbe     .emit
        add     al, 7
.emit:  mov     dl, al
        call    putch
        ret

section .data

; Broadcast ARP request: who-has 0.0.0.0 tell the card's own MAC.
; Harmless on any LAN and unmistakable in tcpdump.
frame:
        db 0xFF,0xFF,0xFF,0xFF,0xFF,0xFF        ; dst broadcast
        db 0x52,0x54,0x05,0x04,0x03,0x02        ; src (default card MAC)
        db 0x08,0x06                            ; ethertype ARP
        db 0x00,0x01                            ; hw type ethernet
        db 0x08,0x00                            ; proto IPv4
        db 0x06,0x04                            ; hw/proto len
        db 0x00,0x01                            ; opcode request
        db 0x52,0x54,0x05,0x04,0x03,0x02        ; sender hw
        db 0x00,0x00,0x00,0x00                  ; sender ip 0.0.0.0
        db 0x00,0x00,0x00,0x00,0x00,0x00        ; target hw
        db 0x00,0x00,0x00,0x00                  ; target ip
        times 18 db 0x00                        ; pad to 60
FRAME_LEN equ 60

m_banner  db 'NE2KSEND - transmit one broadcast frame from the NE2000',13,10,13,10,'$'
m_isr     db '  ISR = $'
m_tsr     db '  TSR = $'
m_sent    db 13,10,'SENT - TSR.PTX set. Look for it in tcpdump on the MiSTer.',13,10,'$'
m_abort   db 13,10,'ABORTED - TSR.ABT. The card sees no live host (BF-7 gate):',13,10
          db 'start ne2000d.py on the MiSTer, then reload the core.',13,10,'$'
m_nothing db 13,10,'NO RESULT - the card reported neither PTX nor ABT.',13,10,'$'
