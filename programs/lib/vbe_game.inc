;=======================================================================
; vbe_game.inc - Mellivora VBE Game-Loop Helper (user-space)
;
; High-level macros that automate the boilerplate needed for a VBE
; 32-bpp pixel-graphics game:
;   VBE_GAME_INIT      Enter 640x480x32 mode and populate fb_* vars.
;   VBE_GAME_PRESENT   Blit shadow buffer to the LFB.
;   VBE_GAME_POLL_KEY  Non-blocking key read (result in EAX; -1=none).
;
; Standard scancode constants for the most common game controls:
;   KEY_LEFT  KEY_RIGHT  KEY_UP  KEY_DOWN
;   KEY_ESC   KEY_SPACE  KEY_ENTER
;   KEY_W  KEY_A  KEY_S  KEY_D
;   KEY_P  KEY_R  KEY_Q
;
; This file auto-includes lib/vbe.inc (which declares fb_addr, fb_pitch,
; fb_width, fb_height and all drawing routines).
;
; Typical usage:
;
;   %include "lib/vbe_game.inc"   ; also pulls in lib/vbe.inc
;
;   _start:
;       VBE_GAME_INIT             ; enter 640x480x32, fill fb_* vars
;
;   .game_loop:
;       VBE_GAME_POLL_KEY         ; EAX = scancode or -1
;       cmp eax, KEY_ESC
;       je  .quit
;       ; ... update state, draw frame ...
;       VBE_GAME_PRESENT          ; flip to screen
;       jmp .game_loop
;
;   .quit:
;       mov eax, 2                ; SYS_FRAMEBUF restore text mode
;       mov ebx, 2
;       int 0x80
;       xor eax, eax
;       int 0x80                  ; SYS_EXIT
;
; Requires: syscalls.inc (or that EAX/EBX/ECX/EDX/ESI conventions hold).
;=======================================================================

%ifndef VBE_GAME_INC
%define VBE_GAME_INC

%include "lib/vbe.inc"          ; drawing primitives + fb_* BSS vars

; -----------------------------------------------------------------------
; Standard game-key codes — translated ASCII/special values returned by
; SYS_READ_KEY (the kernel scancode table maps raw PS/2 scancodes to
; these values before storing them in the keyboard ring buffer).
; Arrow keys: defined in syscalls.inc as KEY_UP=0x80 etc; guard here.
; -----------------------------------------------------------------------
KEY_ESC   equ 0x1B             ; Escape
KEY_ENTER equ 0x0D             ; Enter / carriage-return
KEY_SPACE equ 0x20             ; Space

%ifndef KEY_UP
KEY_UP    equ 0x80             ; scancode 0x48 → translated 0x80
KEY_DOWN  equ 0x81             ; scancode 0x50 → translated 0x81
KEY_LEFT  equ 0x82             ; scancode 0x4B → translated 0x82
KEY_RIGHT equ 0x83             ; scancode 0x4D → translated 0x83
%endif

KEY_W     equ 'w'              ; 0x77
KEY_A     equ 'a'              ; 0x61
KEY_S     equ 's'              ; 0x73
KEY_D     equ 'd'              ; 0x64

KEY_P     equ 'p'              ; pause  0x70
KEY_R     equ 'r'              ; restart 0x72
KEY_Q     equ 'q'              ; quit   0x71

; -----------------------------------------------------------------------
; VBE_GAME_INIT - Enter 1024x768x32 VBE mode and fill fb_* variables.
;
; Clobbers: EAX, EBX, ECX, EDX, ESI.
; After the macro returns, [fb_addr], [fb_width], [fb_height], [fb_pitch]
; are all populated and the shadow buffer is ready for drawing.
; -----------------------------------------------------------------------
%macro VBE_GAME_INIT 0
        ; Enter 1024 x 768 x 32-bpp mode
        mov eax, 37             ; SYS_FRAMEBUF
        mov ebx, 1              ; sub-function 1: set mode
        mov ecx, 1024           ; width
        mov edx, 768            ; height
        mov esi, 32             ; bpp
        int 0x80

        ; Query framebuffer info
        ; Returns: EAX=shadow_buf, EBX=width, ECX=height, EDX=bpp
        mov eax, 37
        mov ebx, 0
        int 0x80

        mov [fb_addr],   eax    ; shadow buffer address
        mov [fb_width],  ebx    ; width in pixels
        mov [fb_height], ecx    ; height in pixels
        ; pitch = width * 4  (32-bpp, no padding)
        shl ebx, 2
        mov [fb_pitch],  ebx
%endmacro

; -----------------------------------------------------------------------
; VBE_GAME_PRESENT - Draw cursor, then blit shadow buffer to the LFB.
; Clobbers: nothing (cursor uses pushad; blit clobbers EAX, EBX).
; -----------------------------------------------------------------------
%macro VBE_GAME_PRESENT 0
        call vbe_draw_cursor
        mov  eax, SYS_FRAMEBUF
        mov  ebx, 4             ; sub-function 4: present
        int  0x80
%endmacro

