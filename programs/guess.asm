; guess.asm - Number guessing game for Mellivora OS
; VBE 1024x768x32bpp. Guess a number 1-100.
%include "syscalls.inc"
%include "lib/vbe_game.inc"
%include "lib/font.inc"
%include "lib/audio.inc"
%include "lib/highscore.inc"

COL_BG          equ 0x00101828
COL_WHITE       equ 0x00FFFFFF
COL_YELLOW      equ 0x00FFE040
COL_GREEN       equ 0x0033DD44
COL_RED         equ 0x00FF4444
COL_BLUE        equ 0x004499FF
COL_GRAY        equ 0x00888888
COL_PANEL       equ 0x00182030

SCALE           equ 3           ; font scale (15x21 px per char)
CW              equ 15          ; SCALE * 5 (char width)

; Layout constants
TITLE_X         equ 340
TITLE_Y         equ 80
INPUT_X         equ 400
INPUT_Y         equ 340
MSG_X           equ 300
MSG_Y           equ 420
TRIES_X         equ 420
TRIES_Y         equ 500

start:
.new_game:
        VBE_GAME_INIT

        ; Random secret 1-100
        mov eax, SYS_GETTIME
        int 0x80
        xor edx, edx
        mov ebx, 100
        div ebx
        inc edx
        mov [secret], edx
        mov dword [guesses], 0
        mov dword [input_val], 0
        mov dword [input_len], 0
        mov dword [msg_ptr], msg_blank
        mov dword [msg_col], COL_GRAY
        ; First-call: load persistent wins from /scores/guess
        cmp byte [hs_loaded], 0
        jne .ng_loaded
        mov byte [hs_loaded], 1
        pushad
        mov esi, hs_name_gs
        call hs_load
        mov [total_wins], eax
        popad
.ng_loaded:

        call draw_screen

.game_loop:
        ; Non-blocking key read
        mov eax, SYS_READ_KEY
        int 0x80
        test eax, eax
        jz .game_loop

        cmp al, 'q'
        je .quit
        cmp al, 'Q'
        je .quit
        cmp al, KEY_ESC
        je .quit
        cmp al, 0x0D            ; Enter
        je .submit
        cmp al, 0x08            ; Backspace
        je .backspace

        ; Digit?
        cmp al, '0'
        jl .game_loop
        cmp al, '9'
        jg .game_loop

        cmp dword [input_len], 3
        jge .game_loop

        sub al, '0'
        movzx eax, al
        push eax
        mov eax, [input_val]
        imul eax, 10
        pop ecx
        add eax, ecx
        mov [input_val], eax
        inc dword [input_len]
        call draw_screen
        jmp .game_loop

.backspace:
        cmp dword [input_len], 0
        je .game_loop
        xor edx, edx
        mov eax, [input_val]
        mov ebx, 10
        div ebx
        mov [input_val], eax
        dec dword [input_len]
        call draw_screen
        jmp .game_loop

.submit:
        cmp dword [input_len], 0
        je .game_loop

        inc dword [guesses]
        mov eax, [input_val]
        mov dword [input_val], 0
        mov dword [input_len], 0

        cmp eax, [secret]
        je .correct
        jl .too_low

        mov dword [msg_ptr], msg_high
        mov dword [msg_col], COL_RED
        call draw_screen
        jmp .game_loop

.too_low:
        mov dword [msg_ptr], msg_low
        mov dword [msg_col], COL_BLUE
        call draw_screen
        jmp .game_loop

.correct:
        mov dword [msg_ptr], msg_correct
        mov dword [msg_col], COL_GREEN
        ; Bump persistent wins, save, win SFX
        pushad
        mov eax, [total_wins]
        inc eax
        mov [total_wins], eax
        mov ebx, [total_wins]
        mov esi, hs_name_gs
        call hs_save
        call audio_sfx_win
        popad
        call draw_screen
        ; Wait for key then new game
.wait_key:
        mov eax, SYS_READ_KEY
        int 0x80
        test eax, eax
        jz .wait_key
        cmp al, 'q'
        je .quit
        jmp .new_game

.quit:
        mov eax, SYS_FRAMEBUF
        mov ebx, 2
        int 0x80
        xor eax, eax
        int 0x80

;--------------------------------------
draw_screen:
        pushad
        mov edx, COL_BG
        call vbe_clear_screen

        ; Panel
        mov ebx, 200
        mov ecx, 60
        mov edx, 624
        mov esi, 648
        mov edi, COL_PANEL
        call vbe_fill_rect

        ; Title
        mov ebx, TITLE_X
        mov ecx, TITLE_Y
        mov edx, msg_title
        mov esi, COL_YELLOW
        mov eax, SCALE
        call vbe_draw_str

        ; Subtitle
        mov ebx, 260
        mov ecx, 130
        mov edx, msg_sub
        mov esi, COL_GRAY
        mov eax, 2
        call vbe_draw_str

        ; "YOUR GUESS:" label
        mov ebx, 260
        mov ecx, 290
        mov edx, msg_prompt_lbl
        mov esi, COL_WHITE
        mov eax, 2
        call vbe_draw_str

        ; Input box
        mov ebx, 390
        mov ecx, 320
        mov edx, 240
        mov esi, 48
        mov edi, 0x00223355
        call vbe_fill_rect

        ; Input value or underscores
        cmp dword [input_len], 0
        jne .show_num
        mov ebx, INPUT_X
        mov ecx, INPUT_Y
        mov edx, msg_underscore
        mov esi, COL_GRAY
        mov eax, SCALE
        call vbe_draw_str
        jmp .after_input
.show_num:
        mov ebx, INPUT_X
        mov ecx, INPUT_Y
        mov edx, [input_val]
        mov esi, COL_WHITE
        mov eax, SCALE
        call vbe_draw_num
.after_input:

        ; Feedback message
        mov ebx, MSG_X
        mov ecx, MSG_Y
        mov edx, [msg_ptr]
        mov esi, [msg_col]
        mov eax, 2
        call vbe_draw_str

        ; Guesses count
        mov ebx, 330
        mov ecx, TRIES_Y
        mov edx, msg_tries_lbl
        mov esi, COL_GRAY
        mov eax, 2
        call vbe_draw_str
        add ebx, 11*CW
        mov edx, [guesses]
        mov esi, COL_WHITE
        mov eax, 2
        call vbe_draw_num

        ; ESC/Q to quit hint
        mov ebx, 380
        mov ecx, 580
        mov edx, msg_quit_hint
        mov esi, COL_GRAY
        mov eax, 1
        call vbe_draw_str

        VBE_GAME_PRESENT
        popad
        ret

;=== Data ===
msg_title:       db "NUMBER GUESSING", 0
msg_sub:         db "GUESS A NUMBER FROM 1 TO 100", 0
msg_prompt_lbl:  db "YOUR GUESS:", 0
msg_underscore:  db "___", 0
msg_tries_lbl:   db "GUESSES:", 0
msg_quit_hint:   db "Q OR ESC TO QUIT - ENTER TO GUESS", 0
msg_high:        db "TOO HIGH! TRY LOWER.", 0
msg_low:         db "TOO LOW! TRY HIGHER.", 0
msg_correct:     db "CORRECT! PRESS ANY KEY FOR A NEW GAME.", 0
msg_blank:       db " ", 0

secret:          dd 0
guesses:         dd 0
input_val:       dd 0
input_len:       dd 0
msg_ptr:         dd 0
msg_col:         dd 0
hs_name_gs:      db "guess", 0
hs_loaded:       db 0
total_wins:      dd 0
