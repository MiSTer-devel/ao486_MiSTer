; NE2KMEM.COM - packet-RAM data-port round-trip test (no RX, no daemon traffic).
;
; Writes 48 ascending bytes (00 01 02 ... 2F) to packet-RAM page 0x40 through the
; 16-bit remote-DMA WRITE port, then reads them back through the remote-DMA READ
; port and transmits the read-back so the daemon logs it as clean hex.
;
; This isolates the CPU<->packet-RAM data-port path from the RX/background/DDR
; path entirely. If the read-back is 00 01 02 ... the data port handles long
; (>2 word) transfers and the RX all-zeros is a background-delivery problem; if
; it is 00 01 <zeros> the data-port READ itself truncates after 2 words.
;
; Build: nasm -f bin -o NE2KMEM.COM NE2KMEM.ASM

BITS 16
ORG 0x100

%define BASE 0x300

start:
        cld
        mov     dx, m_banner
        call    putstr
        call    nic_init

        ; ---- build 48 ascending bytes in buf --------------------------------
        mov     di, buf
        mov     cx, 48
        xor     al, al
.fill:  stosb
        inc     al
        loop    .fill

        ; ---- remote-DMA WRITE 48 bytes to 0x4000 ----------------------------
        mov     dx, BASE+0x0A
        mov     al, 48
        out     dx, al                  ; RBCR0 = 48
        mov     dx, BASE+0x0B
        xor     al, al
        out     dx, al
        mov     dx, BASE+0x08
        xor     al, al
        out     dx, al                  ; RSAR0 = 0
        mov     dx, BASE+0x09
        mov     al, 0x40
        out     dx, al                  ; RSAR1 = 0x40
        mov     dx, BASE+0x00
        mov     al, 0x12
        out     dx, al                  ; remote write
        mov     si, buf
        mov     cx, 24
        mov     dx, BASE+0x10
.wr:    lodsw
        out     dx, ax
        loop    .wr
        call    delay

        ; ---- remote-DMA READ 48 bytes back from 0x4000 ----------------------
        mov     dx, BASE+0x0A
        mov     al, 48
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
        mov     al, 0x0A
        out     dx, al                  ; remote read
        mov     di, buf2
        mov     cx, 24
        mov     dx, BASE+0x10
.rd:    in      ax, dx
        stosw
        loop    .rd

        ; ---- TX buf2[0..47] so the daemon logs the read-back ----------------
        call    nic_init
        mov     dx, BASE+0x0A
        mov     al, 48
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
        out     dx, al                  ; remote write (stage TX)
        mov     si, buf2
        mov     cx, 24
        mov     dx, BASE+0x10
.tw:    lodsw
        out     dx, ax
        loop    .tw
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
        out     dx, al                  ; TXP -> daemon logs buf2

        mov     dx, m_done
        call    putstr
        mov     ah, 0x4C
        mov     al, 0
        int     0x21

nic_init:
        mov     dx, BASE+0x18
        in      al, dx
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
        mov     dx, BASE+0x00
        mov     al, 0x22
        out     dx, al
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

section .data
m_banner db 'NE2KMEM - packet-RAM data-port round-trip',13,10,'$'
m_done   db 'wrote+read 48 bytes; check daemon log (expect 00 01 02 ...).',13,10,'$'

section .bss
buf   resb 64
buf2  resb 64
