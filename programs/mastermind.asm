; mastermind.asm - Code-breaking game for Mellivora OS
; VBE 1024x768x32bpp. Guess 4-color code in 10 tries.
; Colors: 1-6 keys. Backspace to delete. Enter to submit. Q to quit.
%include "syscalls.inc"
%include "lib/vbe_game.inc"
%include "lib/font.inc"
%include "lib/highscore.inc"
%include "lib/audio.inc"

CODE_LEN        equ 4
MAX_GUESSES     equ 10
NUM_COLORS      equ 6

; Layout
PEG_R           equ 22          ; peg radius
PEG_GAP         equ 8
ROW_X           equ 120         ; leftmost peg centre x
ROW_H           equ 60          ; row height
BOARD_Y         equ 80          ; top of board
FB_X            equ 420         ; feedback dots x (black/white pegs)

; Feedback dot size (2×2 grid)
FD_R            equ 8
FD_GAP          equ 4

COL_BG          equ 0x000A0E18
COL_PANEL       equ 0x00101828
COL_WHITE       equ 0x00FFFFFF
COL_GRAY        equ 0x00888888
COL_YELLOW      equ 0x00FFE040
COL_BLACK_PEG   equ 0x00222222
COL_WHITE_PEG   equ 0x00EEEEEE
COL_EMPTY       equ 0x00334455

; 6 code colors
COL1            equ 0x00EE3333   ; Red
COL2            equ 0x0033DD44   ; Green
COL3            equ 0x003399FF   ; Blue
COL4            equ 0x00FFEE22   ; Yellow
COL5            equ 0x00FF8800   ; Orange
COL6            equ 0x00CC44FF   ; Purple

start:
        VBE_GAME_INIT
        call new_game
        call draw_all

.main_loop:
        VBE_GAME_POLL_KEY
        cmp eax, -1
        je .no_key

        cmp al, 'q'
        je .quit
        cmp al, 'Q'
        je .quit
        cmp al, KEY_ESC
        je .quit

        ; Game over? any key = new game
        cmp dword [game_over], 1
        je .new_game_key

        cmp al, '1'
        jl .no_key
        cmp al, '6'
        jg .check_enter
        ; Color digit
        cmp dword [cur_pos], CODE_LEN
        jge .no_key
        sub al, '0'
        movzx eax, al
        mov ecx, [cur_pos]
        mov [cur_guess + ecx], eax
        inc dword [cur_pos]
        jmp .redraw

.check_enter:
        cmp al, 0x0D
        je .submit
        cmp al, 0x08
        je .backspace
        jmp .no_key

.backspace:
        cmp dword [cur_pos], 0
        je .no_key
        dec dword [cur_pos]
        mov ecx, [cur_pos]
        mov byte [cur_guess + ecx], 0
        jmp .redraw

.submit:
        cmp dword [cur_pos], CODE_LEN
        jl .no_key
        call evaluate_guess
        call check_win
        jmp .redraw

.new_game_key:
        call new_game

.redraw:
        call draw_all
.no_key:
        mov eax, SYS_SLEEP
        mov ebx, 1
        int 0x80
        jmp .main_loop

.quit:
        mov eax, SYS_FRAMEBUF
        mov ebx, 2
        int 0x80
        xor eax, eax
        int 0x80

;--------------------------------------
new_game:
        ; Load best (fewest-guesses) record from disk on first call
        cmp byte [hs_loaded], 0
        jne .ng_skip_load
        mov byte [hs_loaded], 1
        push esi
        mov esi, hs_name_mm
        call hs_load
        mov [best_guesses], eax
        pop esi
.ng_skip_load:
        mov dword [score_played], 0
        ; Generate random 4-color code
        xor ecx, ecx
.ng_loop:
        cmp ecx, CODE_LEN
        jge .ng_done
        call rand
        xor edx, edx
        mov ebx, NUM_COLORS
        div ebx
        inc edx                 ; 1..6
        mov [secret + ecx], dl
        inc ecx
        jmp .ng_loop