; -----------------------------------------------------------------------
; VBE_GAME_POLL_KEY - Non-blocking keyboard check.
; Result: EAX = scancode (positive), or -1 if no key is pending.
; Clobbers: EAX only.
; -----------------------------------------------------------------------
%macro VBE_GAME_POLL_KEY 0
        mov eax, 4              ; SYS_READ_KEY  (non-blocking)
        int 0x80
        ; SYS_READ_KEY returns 0 (zero-extended) when no key is waiting.
        ; Normalise to -1 so callers can use: cmp eax, -1 / je .no_key
        test eax, eax
        jnz %%key_ok
        mov eax, -1
%%key_ok:
%endmacro

; -----------------------------------------------------------------------
; vbe_draw_cursor  Draw a software mouse pointer on the shadow buffer.
; Shape: filled 10-row right-angle triangle (top-left hotspot).
;        White fill with 1-pixel black drop-shadow at (+1,+1).
; Uses save/restore so the cursor never permanently bakes into the
; shadow buffer — eliminates the trail in partial-update game loops.
; Reads mouse position via SYS_MOUSE. Clobbers nothing (pushad/popad).
; -----------------------------------------------------------------------
vbe_draw_cursor:
        pushad
        mov  eax, SYS_MOUSE
        int  0x80               ; EAX=x, EBX=y, ECX=buttons
        mov  [.vdc_mx], eax
        mov  [.vdc_my], ebx

        ;---- 1. Restore previous cursor area to shadow buffer ----
        cmp  dword [.vdc_px], -1
        je   .vdc_to_save       ; first call — nothing to restore

        xor  ebp, ebp           ; row counter (0..11)
.vdc_rst:
        cmp  ebp, 12
        jge  .vdc_to_save
        mov  eax, [.vdc_py]
        add  eax, ebp           ; y = py + row
        cmp  eax, [fb_height]
        jge  .vdc_rst_next
        mov  edx, [fb_width]
        sub  edx, [.vdc_px]     ; pixels remaining on this row
        cmp  edx, 12
        jg   .vdc_rst_full
        test edx, edx
        jle  .vdc_rst_next
        jmp  .vdc_rst_copy
.vdc_rst_full:
        mov  edx, 12
.vdc_rst_copy:
        imul eax, [fb_pitch]
        add  eax, [fb_addr]
        mov  ecx, [.vdc_px]
        lea  edi, [eax + ecx*4] ; dest: shadow at (px, py+row)
        mov  ecx, ebp
        imul ecx, 48            ; save_buf row offset (12 px * 4 bytes)
        lea  esi, [.vdc_save_buf + ecx]
        mov  ecx, edx
        rep movsd
.vdc_rst_next:
        inc  ebp
        jmp  .vdc_rst

        ;---- 2. Save shadow pixels at new cursor position ----
.vdc_to_save:
        mov  eax, [.vdc_mx]
        mov  [.vdc_px], eax
        mov  eax, [.vdc_my]
        mov  [.vdc_py], eax

        xor  ebp, ebp
.vdc_sv:
        cmp  ebp, 12
        jge  .vdc_to_draw
        mov  eax, [.vdc_py]
        add  eax, ebp
        cmp  eax, [fb_height]
        jge  .vdc_sv_next
        mov  edx, [fb_width]
        sub  edx, [.vdc_px]
        cmp  edx, 12
        jg   .vdc_sv_full
        test edx, edx
        jle  .vdc_sv_next
        jmp  .vdc_sv_copy
.vdc_sv_full:
        mov  edx, 12
.vdc_sv_copy:
        imul eax, [fb_pitch]
        add  eax, [fb_addr]
        mov  ecx, [.vdc_px]
        lea  esi, [eax + ecx*4] ; src: shadow at (mx, my+row)
        mov  ecx, ebp
        imul ecx, 48
        lea  edi, [.vdc_save_buf + ecx]
        mov  ecx, edx
        rep movsd
.vdc_sv_next:
        inc  ebp
        jmp  .vdc_sv

        ;---- 3. Draw cursor ----
.vdc_to_draw:
        ; Black drop-shadow: row i at (mx+1, my+i+1), width i+1
        xor  esi, esi
.vdc_sh:
        cmp  esi, 10
        jge  .vdc_fill
        mov  ebx, [.vdc_mx]
        inc  ebx
        mov  ecx, [.vdc_my]
        add  ecx, esi
        inc  ecx
        mov  edx, esi
        inc  edx
        push esi
        mov  esi, 0x00000000
        call vbe_draw_hline
        pop  esi
        inc  esi
        jmp  .vdc_sh

.vdc_fill:
        ; White fill: row i at (mx, my+i), width i+1
        xor  esi, esi
.vdc_fl:
        cmp  esi, 10
        jge  .vdc_done
        mov  ebx, [.vdc_mx]
        mov  ecx, [.vdc_my]
        add  ecx, esi
        mov  edx, esi
        inc  edx
        push esi
        mov  esi, 0x00FFFFFF
        call vbe_draw_hline
        pop  esi
        inc  esi
        jmp  .vdc_fl

.vdc_done:
        popad
        ret

.vdc_mx: dd 0
.vdc_my: dd 0
.vdc_px: dd -1                  ; -1 = no previous position yet
.vdc_py: dd -1
.vdc_save_buf: times 12*12*4 db 0  ; 576-byte background save area

%endif ; VBE_GAME_INC
