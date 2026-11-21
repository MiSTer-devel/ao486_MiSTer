; NE2KLOOP.COM - loopback RX read-back for the ao486 NE2000.
;
; With the daemon in:  ne2000d.arm eth0 --loopback --loopsize <N>
; any guest transmit makes the daemon enqueue a synthetic N-byte RX frame with
; byte[i] = (i*7 + 0x11) & 0xFF (11 18 1f 26 2d ...).
;
; This tool: (1) transmits a trigger frame, (2) reads the whole looped-back
; frame out of the ring via the 16-bit remote-DMA port into a buffer, then
; (3) TRANSMITS the first 48 payload bytes back. The daemon logs those bytes as
; clean hex on the HPS console -- exactly what the guest read, past the OSD font.
; Compare against the expected pattern to see how a multi-page read corrupts.
;
; Build: nasm -f bin -o NE2KLOOP.COM NE2KLOOP.ASM

BITS 16
ORG 0x100

%define BASE   0x300
%define PSTART 0x46
%define PSTOP  0x80

start:
        cld
        mov     dx, m_banner
        call    putstr

        call    nic_init
        call    tx_trigger              ; trigger the daemon loopback

        ; ---- wait for the looped-back frame ------------------------------
        mov     word [poll_left], 20000
.wait:
        call    get_curr
        mov     bl, al
        mov     dx, BASE+0x03
        in      al, dx
        inc     al
        cmp     al, PSTOP
        jb      .nw
        mov     al, PSTART
.nw:    cmp     al, bl
        jne     .got
        dec     word [poll_left]
        jnz     .wait
        mov     dx, m_norx
        call    putstr
        jmp     .exit
.got:
        mov     [cur_page], al

        ; ---- SINGLE remote read: header(4) + first 48 payload bytes ------
        ; One transaction from the page start (RSAR0=0), 52 bytes. buf[0..3] =
        ; ring header {status,next,len_lo,len_hi}; buf[4..] = payload pattern.
        ; If buf[4..] is the pattern, the payload IS in the ring and the earlier
        ; all-zeros came from the second (separate) remote-read setup.
        mov     dx, BASE+0x0A
        mov     al, 52
        out     dx, al                  ; RBCR0 = 52
        mov     dx, BASE+0x0B
        xor     al, al
        out     dx, al
        mov     dx, BASE+0x08
        xor     al, al
        out     dx, al                  ; RSAR0 = 0 (page start)
        mov     dx, BASE+0x09
        mov     al, [cur_page]
        out     dx, al                  ; RSAR1 = page
        mov     dx, BASE+0x00
        mov     al, 0x0A
        out     dx, al                  ; remote read

        mov     di, buf
        mov     cx, 26                  ; 52 bytes
        mov     dx, BASE+0x10
.rdp:   in      ax, dx
        stosw
        loop    .rdp

        mov     ax, [buf+2]             ; length field from the header
        mov     [pay_len], ax
        mov     dx, m_len
        call    putstr
        call    puthex16
        call    crlf

        ; ---- advance BNRY past the frame ---------------------------------
        mov     al, [hdr_next]
        dec     al
        cmp     al, PSTART
        jae     .ab
        mov     al, PSTOP-1
.ab:    mov     dx, BASE+0x03
        out     dx, al

        ; ---- transmit the first 48 read-back bytes so the daemon logs them
        call    nic_init                ; fresh state for a clean TX
        mov     dx, BASE+0x0A
        mov     al, 48
        out     dx, al                  ; RBCR0 = 48
        mov     dx, BASE+0x0B
        xor     al, al
        out     dx, al
        mov     dx, BASE+0x08
        xor     al, al
        out     dx, al
        mov     dx, BASE+0x09
        mov     al, 0x40
        out     dx, al                  ; RSAR = 0x4000 (TX page)
        mov     dx, BASE+0x00
        mov     al, 0x12
        out     dx, al                  ; remote write
        mov     si, buf
        mov     cx, 24                  ; 48 bytes
        mov     dx, BASE+0x10
