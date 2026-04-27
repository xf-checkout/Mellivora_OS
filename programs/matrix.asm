; matrix.asm - The Matrix Digital Rain for Mellivora OS
; VBE 1024x768x32bpp. Cascading green characters.
; Press any key to exit.
%include "syscalls.inc"
%include "lib/vbe_game.inc"
%include "lib/font.inc"

; Character cell layout at scale=2: 10x14 pixels per cell
CHAR_W          equ 10
CHAR_H          equ 14
COLS            equ 102         ; 1024 / 10
ROWS            equ 54          ; 768  / 14
NUM_DROPS       equ 60
TICK_DELAY      equ 3

COL_BLACK       equ 0x00000000
COL_HEAD        equ 0x00FFFFFF   ; bright white head
COL_BRIGHT_G    equ 0x0044FF44   ; bright green near-head
COL_MID_G       equ 0x0000CC00   ; mid green
COL_DIM_G       equ 0x00006600   ; dim green tail

start:
        VBE_GAME_INIT

        ; Seed random from timer
        mov eax, SYS_GETTIME
        int 0x80
        mov [rand_state], eax

        ; Clear to black
        mov edx, COL_BLACK
        call vbe_clear_screen

        ; Initialize drops
        xor esi, esi
.init_drops:
        cmp esi, NUM_DROPS
        jge .main_loop
        call init_drop
        inc esi
        jmp .init_drops

;=== Main loop ===
.main_loop:
        VBE_GAME_POLL_KEY
        cmp eax, -1
        jne .exit

        ; Clear shadow buffer to black each frame
        mov edx, COL_BLACK
        call vbe_clear_screen

        ; Update and draw each drop
        xor esi, esi
.drop_loop:
        cmp esi, NUM_DROPS
        jge .frame_done

        ; Advance drop by speed
        mov eax, [drop_spd + esi*4]
        add [drop_row + esi*4], eax

        ; Draw the drop's trail
        call draw_drop_col

        ; Reset drop if fully off screen
        mov eax, [drop_row + esi*4]
        sub eax, [drop_len + esi*4]
        cmp eax, ROWS
        jl .drop_next
        call init_drop

.drop_next:
        inc esi
        jmp .drop_loop

.frame_done:
        VBE_GAME_PRESENT
        mov eax, SYS_SLEEP
        mov ebx, TICK_DELAY
        int 0x80
        jmp .main_loop

.exit:
        mov eax, SYS_FRAMEBUF
        mov ebx, 2
        int 0x80
        xor eax, eax
        int 0x80

;---------------------------------------
; init_drop: randomise drop[esi] fields
;---------------------------------------
init_drop:
        pushad
        call rand
        xor edx, edx
        mov ecx, COLS
        div ecx
        mov [drop_col + esi*4], edx

        call rand
        xor edx, edx
        mov ecx, 20
        div ecx
        neg edx
        dec edx
        mov [drop_row + esi*4], edx

        call rand
        xor edx, edx
        mov ecx, 16
        div ecx
        add edx, 5
        mov [drop_len + esi*4], edx

        call rand
        xor edx, edx
        mov ecx, 3
        div ecx
        inc edx
        mov [drop_spd + esi*4], edx
        popad
        ret

;---------------------------------------
; draw_drop_col: draw one complete drop (ESI = drop index)
;---------------------------------------
draw_drop_col:
        pushad
        mov ebp, esi

        mov edi, [drop_len + ebp*4]   ; trail length
        mov edx, [drop_row + ebp*4]   ; head row (cells)

        xor ecx, ecx            ; ecx = distance from head (0=head)
.dc_loop:
        cmp ecx, edi
        jge .dc_done

        ; current row = head_row - dist
        mov eax, edx
        sub eax, ecx

        ; Bounds check
        cmp eax, 0
        jl .dc_next
        cmp eax, ROWS
        jge .dc_next

        ; pixel coords
        imul eax, CHAR_H
        mov [.dc_py], eax
        mov eax, [drop_col + ebp*4]
        imul eax, CHAR_W
        mov [.dc_px], eax

        ; colour by distance
        cmp ecx, 0
        je .dc_head
        cmp ecx, 2
        jle .dc_bright
        cmp ecx, 5
        jle .dc_mid
        jmp .dc_dim

.dc_head:   mov esi, COL_HEAD
        jmp .dc_pick_char
.dc_bright: mov esi, COL_BRIGHT_G
        jmp .dc_pick_char
.dc_mid:    mov esi, COL_MID_G
        jmp .dc_pick_char
.dc_dim:    mov esi, COL_DIM_G

.dc_pick_char:
        push ecx
        push esi
        call rand
        pop esi
        pop ecx
        xor edx, edx
        push ecx
        mov ecx, 26
        div ecx
        pop ecx
        add edx, 'A'            ; random A-Z

        push ecx
        mov ebx, [.dc_px]
        mov ecx, [.dc_py]
        mov eax, 2              ; scale=2
        call vbe_draw_char
        pop ecx

.dc_next:
        inc ecx
        jmp .dc_loop

.dc_done:
        popad
        ret

.dc_px: dd 0
.dc_py: dd 0

;---------------------------------------
; rand - LCG PRNG -> EAX
;---------------------------------------
rand:
        mov eax, [rand_state]
        imul eax, 1103515245
        add eax, 12345
        mov [rand_state], eax
        shr eax, 16
        and eax, 0x7FFF
        ret

; === Data ===
rand_state:     dd 0
drop_col:       times NUM_DROPS dd 0
drop_row:       times NUM_DROPS dd 0
drop_len:       times NUM_DROPS dd 0
drop_spd:       times NUM_DROPS dd 0

