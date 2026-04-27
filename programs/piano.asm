; piano.asm - PC speaker piano for Mellivora OS
; VBE 1024x768. Keys: a s d f g h j k l (white keys), w e t y u o (black keys)
; 1=play scale, 2=Mary Had a Little Lamb, Q/ESC=quit

%include "syscalls.inc"
%include "lib/vbe_game.inc"
%include "lib/font.inc"

; Piano key dimensions
WHITE_W     equ 80
WHITE_H     equ 200
BLACK_W     equ 44
BLACK_H     equ 120
PIANO_X     equ 152
PIANO_Y     equ 230

; Colors
COL_WHITE_KEY   equ 0x00EEEEEE
COL_BLACK_KEY   equ 0x00222222
COL_PRESS       equ 0x0044DDAA
COL_BG          equ 0x00181818

start:
        VBE_GAME_INIT
        mov byte [pressed_key], 0
        call draw_piano

.loop:
        mov eax, SYS_READ_KEY
        int 0x80

        cmp al, 'q'
        je .quit
        cmp al, 'Q'
        je .quit
        cmp al, KEY_ESC
        je .quit

        cmp al, '1'
        je .play_scale
        cmp al, '2'
        je .play_mary

        mov byte [pressed_key], al

        cmp al, 'a'
        je .note_c4
        cmp al, 'w'
        je .note_cs4
        cmp al, 's'
        je .note_d4
        cmp al, 'e'
        je .note_ds4
        cmp al, 'd'
        je .note_e4
        cmp al, 'f'
        je .note_f4
        cmp al, 't'
        je .note_fs4
        cmp al, 'g'
        je .note_g4
        cmp al, 'y'
        je .note_gs4
        cmp al, 'h'
        je .note_a4
        cmp al, 'u'
        je .note_as4
        cmp al, 'j'
        je .note_b4
        cmp al, 'k'
        je .note_c5
        cmp al, 'o'
        je .note_cs5
        cmp al, 'l'
        je .note_d5
        jmp .loop

.note_c4:
        mov ebx, 262
        jmp .play
.note_cs4:
        mov ebx, 277
        jmp .play
.note_d4:
        mov ebx, 294
        jmp .play
.note_ds4:
        mov ebx, 311
        jmp .play
.note_e4:
        mov ebx, 330
        jmp .play
.note_f4:
        mov ebx, 349
        jmp .play
.note_fs4:
        mov ebx, 370
        jmp .play
.note_g4:
        mov ebx, 392
        jmp .play
.note_gs4:
        mov ebx, 415
        jmp .play
.note_a4:
        mov ebx, 440
        jmp .play
.note_as4:
        mov ebx, 466
        jmp .play
.note_b4:
        mov ebx, 494
        jmp .play
.note_c5:
        mov ebx, 523
        jmp .play
.note_cs5:
        mov ebx, 554
        jmp .play
.note_d5:
        mov ebx, 587
        jmp .play

.play:
        call draw_piano
        mov eax, SYS_BEEP
        mov ecx, 20
        int 0x80
        mov byte [pressed_key], 0
        call draw_piano
        jmp .loop

.play_scale:
        mov byte [pressed_key], '1'
        call draw_piano
        mov esi, scale_notes
        mov ecx, 8
        call play_sequence
        mov byte [pressed_key], 0
        call draw_piano
        jmp .loop

.play_mary:
        mov byte [pressed_key], '2'
        call draw_piano
        mov esi, mary_notes
        mov ecx, 13
        call play_sequence
        mov byte [pressed_key], 0
        call draw_piano
        jmp .loop

.quit:
        mov eax, SYS_FRAMEBUF
        mov ebx, 2
        int 0x80
        xor eax, eax
        int 0x80


; play_sequence: ESI=word array, ECX=count
play_sequence:
        pushad
.ps_loop:
        cmp ecx, 0
        je .ps_done
        movzx ebx, word [esi]
        cmp ebx, 0
        je .ps_rest
        mov eax, SYS_BEEP
        push ecx
        mov ecx, 25
        int 0x80
        pop ecx
        jmp .ps_next
.ps_rest:
        mov eax, SYS_SLEEP
        mov ebx, 15
        int 0x80
