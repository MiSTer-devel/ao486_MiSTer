; SHMPROBE.COM - guest side of the ao486 HPS<->FPGA transport gate (Phase 1).
;
; Drives the ne2000_shm_probe registers at 0x328..0x32D and answers the one
; question everything else rests on: do the FPGA and the HPS address the same
; physical DDR bytes?
;
;   0x328 W  window byte address, low
;   0x329 W  window byte address, high
;   0x32A RW data low
;   0x32B RW data high
;   0x32C W  command 1=read 2=write / R status bit0 busy, bit1 done, bit2 timeout
;   0x32D R  completion counter
;
; Sequence:
;   1. read window offset 0x108C - the HPS signature slot. Run
;      `shmtest.py sign` on the MiSTer first; this must read CAFE.
;   2. read 0x108E - the low half of the signature; must read BABE.
;   3. write 0x5A5A to window offset 0x0000, so the HPS can see it with
;      `shmtest.py dump 0 10`.
;   4. read it back through the probe.
;
; Usage:  SHMPROBE            (probe base fixed at 0x328)
; Build:  nasm -f bin -o SHMPROBE.COM SHMPROBE.ASM

BITS 16
ORG 0x100

%define P_ADDRLO 0x328
%define P_ADDRHI 0x329
%define P_DATALO 0x32A
%define P_DATAHI 0x32B
%define P_CMD    0x32C
%define P_COUNT  0x32D

start:
        cld
        mov     dx, m_banner
        call    putstr

        ; ---- 1. signature high half ------------------------------------------
        mov     ax, 0x108C
        call    win_read
        mov     [val1], ax
        mov     dx, m_sig_hi
        call    putstr
        mov     ax, [val1]
        call    puthex16
        mov     ax, [val1]
        cmp     ax, 0xCAFE
        je      .sig_hi_ok
        call    fail_tail
        jmp     .sig_lo
.sig_hi_ok:
        call    ok_tail

        ; ---- 2. signature low half -------------------------------------------
.sig_lo:
        mov     ax, 0x108E
        call    win_read
        mov     [val2], ax
        mov     dx, m_sig_lo
        call    putstr
        mov     ax, [val2]
        call    puthex16
        mov     ax, [val2]
        cmp     ax, 0xBABE
        je      .sig_lo_ok
        call    fail_tail
        jmp     .wr
.sig_lo_ok:
        call    ok_tail

        ; ---- 3. FPGA -> HPS: leave a marker ----------------------------------
.wr:
        mov     ax, 0x0000
        mov     bx, 0x5A5A
        call    win_write
        mov     dx, m_wrote
        call    putstr

        ; ---- 4. read it back --------------------------------------------------
        mov     ax, 0x0000
        call    win_read
        mov     [val3], ax
        mov     dx, m_readback
        call    putstr
        mov     ax, [val3]
        call    puthex16
        mov     ax, [val3]
        cmp     ax, 0x5A5A
        je      .rb_ok
        call    fail_tail
        jmp     .done
.rb_ok:
        call    ok_tail

.done:
        mov     dx, m_hint
        call    putstr
        mov     al, [fails]
        cmp     al, 0
        jne     .bad
        mov     dx, m_passed
        call    putstr
        mov     al, 0
        jmp     .exit
.bad:
        mov     dx, m_failed
        call    putstr
        mov     al, 1
.exit:
        mov     ah, 0x4C
        int     0x21

; ---------------------------------------------------------------------------
; AX = window byte offset -> AX = value read (0xFFFF and a fail on timeout)
win_read:
        push    bx
        mov     bx, ax
        mov     dx, P_ADDRLO
        mov     al, bl
        out     dx, al
        mov     dx, P_ADDRHI
        mov     al, bh
        out     dx, al
        mov     dx, P_CMD
        mov     al, 1                   ; read
        out     dx, al
        call    wait_done
        jc      .timeout
        mov     dx, P_DATALO
        in      al, dx
        mov     bl, al
        mov     dx, P_DATAHI
        in      al, dx
        mov     bh, al
        mov     ax, bx
        pop     bx
        ret
