; wordle.asm - Wordle 5-letter word game
; VBE 1024x768x32bpp. Type A-Z, BKSP=delete, ENTER=submit, ESC=quit.
%include "syscalls.inc"
%include "lib/vbe_game.inc"
%include "lib/font.inc"
%include "lib/audio.inc"
%include "lib/highscore.inc"

WORD_LEN    equ 5
MAX_TRIES   equ 6
NUM_WORDS   equ 50

BOX_SZ      equ 80
BOX_GAP     equ 8
BOX_STEP    equ BOX_SZ + BOX_GAP   ; 88
; 5 boxes: 5*88-8=432. (1024-432)/2=296
GRID_X      equ 296
GRID_Y      equ 100

COL_BG      equ 0x00121213
COL_EMPTY   equ 0x003A3A3C
COL_ACTIVE  equ 0x00565758
COL_GREEN   equ 0x00538D4E
COL_YELLOW  equ 0x00B59F3B
COL_GRAY    equ 0x003A3A3C
COL_TEXT    equ 0x00FFFFFF
COL_TITLE   equ 0x00FFFFFF
COL_DIM     equ 0x00888888

FB_EMPTY    equ 0
FB_YELLOW   equ 2
FB_GREEN    equ 3

start:
        VBE_GAME_INIT
        call new_game
        call draw_all

.main_loop:
        VBE_GAME_POLL_KEY
        cmp eax, -1
        je .no_key

        cmp al, KEY_ESC
        je .quit
        cmp al, 'q'
        je .quit
        cmp al, 'Q'
        je .quit

        cmp dword [game_over], 0
        jne .any_key

        cmp al, 0x08
        je .backspace
        cmp al, 0x7F
        je .backspace

        cmp al, 0x0D
        je .submit

        ; Letter a-z → uppercase
        cmp al, 'a'
        jl .chk_upper
        cmp al, 'z'
        jg .no_key
        sub al, 0x20
        jmp .add_ltr
.chk_upper:
        cmp al, 'A'
        jl .no_key
        cmp al, 'Z'
        jg .no_key
.add_ltr:
        cmp dword [cur_len], WORD_LEN
        jge .no_key
        mov ecx, [cur_len]
        mov [cur_input + ecx], al
        inc dword [cur_len]
        call draw_all
        jmp .no_key

.backspace:
        cmp dword [cur_len], 0
        je .no_key
        dec dword [cur_len]
        call draw_all
        jmp .no_key

.submit:
        cmp dword [cur_len], WORD_LEN
        jne .no_key
        call evaluate_guess
        call draw_all
        jmp .no_key

.any_key:
        call new_game
        call draw_all
        jmp .no_key

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
        pushad
        mov eax, SYS_GETTIME
        int 0x80
        xor edx, edx
        mov ecx, NUM_WORDS
        div ecx
        imul edx, 8
        lea esi, [word_list + edx]
        mov edi, secret
        mov ecx, WORD_LEN
        rep movsb
        mov byte [secret + WORD_LEN], 0

        mov edi, guesses
        mov ecx, MAX_TRIES * 8
        xor eax, eax
        rep stosb
        mov edi, fb_buf
        mov ecx, MAX_TRIES * WORD_LEN
        rep stosb

        mov dword [try_num], 0
        mov dword [cur_len], 0
        mov dword [game_over], 0
        ; First-call: load persistent total wins from /scores/wordle
        cmp byte [hs_loaded], 0
        jne .ng_done
        mov byte [hs_loaded], 1
        mov esi, hs_name_wd
        call hs_load
        mov [total_wins], eax
.ng_done:
        popad
        ret

;--------------------------------------
evaluate_guess:
        pushad
        ; Copy input to history
        mov eax, [try_num]
        shl eax, 3
        lea edi, [guesses + eax]
        mov esi, cur_input
        mov ecx, WORD_LEN
        rep movsb

        ; Clear ev_used
        mov dword [ev_used], 0
        mov dword [ev_used+4], 0

        ; fb_buf offset
        mov edx, [try_num]
        imul edx, WORD_LEN

        ; Pass 1: greens
        xor ecx, ecx
.eg_g:
        cmp ecx, WORD_LEN
        jge .eg_p2
        mov al, [cur_input + ecx]
        cmp al, [secret + ecx]
        jne .eg_gn
        mov byte [fb_buf + edx + ecx], FB_GREEN
        mov byte [ev_used + ecx], 1
.eg_gn:
        inc ecx
        jmp .eg_g

.eg_p2:
        xor ecx, ecx
