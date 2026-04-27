; rain.asm - Matrix digital rain animation for Mellivora OS
; VBE 1024x768x32bpp. Press any key to exit.
%include "syscalls.inc"
%include "lib/vbe_game.inc"
%include "lib/font.inc"

CHAR_W          equ 10
CHAR_H          equ 14
COLS            equ 102
ROWS            equ 54
NUM_DROPS       equ 40
TICK_DELAY      equ 3

COL_BLACK       equ 0x00000000
COL_HEAD        equ 0x00FFFFFF
COL_BRIGHT_G    equ 0x0044FF44
COL_MID_G       equ 0x0000CC00
COL_DIM_G       equ 0x00005500

start:
        VBE_GAME_INIT

        mov eax, SYS_GETTIME
        int 0x80
        mov [rand_state], eax

        mov edx, COL_BLACK
        call vbe_clear_screen

        xor esi, esi
.init:
        cmp esi, NUM_DROPS
        jge .main_loop
        call init_drop
        inc esi
        jmp .init

.main_loop:
        VBE_GAME_POLL_KEY
        cmp eax, -1
        jne .exit

        mov edx, COL_BLACK
        call vbe_clear_screen

        xor esi, esi
.drops:
        cmp esi, NUM_DROPS
        jge .present

        mov eax, [drop_spd + esi*4]
        add [drop_row + esi*4], eax

        call draw_drop_col

        mov eax, [drop_row + esi*4]
        sub eax, [drop_len + esi*4]
        cmp eax, ROWS
        jl .next_drop
        call init_drop
.next_drop:
        inc esi
        jmp .drops

.present:
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

draw_drop_col:
        pushad
        mov ebp, esi
        mov edi, [drop_len + ebp*4]
        mov edx, [drop_row + ebp*4]
        xor ecx, ecx
.loop:
        cmp ecx, edi
        jge .done

        mov eax, edx
        sub eax, ecx
        cmp eax, 0
        jl .skip
        cmp eax, ROWS
        jge .skip

        imul eax, CHAR_H
        mov [.py], eax
        mov eax, [drop_col + ebp*4]
        imul eax, CHAR_W
        mov [.px], eax

        cmp ecx, 0
        je .h
        cmp ecx, 2
        jle .b
        cmp ecx, 5
        jle .m
        jmp .d
.h:     mov esi, COL_HEAD    ; esi = colour temporarily
        jmp .ch
.b:     mov esi, COL_BRIGHT_G
        jmp .ch
.m:     mov esi, COL_MID_G
        jmp .ch
.d:     mov esi, COL_DIM_G
.ch:
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
        add edx, 'A'

        push ecx
        mov ebx, [.px]
        mov ecx, [.py]
        mov eax, 2
        call vbe_draw_char
        pop ecx
.skip:
        inc ecx
        jmp .loop
.done:
        popad
        ret

.px: dd 0
.py: dd 0

rand:
        mov eax, [rand_state]
        imul eax, 1103515245
        add eax, 12345
        mov [rand_state], eax
        shr eax, 16
        and eax, 0x7FFF
        ret

rand_state:     dd 0x5DEECE6D
drop_col:       times NUM_DROPS dd 0
drop_row:       times NUM_DROPS dd 0
drop_len:       times NUM_DROPS dd 0
drop_spd:       times NUM_DROPS dd 0