.wrb:   lodsw
        out     dx, ax
        loop    .wrb
        call    delay
        mov     dx, BASE+0x04
        mov     al, 0x40
        out     dx, al                  ; TPSR
        mov     dx, BASE+0x05
        mov     al, 48
        out     dx, al                  ; TBCR0
        mov     dx, BASE+0x06
        xor     al, al
        out     dx, al
        mov     dx, BASE+0x00
        mov     al, 0x26
        out     dx, al                  ; STA|TXP -> daemon logs these 48 bytes

        mov     dx, m_sent
        call    putstr
.exit:
        mov     ah, 0x4C
        mov     al, 0
        int     0x21

; ---- NIC init for RX+TX ---------------------------------------------------
nic_init:
        mov     dx, BASE+0x18
        in      al, dx                  ; reset port
        call    delay
        mov     dx, BASE+0x07
        mov     al, 0xFF
        out     dx, al
        mov     dx, BASE+0x00
        mov     al, 0x21
        out     dx, al
        mov     dx, BASE+0x0E
        mov     al, 0x01
        out     dx, al                  ; DCR word
        mov     dx, BASE+0x0C
        mov     al, 0x0C
        out     dx, al                  ; RCR
        mov     dx, BASE+0x0D
        mov     al, 0x00
        out     dx, al                  ; TCR
        mov     dx, BASE+0x01
        mov     al, PSTART
        out     dx, al
        mov     dx, BASE+0x02
        mov     al, PSTOP
        out     dx, al
        mov     dx, BASE+0x03
        mov     al, PSTART
        out     dx, al
        mov     dx, BASE+0x00
        mov     al, 0x61
        out     dx, al                  ; page1
        mov     dx, BASE+0x07
        mov     al, PSTART+1
        out     dx, al                  ; CURR
        mov     dx, BASE+0x00
        mov     al, 0x22
        out     dx, al                  ; page0 start
        ret

tx_trigger:
        mov     dx, BASE+0x0A
        mov     al, 20
        out     dx, al
        mov     dx, BASE+0x0B
        xor     al, al
        out     dx, al
        mov     dx, BASE+0x08
        xor     al, al
        out     dx, al
        mov     dx, BASE+0x09
        mov     al, 0x40
        out     dx, al
        mov     dx, BASE+0x00
        mov     al, 0x12
        out     dx, al
        mov     cx, 10
        mov     dx, BASE+0x10
        mov     ax, 0x1234
.t:     out     dx, ax
        loop    .t
        call    delay
        mov     dx, BASE+0x04
        mov     al, 0x40
        out     dx, al
        mov     dx, BASE+0x05
        mov     al, 20
        out     dx, al
        mov     dx, BASE+0x06
        xor     al, al
        out     dx, al
        mov     dx, BASE+0x00
        mov     al, 0x26
        out     dx, al
        ret

get_curr:
        mov     dx, BASE+0x00
        mov     al, 0x62
        out     dx, al
        mov     dx, BASE+0x07
        in      al, dx
        push    ax
        mov     dx, BASE+0x00
        mov     al, 0x22
        out     dx, al
        pop     ax
        ret

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
puthex16:
        push    ax
        mov     al, ah
        call    puthex8
        pop     ax
        call    puthex8
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
.emit:  push    dx
        mov     dl, al
        call    putch
        pop     dx
        ret

section .data
m_banner db 'NE2KLOOP - loopback RX read-back (TX result to daemon log)',13,10,'$'
m_len    db 'payload len (hex): $'
m_sent   db 'read-back 48 bytes transmitted; check daemon log.',13,10,'$'
m_norx   db 'NO RX - frame never arrived. Is the daemon in --loopback?',13,10,'$'

section .bss
poll_left resw 1
pay_len   resw 1
cur_page  resb 1
hdr_next  resb 1
buf       resb 1600