.eg_y:
        cmp ecx, WORD_LEN
        jge .eg_done
        cmp byte [fb_buf + edx + ecx], FB_GREEN
        je .eg_yn
        mov al, [cur_input + ecx]
        xor ebx, ebx
.eg_ys:
        cmp ebx, WORD_LEN
        jge .eg_yn
        cmp byte [ev_used + ebx], 1
        je .eg_ysn
        cmp al, [secret + ebx]
        jne .eg_ysn
        mov byte [fb_buf + edx + ecx], FB_YELLOW
        mov byte [ev_used + ebx], 1
        jmp .eg_yn
.eg_ysn:
        inc ebx
        jmp .eg_ys
.eg_yn:
        inc ecx
        jmp .eg_y

.eg_done:
        ; Count greens
        xor eax, eax
        xor ecx, ecx
.eg_wc:
        cmp ecx, WORD_LEN
        jge .eg_wck
        cmp byte [fb_buf + edx + ecx], FB_GREEN
        jne .eg_wcn
        inc eax
.eg_wcn:
        inc ecx
        jmp .eg_wc
.eg_wck:
        mov dword [cur_len], 0
        inc dword [try_num]
        cmp eax, WORD_LEN
        je .eg_win
        cmp dword [try_num], MAX_TRIES
        jge .eg_lose
        popad
        ret
.eg_win:
        mov dword [game_over], 1
        ; Bump persistent wins, save, win SFX
        mov eax, [total_wins]
        inc eax
        mov [total_wins], eax
        mov ebx, [total_wins]
        mov esi, hs_name_wd
        call hs_save
        call audio_sfx_win
        popad
        ret
.eg_lose:
        mov dword [game_over], 2
        call audio_sfx_lose
        popad
        ret

;--------------------------------------
draw_all:
        pushad
        mov edx, COL_BG
        call vbe_clear_screen

        ; Title "WORDLE" centered: 6 chars*15px=90, x=(1024-90)/2=467
        mov ebx, 467
        mov ecx, 20
        mov edx, msg_title
        mov esi, COL_TITLE
        mov eax, 3
        call vbe_draw_str

        mov dword [.row], 0
.da_row:
        cmp dword [.row], MAX_TRIES
        jge .da_grid_done
        mov dword [.col], 0
.da_col:
        cmp dword [.col], WORD_LEN
        jge .da_col_done

        ; Box pixel position
        mov eax, [.col]
        imul eax, BOX_STEP
        add eax, GRID_X
        mov [.bx], eax
        mov eax, [.row]
        imul eax, BOX_STEP
        add eax, GRID_Y
        mov [.by], eax

        ; Classify row
        mov eax, [.row]
        cmp eax, [try_num]
        jl .da_subm
        je .da_cur
        ; Future empty
        mov dword [.box_c], COL_EMPTY
        mov dword [.ltr], 0
        jmp .da_draw

.da_subm:
        ; Submitted row
        mov eax, [.row]
        imul eax, WORD_LEN
        add eax, [.col]
        movzx ecx, byte [fb_buf + eax]
        cmp ecx, FB_GREEN
        je .da_s_g
        cmp ecx, FB_YELLOW
        je .da_s_y
        mov dword [.box_c], COL_GRAY
        jmp .da_s_l
.da_s_g:
        mov dword [.box_c], COL_GREEN
        jmp .da_s_l
.da_s_y:
        mov dword [.box_c], COL_YELLOW
.da_s_l:
        mov eax, [.row]
        shl eax, 3
        add eax, [.col]
        movzx ecx, byte [guesses + eax]
        mov [.ltr], ecx
        jmp .da_draw

.da_cur:
        ; Active input row
        mov eax, [.col]
        cmp eax, [cur_len]
        jge .da_cur_e
        movzx ecx, byte [cur_input + eax]
        mov [.ltr], ecx
        mov dword [.box_c], COL_ACTIVE
        jmp .da_draw
.da_cur_e:
        mov dword [.box_c], COL_EMPTY
        mov dword [.ltr], 0

.da_draw:
        mov ebx, [.bx]
        mov ecx, [.by]
        mov edx, BOX_SZ
        mov esi, BOX_SZ
        mov edi, [.box_c]
        call vbe_fill_rect

        cmp dword [.ltr], 0
        je .da_next
        ; Center letter (scale=3 → 15×21px) in 80×80 box: offset (32,29)
        mov ebx, [.bx]
        add ebx, 32
        mov ecx, [.by]
        add ecx, 29
        mov edx, [.ltr]
        mov esi, COL_TEXT
        mov eax, 3
        call vbe_draw_char