.ng_done:
        mov dword [num_guesses], 0
        mov dword [cur_pos], 0
        mov dword [game_over], 0
        ; Clear guess history
        xor ecx, ecx
.ng_clear:
        cmp ecx, MAX_GUESSES * CODE_LEN
        jge .ng_clear_done
        mov byte [guess_history + ecx], 0
        mov byte [feedback + ecx], 0
        inc ecx
        jmp .ng_clear
.ng_clear_done:
        xor ecx, ecx
.ng_clrc:
        cmp ecx, CODE_LEN
        jge .ng_ret
        mov byte [cur_guess + ecx], 0
        inc ecx
        jmp .ng_clrc
.ng_ret:
        ret

;--------------------------------------
; evaluate_guess: score current guess, store in feedback row
; Black peg = right color+pos, White peg = right color wrong pos
;--------------------------------------
evaluate_guess:
        ; Copy cur_guess into history row
        mov eax, [num_guesses]
        imul eax, CODE_LEN
        mov ecx, 0
.eg_copy:
        cmp ecx, CODE_LEN
        jge .eg_score
        movzx edx, byte [cur_guess + ecx]
        mov [guess_history + eax + ecx], dl
        inc ecx
        jmp .eg_copy

.eg_score:
        ; Count black (exact) pegs
        mov [.blacks], dword 0
        mov [.whites], dword 0
        ; Mark arrays for scoring
        xor ecx, ecx
.eg_black:
        cmp ecx, CODE_LEN
        jge .eg_white_setup
        movzx eax, byte [secret + ecx]
        movzx edx, byte [cur_guess + ecx]
        cmp eax, edx
        jne .eg_b_skip
        inc dword [.blacks]
        mov byte [.smask + ecx], 1
        mov byte [.gmask + ecx], 1
        jmp .eg_b_next
.eg_b_skip:
        mov byte [.smask + ecx], 0
        mov byte [.gmask + ecx], 0
.eg_b_next:
        inc ecx
        jmp .eg_black

.eg_white_setup:
        xor ecx, ecx
.eg_white:
        cmp ecx, CODE_LEN
        jge .eg_store
        cmp byte [.gmask + ecx], 1
        je .eg_w_next
        movzx eax, byte [cur_guess + ecx]
        ; Search secret for this color (unmatched)
        xor edx, edx
.eg_ws:
        cmp edx, CODE_LEN
        jge .eg_w_next
        cmp byte [.smask + edx], 1
        je .eg_ws_next
        movzx ebx, byte [secret + edx]
        cmp eax, ebx
        jne .eg_ws_next
        ; Match
        inc dword [.whites]
        mov byte [.smask + edx], 1
        mov byte [.gmask + ecx], 1
        jmp .eg_w_next
.eg_ws_next:
        inc edx
        jmp .eg_ws
.eg_w_next:
        inc ecx
        jmp .eg_white

.eg_store:
        ; Pack blacks/whites into feedback byte: high nibble=blacks, low nibble=whites
        mov eax, [num_guesses]
        imul eax, CODE_LEN      ; use first byte of row for b, second for w
        mov ecx, [.blacks]
        mov [feedback + eax], cl
        mov ecx, [.whites]
        mov [feedback + eax + 1], cl

        inc dword [num_guesses]
        ; Reset cur_guess
        mov dword [cur_pos], 0
        xor ecx, ecx
.eg_rc:
        cmp ecx, CODE_LEN
        jge .eg_done
        mov byte [cur_guess + ecx], 0
        inc ecx
        jmp .eg_rc
.eg_done:
        ret

.blacks:  dd 0
.whites:  dd 0
.smask:   times CODE_LEN db 0
.gmask:   times CODE_LEN db 0