.ps_next:
        add esi, 2
        mov eax, SYS_SLEEP
        mov ebx, 5
        int 0x80
        dec ecx
        jmp .ps_loop
.ps_done:
        popad
        ret


; draw_piano: Render the piano
draw_piano:
        pushad

        mov edx, COL_BG
        call vbe_clear_screen

        ; Title
        mov ebx, 380
        mov ecx, 30
        mov edx, title_str
        mov esi, 0x00DDDDDD
        mov eax, 2
        call vbe_draw_str

        ; Key hint
        mov ebx, 210
        mov ecx, 72
        mov edx, str_keys
        mov esi, 0x00888888
        mov eax, 1
        call vbe_draw_str

        ; Draw 9 white keys
        mov dword [.wi], 0
.wk_loop:
        cmp dword [.wi], 9
        jge .wk_done

        mov edi, COL_WHITE_KEY
        mov eax, [.wi]
        movzx ebx, byte [white_keys + eax]
        cmp bl, byte [pressed_key]
        jne .wk_col_ok
        mov edi, COL_PRESS
.wk_col_ok:
        mov ebx, [.wi]
        imul ebx, WHITE_W
        add ebx, PIANO_X
        add ebx, 1
        mov ecx, PIANO_Y
        mov edx, WHITE_W - 2
        mov esi, WHITE_H
        call vbe_fill_rect

        ; Label below white key
        mov eax, [.wi]
        movzx edx, byte [white_keys + eax]
        sub dl, 0x20
        mov eax, [.wi]
        imul eax, WHITE_W
        add eax, PIANO_X + (WHITE_W - 10) / 2
        mov ebx, eax
        mov ecx, PIANO_Y + WHITE_H + 8
        mov esi, 0x00888888
        mov eax, 2
        call vbe_draw_char

        inc dword [.wi]
        jmp .wk_loop
.wk_done:

        ; Draw 6 black keys
        mov dword [.bi], 0
.bk_loop:
        cmp dword [.bi], 6
        jge .bk_done

        mov edi, COL_BLACK_KEY
        mov eax, [.bi]
        movzx ebx, byte [black_keys + eax]
        cmp bl, byte [pressed_key]
        jne .bk_col_ok
        mov edi, COL_PRESS
.bk_col_ok:
        mov eax, [.bi]
        movzx ebx, word [black_xpos + eax*2]
        mov ecx, PIANO_Y
        mov edx, BLACK_W
        mov esi, BLACK_H
        call vbe_fill_rect

        ; Label on black key
        mov eax, [.bi]
        movzx edx, byte [black_keys + eax]
        sub dl, 0x20
        mov eax, [.bi]
        movzx ebx, word [black_xpos + eax*2]
        add ebx, (BLACK_W - 10) / 2
        mov ecx, PIANO_Y + 10
        mov esi, 0x00AAAAAA
        mov eax, 2
        call vbe_draw_char

        inc dword [.bi]
        jmp .bk_loop
.bk_done:

        ; Instructions
        mov ebx, 300
        mov ecx, PIANO_Y + WHITE_H + 60
        mov edx, str_help
        mov esi, 0x00666688
        mov eax, 1
        call vbe_draw_str

        VBE_GAME_PRESENT
        popad
        ret

.wi: dd 0
.bi: dd 0


; === Data ===
title_str:  db "MELLIVORA PIANO", 0
str_keys:   db "WHITE KEYS: A S D F G H J K L     BLACK KEYS: W E T Y U O", 0
str_help:   db "1=SCALE  2=MARY HAD A LITTLE LAMB  Q=QUIT", 0

; White key chars: C4 D4 E4 F4 G4 A4 B4 C5 D5
white_keys: db 'a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l'

; Black key chars: C#4 D#4 F#4 G#4 A#4 C#5
black_keys: db 'w', 'e', 't', 'y', 'u', 'o'

; Black key x positions:
; C#4=210 D#4=290 F#4=450 G#4=530 A#4=610 C#5=770
black_xpos: dw 210, 290, 450, 530, 610, 770

; C major scale
scale_notes: dw 262, 294, 330, 349, 392, 440, 494, 523

; Mary Had a Little Lamb
mary_notes: dw 330, 294, 262, 294, 330, 330, 330, 0, 294, 294, 294, 0, 330

; === BSS ===
pressed_key: db 0