.timeout:
        mov     ax, 0xFFFF
        pop     bx
        ret

; AX = window byte offset, BX = value
win_write:
        push    bx
        push    cx
        mov     cx, ax                  ; hold the offset; AL is needed for OUT
        mov     dx, P_ADDRLO
        mov     al, cl
        out     dx, al
        mov     dx, P_ADDRHI
        mov     al, ch
        out     dx, al
        mov     dx, P_DATALO
        mov     al, bl
        out     dx, al
        mov     dx, P_DATAHI
        mov     al, bh
        out     dx, al
        mov     dx, P_CMD
        mov     al, 2                   ; write
        out     dx, al
        call    wait_done
        pop     cx
        pop     bx
        ret

; Poll status until done; CF set if the transport timed out or never retired
wait_done:
        push    cx
        push    ax
        push    dx
        mov     cx, 0xFFFF
.poll:
        mov     dx, P_CMD
        in      al, dx
        cmp     al, 0xFF                ; open bus: probe not decoded at all
        je      .nodecode
        test    al, 0x02                ; done
        jnz     .retired
        loop    .poll
        ; never retired at all - treat as timeout
        mov     dx, m_stuck
        call    putstr
        call    bump_fail
        pop     dx
        pop     ax
        pop     cx
        stc
        ret
.nodecode:
        ; Every status bit set is not a status word - it is an unclaimed port.
        ; The probe lives behind the same OSD "Network" switch as the NIC, and
        ; MiSTer keeps settings per core FILENAME, so a freshly renamed .rbf
        ; starts with Network off.
        mov     dx, m_nodecode
        call    putstr
        call    bump_fail
        pop     dx
        pop     ax
        pop     cx
        stc
        ret
.retired:
        test    al, 0x04                ; timeout bit
        jz      .clean
        mov     dx, m_timeout
        call    putstr
        call    bump_fail
        pop     dx
        pop     ax
        pop     cx
        stc
        ret
.clean:
        pop     dx
        pop     ax
        pop     cx
        clc
        ret

; ---------------------------------------------------------------------------
ok_tail:
        push    dx
        mov     dx, m_ok
        call    putstr
        pop     dx
        ret

fail_tail:
        push    dx
        mov     dx, m_bad
        call    putstr
        pop     dx
        call    bump_fail
        ret

bump_fail:
        inc     byte [fails]
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

fails       db 0
val1        dw 0
val2        dw 0
val3        dw 0

m_banner    db 'SHMPROBE - ao486 HPS<->FPGA window gate (probe at 0x328)',13,10
            db 'Run "shmtest.py sign" on the MiSTer first.',13,10,13,10,'$'
m_sig_hi    db '  window 0x108C (sig hi, expect CAFE)  $'
m_sig_lo    db '  window 0x108E (sig lo, expect BABE)  $'
m_wrote     db '  wrote 5A5A to window 0x0000 - check with: shmtest.py dump 0 10',13,10,'$'
m_readback  db '  read back window 0x0000 (expect 5A5A) $'
m_ok        db '   [ ok ]',13,10,'$'
m_bad       db '   [FAIL]',13,10,'$'
m_timeout   db 13,10,'  transport TIMEOUT - mailbox never acknowledged',13,10,'$'
m_stuck     db 13,10,'  probe never retired - FPGA side is wedged',13,10,'$'
m_nodecode  db 13,10,'  probe port reads FF (open bus) - the probe is not decoded.',13,10
            db '  Enable Network in the OSD (Hardware page). NOTE: MiSTer stores',13,10
            db '  settings per core FILENAME, so a renamed .rbf starts with it OFF.',13,10,'$'
m_hint      db 13,10,'If the signature reads FFFF or 0000, the FPGA and the HPS are not',13,10
            db 'addressing the same bytes - that is the Phase 1 gate, not a NIC bug.',13,10,'$'
m_passed    db 13,10,'PASSED - FPGA and HPS share the same window',13,10,'$'
m_failed    db 13,10,'FAILED',13,10,'$'