;--------------------------------------
check_win:
        mov eax, [num_guesses]
        test eax, eax
        jz .cw_ret
        dec eax
        imul eax, CODE_LEN
        movzx ecx, byte [feedback + eax]
        cmp ecx, CODE_LEN
        je .cw_win
        cmp dword [num_guesses], MAX_GUESSES
        jge .cw_lose
        ret
.cw_win:
        mov dword [game_over], 1
        mov dword [player_won], 1
        ; Lower guess count is better; store inverse so hs_update picks max
        cmp dword [score_played], 0
        jne .cw_skip_sfx
        mov dword [score_played], 1
        ; Store score = (MAX_GUESSES - num_guesses + 1) so fewer guesses = higher
        mov eax, MAX_GUESSES
        sub eax, [num_guesses]
        inc eax
        push esi
        mov esi, hs_name_mm
        mov ebx, eax
        call hs_update
        mov [best_guesses], eax
        pop esi
        call audio_sfx_win
.cw_skip_sfx:
        ret
.cw_lose:
        mov dword [game_over], 1
        mov dword [player_won], 0
        cmp dword [score_played], 0
        jne .cw_ret
        mov dword [score_played], 1
        call audio_sfx_lose
.cw_ret:
        ret

;--------------------------------------
rand:
        mov eax, [rand_state]
        imul eax, 1664525
        add eax, 1013904223
        mov [rand_state], eax
        shr eax, 16
        and eax, 0x7FFF
        ret

;--------------------------------------
; get_color_rgb: EAX=color(1-6) → ESI=rgb
;--------------------------------------
get_color_rgb:
        cmp eax, 1
        je .c1
        cmp eax, 2
        je .c2
        cmp eax, 3
        je .c3
        cmp eax, 4
        je .c4
        cmp eax, 5
        je .c5
        mov esi, COL6
        ret
.c1: mov esi, COL1
        ret
.c2: mov esi, COL2
        ret
.c3: mov esi, COL3
        ret
.c4: mov esi, COL4
        ret
.c5: mov esi, COL5
        ret

;--------------------------------------
draw_all:
        pushad
        mov edx, COL_BG
        call vbe_clear_screen

        ; Title
        mov ebx, 390
        mov ecx, 30
        mov edx, msg_title
        mov esi, COL_YELLOW
        mov eax, 2
        call vbe_draw_str

        ; Draw guess history rows
        mov dword [.ri], 0
.da_row:
        cmp dword [.ri], MAX_GUESSES
        jge .da_cur

        ; Row y (bottom row = row 0 = current)
        mov eax, MAX_GUESSES - 1
        sub eax, [.ri]
        imul eax, ROW_H
        add eax, BOARD_Y
        mov [.ry], eax

        ; Row number label
        mov ebx, 50
        mov ecx, [.ry]
        add ecx, ROW_H/2 - 7
        mov edx, [.ri]
        add edx, 1
        mov esi, COL_GRAY
        mov eax, 2
        call vbe_draw_num

        mov eax, [.ri]
        cmp eax, [num_guesses]
        jge .da_empty_row     ; not yet played

        ; Draw pegs for this guess
        mov dword [.ci], 0
.da_peg:
        cmp dword [.ci], CODE_LEN
        jge .da_feedback

        ; cx = ROW_X + ci*(PEG_R*2 + PEG_GAP) + PEG_R
        mov eax, [.ci]
        imul eax, PEG_R*2 + PEG_GAP
        add eax, ROW_X + PEG_R
        mov [.px], eax
        mov eax, [.ry]
        add eax, ROW_H/2
        mov [.py], eax

        ; Color
        mov eax, [.ri]
        imul eax, CODE_LEN
        add eax, [.ci]
        movzx eax, byte [guess_history + eax]
        test eax, eax
        jz .da_empty_peg
        call get_color_rgb
        jmp .da_draw_peg

.da_empty_peg:
        mov esi, COL_EMPTY
