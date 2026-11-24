; NE2KRECV.COM - read received frames out of the ao486 NE2000 RX ring.
;
; Proves the last unproven path: the GUEST consuming frames the FPGA/daemon put
; in the ring. Starting the NIC lets the FPGA drain its shared-memory RX queue
; into the packet-RAM ring and advance CURR; this tool then walks BNRY->CURR,
; reads each packet's 4-byte ring header + Ethernet header via remote DMA, prints
; length / dst / src / ethertype, and advances BNRY so the ring drains.
;
; Run it with the daemon (ne2000d.py) running on the MiSTer and some LAN
; broadcast/multicast traffic present. RCR accepts broadcast + multicast, which
; is exactly what the daemon forwards.
;
; Build: nasm -f bin -o NE2KRECV.COM NE2KRECV.ASM

BITS 16
ORG 0x100

%define BASE      0x300
%define PSTART    0x46
%define PSTOP     0x80
%define MAXPKTS   8
%define POLLCAP   30000          ; empty-poll iterations before giving up

start:
        cld
        mov     dx, m_banner
        call    putstr

        ; ---- reset + RX init ---------------------------------------------
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
        mov     al, 0x01                ; DCR: word mode, BOS=0
        out     dx, al
        mov     dx, BASE+0x0A           ; RBCR = 0 while stopped
        xor     al, al
        out     dx, al
        mov     dx, BASE+0x0B
        xor     al, al
        out     dx, al
        mov     dx, BASE+0x0C
        mov     al, 0x0C                ; RCR: accept broadcast + multicast
        out     dx, al
        mov     dx, BASE+0x0D
        mov     al, 0x02                ; TCR: internal loopback off, monitor off
        out     dx, al
        mov     dx, BASE+0x01
        mov     al, PSTART
        out     dx, al                  ; PSTART
        mov     dx, BASE+0x02
        mov     al, PSTOP
        out     dx, al                  ; PSTOP
        mov     dx, BASE+0x03
        mov     al, PSTART
        out     dx, al                  ; BNRY = PSTART

        ; page 1: CURR = PSTART+1, accept-all multicast filter
        mov     dx, BASE+0x00
        mov     al, 0x61                ; page 1, stop
        out     dx, al
        mov     dx, BASE+0x07
        mov     al, PSTART+1
        out     dx, al                  ; CURR
        mov     dx, BASE+0x08           ; MAR0..7 = all ones (accept all multicast)
        mov     cx, 8
        mov     al, 0xFF
.mar:   out     dx, al
        inc     dx
        loop    .mar

        mov     dx, BASE+0x00
        mov     al, 0x22                ; page 0, start
        out     dx, al
        mov     dx, BASE+0x0D
        mov     al, 0x00                ; TCR: normal
        out     dx, al

        mov     word [pkt_count], 0
        mov     word [poll_left], POLLCAP

        ; ---- drain loop ---------------------------------------------------
.poll:
        call    get_curr                ; -> AL = CURR
        mov     bl, al                  ; BL = CURR
        mov     dx, BASE+0x03
        in      al, dx                  ; AL = BNRY
        mov     bh, al                  ; BH = BNRY

        ; nextpg = BNRY+1 (wrap to PSTART at PSTOP)
        mov     al, bh
        inc     al
        cmp     al, PSTOP
        jb      .nowrap
        mov     al, PSTART
.nowrap:
        cmp     al, bl                  ; nextpg == CURR ?  => ring empty
        jne     .have

        ; empty: count down and keep polling
        dec     word [poll_left]
        jnz     .poll_delay
        jmp     .done                   ; polled long enough, stop
.poll_delay:
        call    delay
        jmp     .poll