.da_next:
        inc dword [.col]
        jmp .da_col
.da_col_done:
        inc dword [.row]
        jmp .da_row

.da_grid_done:
        mov ecx, GRID_Y + MAX_TRIES * BOX_STEP + 20
        cmp dword [game_over], 1
        je .da_win
        cmp dword [game_over], 2
        je .da_lose

        mov ebx, GRID_X
        mov edx, msg_hint
        mov esi, COL_DIM
        mov eax, 1
        call vbe_draw_str
        jmp .da_end

.da_win:
        mov ebx, GRID_X + 80
        mov edx, msg_win
        mov esi, COL_GREEN
        mov eax, 2
        call vbe_draw_str
        add ecx, 35
        mov ebx, GRID_X + 40
        mov edx, msg_restart
        mov esi, COL_DIM
        mov eax, 1
        call vbe_draw_str
        jmp .da_end

.da_lose:
        mov ebx, GRID_X + 20
        mov edx, msg_lose
        mov esi, COL_YELLOW
        mov eax, 2
        call vbe_draw_str
        add ecx, 40
        mov ebx, GRID_X + 80
        mov edx, secret
        mov esi, COL_TEXT
        mov eax, 3
        call vbe_draw_str
        add ecx, 50
        mov ebx, GRID_X + 40
        mov edx, msg_restart
        mov esi, COL_DIM
        mov eax, 1
        call vbe_draw_str

.da_end:
        VBE_GAME_PRESENT
        popad
        ret

.row:   dd 0
.col:   dd 0
.bx:    dd 0
.by:    dd 0
.box_c: dd 0
.ltr:   dd 0

;=== Data ===
msg_title:   db "WORDLE", 0
msg_hint:    db "A-Z=TYPE  ENTER=SUBMIT  BKSP=DELETE  ESC=QUIT", 0
msg_win:     db "YOU WIN!", 0
msg_lose:    db "THE WORD WAS:", 0
msg_restart: db "ANY KEY = NEW GAME", 0

word_list:
        db "APPLE", 0, 0, 0
        db "BRAIN", 0, 0, 0
        db "CHAIR", 0, 0, 0
        db "DANCE", 0, 0, 0
        db "EARLY", 0, 0, 0
        db "FLAME", 0, 0, 0
        db "GRAPE", 0, 0, 0
        db "HORSE", 0, 0, 0
        db "INDEX", 0, 0, 0
        db "JEWEL", 0, 0, 0
        db "KNIFE", 0, 0, 0
        db "LEMON", 0, 0, 0
        db "MUSIC", 0, 0, 0
        db "NOBLE", 0, 0, 0
        db "OCEAN", 0, 0, 0
        db "PIANO", 0, 0, 0
        db "QUEEN", 0, 0, 0
        db "RIVER", 0, 0, 0
        db "STONE", 0, 0, 0
        db "TIGER", 0, 0, 0
        db "ULTRA", 0, 0, 0
        db "VOICE", 0, 0, 0
        db "WATER", 0, 0, 0
        db "YOUTH", 0, 0, 0
        db "ZEBRA", 0, 0, 0
        db "ANGEL", 0, 0, 0
        db "BEACH", 0, 0, 0
        db "CLOUD", 0, 0, 0
        db "DREAM", 0, 0, 0
        db "EAGLE", 0, 0, 0
        db "FROST", 0, 0, 0
        db "GHOST", 0, 0, 0
        db "HEART", 0, 0, 0
        db "IVORY", 0, 0, 0
        db "JUDGE", 0, 0, 0
        db "KNACK", 0, 0, 0
        db "LIGHT", 0, 0, 0
        db "MAGIC", 0, 0, 0
        db "NIGHT", 0, 0, 0
        db "OLIVE", 0, 0, 0
        db "PEARL", 0, 0, 0
        db "QUIET", 0, 0, 0
        db "ROYAL", 0, 0, 0
        db "SHINE", 0, 0, 0
        db "TRAIL", 0, 0, 0
        db "UNITY", 0, 0, 0
        db "VIGOR", 0, 0, 0
        db "WHEAT", 0, 0, 0
        db "CHESS", 0, 0, 0
        db "PIXEL", 0, 0, 0

secret:     times 8 db 0
cur_input:  times 8 db 0
guesses:    times MAX_TRIES * 8 db 0
fb_buf:     times MAX_TRIES * WORD_LEN db 0
ev_used:    times 8 db 0
try_num:    dd 0
cur_len:    dd 0
game_over:  dd 0
hs_name_wd: db "wordle", 0
hs_loaded:  db 0
total_wins: dd 0