.da_draw_peg:
        mov ebx, [.px]
        mov ecx, [.py]
        mov edx, PEG_R
        call vbe_fill_circle

        inc dword [.ci]
        jmp .da_peg

.da_feedback:
        ; Draw feedback dots (2×2 grid)
        mov eax, [.ri]
        imul eax, CODE_LEN
        movzx ecx, byte [feedback + eax]       ; blacks
        movzx edx, byte [feedback + eax + 1]   ; whites
        mov [.fb], ecx
        mov [.fw], edx

        mov eax, [.ry]
        add eax, ROW_H/2 - FD_R - FD_GAP/2
        mov [.fdy], eax

        ; 4 slots in 2×2: draw blacks first, then whites
        mov dword [.fi], 0
.da_fd:
        cmp dword [.fi], CODE_LEN
        jge .da_next_row

        ; Position: fi=0,1 → top row, fi=2,3 → bottom
        mov eax, [.fi]
        xor edx, edx
        mov ebx, 2
        div ebx             ; EAX=row(0/1), EDX=col(0/1)
        imul edx, FD_R*2 + FD_GAP
        add edx, FB_X
        imul eax, FD_R*2 + FD_GAP
        add eax, [.fdy]
        mov [.fdpx], edx
        mov [.fdpy], eax

        ; Color: fi < blacks → black peg, fi < blacks+whites → white peg
        mov eax, [.fi]
        cmp eax, [.fb]
        jl .da_fd_black
        mov ecx, [.fb]
        add ecx, [.fw]
        cmp eax, ecx
        jl .da_fd_white
        mov esi, COL_EMPTY
        jmp .da_fd_draw
.da_fd_black:
        mov esi, COL_BLACK_PEG
        jmp .da_fd_draw
.da_fd_white:
        mov esi, COL_WHITE_PEG
.da_fd_draw:
        mov ebx, [.fdpx]
        mov ecx, [.fdpy]
        mov edx, FD_R
        call vbe_fill_circle

        inc dword [.fi]
        jmp .da_fd

.da_empty_row:
        ; Row not yet guessed — draw empty pegs
        mov dword [.ci], 0
.da_ep:
        cmp dword [.ci], CODE_LEN
        jge .da_next_row
        mov eax, [.ci]
        imul eax, PEG_R*2 + PEG_GAP
        add eax, ROW_X + PEG_R
        mov ebx, eax
        mov ecx, [.ry]
        add ecx, ROW_H/2
        mov edx, PEG_R
        mov esi, COL_EMPTY
        call vbe_fill_circle
        inc dword [.ci]
        jmp .da_ep

.da_next_row:
        inc dword [.ri]
        jmp .da_row

.da_cur:
        ; Current guess row (at bottom)
        mov eax, MAX_GUESSES
        imul eax, ROW_H
        add eax, BOARD_Y
        mov [.ry], eax

        ; Highlight bar
        mov ebx, 90
        mov ecx, [.ry]
        mov edx, 450
        mov esi, ROW_H - 4
        mov edi, 0x00182838
        call vbe_fill_rect

        mov dword [.ci], 0
.da_cur_peg:
        cmp dword [.ci], CODE_LEN
        jge .da_status
        mov eax, [.ci]
        imul eax, PEG_R*2 + PEG_GAP
        add eax, ROW_X + PEG_R
        mov [.px], eax
        mov eax, [.ry]
        add eax, ROW_H/2
        mov [.py], eax

        mov eax, [.ci]
        movzx eax, byte [cur_guess + eax]
        test eax, eax
        jz .da_cur_empty
        call get_color_rgb
        jmp .da_cur_draw
.da_cur_empty:
        mov esi, COL_EMPTY
.da_cur_draw:
        mov ebx, [.px]
        mov ecx, [.py]
        mov edx, PEG_R
        call vbe_fill_circle
        inc dword [.ci]
        jmp .da_cur_peg