.have:
        mov     [cur_page], al          ; page holding this packet

        ; ---- remote DMA read: 18 bytes from cur_page:0000 ----------------
        mov     dx, BASE+0x0A
        mov     al, 18
        out     dx, al                  ; RBCR0
        mov     dx, BASE+0x0B
        xor     al, al
        out     dx, al                  ; RBCR1
        mov     dx, BASE+0x08
        xor     al, al
        out     dx, al                  ; RSAR0 = 0
        mov     dx, BASE+0x09
        mov     al, [cur_page]
        out     dx, al                  ; RSAR1 = page
        mov     dx, BASE+0x00
        mov     al, 0x0A                ; start + remote read
        out     dx, al

        mov     di, buf
        mov     cx, 9                   ; 9 words = 18 bytes
        mov     dx, BASE+0x10
.rd:    in      ax, dx
        stosw
        loop    .rd

        ; ISR.RDC ack
        mov     dx, BASE+0x07
        mov     al, 0x40
        out     dx, al

        ; ---- print packet header -----------------------------------------
        inc     word [pkt_count]
        mov     dx, m_pkt
        call    putstr
        mov     ax, [pkt_count]
        call    puthex16                ; index
        mov     dx, m_len
        call    putstr
        mov     al, [buf+2]             ; len lo
        mov     ah, [buf+3]             ; len hi
        call    puthex16
        mov     dx, m_dst
        call    putstr
        mov     si, buf+4
        call    put_mac
        mov     dx, m_src
        call    putstr
        mov     si, buf+10
        call    put_mac
        mov     dx, m_typ
        call    putstr
        mov     al, [buf+12]            ; ethertype hi first (wire order)
        call    puthex8
        mov     al, [buf+13]
        call    puthex8
        call    crlf

        ; ---- advance BNRY = next_page - 1 (wrap) --------------------------
        mov     al, [buf+1]             ; next_page from ring header
        dec     al
        cmp     al, PSTART
        jae     .nb_ok
        mov     al, PSTOP-1
.nb_ok:
        mov     dx, BASE+0x03
        out     dx, al                  ; BNRY

        cmp     word [pkt_count], MAXPKTS
        jae     .done
        jmp     .poll

.done:
        mov     dx, m_total
        call    putstr
        mov     ax, [pkt_count]
        call    puthex16
        call    crlf
        cmp     word [pkt_count], 0
        jne     .some
        mov     dx, m_none
        call    putstr
        jmp     .exit
.some:
        mov     dx, m_ok
        call    putstr
.exit:
        mov     ah, 0x4C
        mov     al, 0
        int     0x21

; ---- read CURR (page 1 reg 7), restore page 0. Returns AL = CURR ----------
get_curr:
        mov     dx, BASE+0x00
        mov     al, 0x62                ; page 1, start
        out     dx, al
        mov     dx, BASE+0x07
        in      al, dx                  ; CURR
        push    ax
        mov     dx, BASE+0x00
        mov     al, 0x22                ; page 0, start
        out     dx, al
        pop     ax
        ret

; ---- print 6-byte MAC at DS:SI as xx:xx:xx:xx:xx:xx ----------------------
put_mac:
        push    cx
        mov     cx, 6
.pm:    lodsb
        call    puthex8
        dec     cx
        jz      .pm_done
        push    dx
        mov     dl, ':'
        call    putch
        pop     dx
        jmp     .pm
.pm_done:
        pop     cx
        ret

delay:
        push    cx
        mov     cx, 0x2000
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

; print AX as 4 hex digits
puthex16:
        push    ax
        mov     al, ah
        call    puthex8
        pop     ax
        call    puthex8
        ret

; print AL as 2 hex digits
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

m_banner db 'NE2KRECV - read frames out of the NE2000 RX ring',13,10
         db 'Needs ne2000d.py running and LAN bcast/mcast traffic.',13,10,13,10,'$'
m_pkt    db 'pkt ',  '$'
m_len    db ' len=', '$'
m_dst    db ' dst=', '$'
m_src    db ' src=', '$'
m_typ    db ' type=','$'
m_total  db 13,10,'received (hex): ','$'
m_ok     db 'OK - guest consumed frames from the ring.',13,10,'$'
m_none   db 'NONE - ring was empty. Is the NIC started and traffic present?',13,10,'$'

section .bss
pkt_count resw 1
poll_left resw 1
cur_page  resb 1
buf       resb 32