.da_status:
        ; Color palette hint
        mov ebx, 550
        mov ecx, BOARD_Y + MAX_GUESSES*ROW_H/2 - 10
        mov edx, msg_colors
        mov esi, COL_GRAY
        mov eax, 1
        call vbe_draw_str

        ; Draw 6 color swatches
        xor ecx, ecx
.da_sw:
        cmp ecx, 6
        jge .da_sw_done
        push ecx
        mov eax, ecx
        add eax, 1
        call get_color_rgb
        mov eax, ecx
        imul eax, (PEG_R*2 + 4)
        add eax, 550
        mov ebx, eax
        mov ecx, BOARD_Y + MAX_GUESSES*ROW_H/2 + 20
        mov edx, PEG_R
        call vbe_fill_circle
        pop ecx
        inc ecx
        jmp .da_sw
.da_sw_done:

        ; Status messages
        cmp dword [game_over], 0
        je .da_hint_msg
        cmp dword [player_won], 1
        je .da_win_msg
        ; Lose — show secret
        mov ebx, 550
        mov ecx, BOARD_Y + MAX_GUESSES*ROW_H/2 + 80
        mov edx, msg_lose
        mov esi, 0x00FF4444
        mov eax, 2
        call vbe_draw_str
        ; Show secret code pegs
        xor ecx, ecx
.da_secret:
        cmp ecx, CODE_LEN
        jge .da_over_prompt
        push ecx
        movzx eax, byte [secret + ecx]
        call get_color_rgb
        mov eax, ecx
        imul eax, PEG_R*2 + PEG_GAP
        add eax, 550
        mov ebx, eax
        mov ecx, BOARD_Y + MAX_GUESSES*ROW_H/2 + 115
        mov edx, PEG_R
        call vbe_fill_circle
        pop ecx
        inc ecx
        jmp .da_secret

.da_win_msg:
        mov ebx, 560
        mov ecx, BOARD_Y + MAX_GUESSES*ROW_H/2 + 80
        mov edx, msg_win
        mov esi, COL_YELLOW
        mov eax, 2
        call vbe_draw_str

.da_over_prompt:
        mov ebx, 540
        mov ecx, BOARD_Y + MAX_GUESSES*ROW_H/2 + 150
        mov edx, msg_new_game
        mov esi, COL_GRAY
        mov eax, 1
        call vbe_draw_str
        jmp .da_end

.da_hint_msg:
        mov ebx, 545
        mov ecx, BOARD_Y + MAX_GUESSES*ROW_H/2 + 150
        mov edx, msg_hint
        mov esi, COL_GRAY
        mov eax, 1
        call vbe_draw_str

.da_end:
        VBE_GAME_PRESENT
        popad
        ret

.ri: dd 0
.ci: dd 0
.fi: dd 0
.ry: dd 0
.px: dd 0
.py: dd 0
.fb: dd 0
.fw: dd 0
.fdy: dd 0
.fdpx: dd 0
.fdpy: dd 0

;=== Data ===
msg_title:    db "MASTERMIND", 0
msg_colors:   db "1=RED 2=GREEN 3=BLUE 4=YELLOW 5=ORANGE 6=PURPLE", 0
msg_hint:     db "1-6=PICK COLOR  ENTER=GUESS  BKSP=DEL  Q=QUIT", 0
msg_win:      db "YOU WIN!", 0
msg_lose:     db "GAME OVER! CODE WAS:", 0
msg_new_game: db "ANY KEY FOR NEW GAME", 0

secret:         times CODE_LEN db 0
guess_history:  times MAX_GUESSES*CODE_LEN db 0
feedback:       times MAX_GUESSES*CODE_LEN db 0
cur_guess:      times CODE_LEN db 0
cur_pos:        dd 0
num_guesses:    dd 0
game_over:      dd 0
player_won:     dd 0
rand_state:     dd 0xCAFEBABE
hs_loaded:      db 0
score_played:   dd 0
best_guesses:   dd 0
hs_name_mm:     db "mastermind", 0
