; simon.asm - Simon Says VBE graphics game for Mellivora OS
; Watch the flashing colour sequence, then repeat it using the mouse
; or keys R/G/B/Y.  Sequence grows by one each round.

%include "syscalls.inc"
%include "lib/vbe_game.inc"
%include "lib/font.inc"
%include "lib/highscore.inc"
%include "lib/audio.inc"

MAX_SEQ         equ 100

; Button quadrant layout (two wide x two tall, leaving thin gap)
GAP             equ 6
BTN_W           equ (320 - GAP)    ; 314
BTN_H           equ (240 - GAP)    ; 234

; Pixel positions of each quadrant (index 0-3)
; 0=Red TL, 1=Green TR, 2=Blue BL, 3=Yellow BR
BTN0_X equ 0
BTN0_Y equ 0
BTN1_X equ (320 + GAP)
BTN1_Y equ 0
BTN2_X equ 0
BTN2_Y equ (240 + GAP)
BTN3_X equ (320 + GAP)
BTN3_Y equ (240 + GAP)

; Dark colours
COL_RED_D    equ 0x00880000
COL_GRN_D    equ 0x00008800
COL_BLU_D    equ 0x00000088
COL_YEL_D    equ 0x00888800
; Bright colours
COL_RED_B    equ 0x00FF4444
COL_GRN_B    equ 0x0044FF44
COL_BLU_B    equ 0x004444FF
COL_YEL_B    equ 0x00FFFF44
; UI
COL_GAP      equ 0x00111111
COL_TEXT     equ 0x00FFFFFF

; States
ST_SHOW      equ 0    ; computer showing sequence
ST_INPUT     equ 1    ; player's turn
ST_CORRECT   equ 2    ; brief pause after correct
ST_GAMEOVER  equ 3

; Beep frequencies for each colour
BEEP_RED     equ 262
BEEP_GRN     equ 330
BEEP_BLU     equ 392
BEEP_YEL     equ 523
FLASH_TICKS  equ 25
PAUSE_TICKS  equ 12

start:
        VBE_GAME_INIT
        call init_game

.main_loop:
        cmp byte [gstate], ST_SHOW
        je  .do_show
        cmp byte [gstate], ST_CORRECT
        je  .do_correct
        ; ST_INPUT or ST_GAMEOVER: poll events
        jmp .poll

.do_show:
        call show_sequence
        mov  byte [input_pos], 0
        mov  byte [gstate], ST_INPUT
        jmp  .main_loop

.do_correct:
        call draw_board_all_dark
        VBE_GAME_PRESENT
        mov  eax, SYS_SLEEP
        mov  ebx, 20
        int  0x80
        call add_to_sequence
        mov  byte [gstate], ST_SHOW
        jmp  .main_loop

.poll:
        call draw_board_all_dark
        VBE_GAME_PRESENT

        ; Check keyboard
        VBE_GAME_POLL_KEY
        cmp  eax, -1
        jne  .check_key

        ; Check mouse button
        mov  eax, SYS_MOUSE
        int  0x80
        ; EAX=x, EBX=y, ECX=buttons
        test ecx, 1
        jz   .poll
        ; debounce: wait for release
        call wait_mouse_release
        ; determine which button was clicked
        call coord_to_button        ; EBX=x, ECX=y → EAX=0-3 or -1
        cmp  eax, -1
        je   .poll
        jmp  .handle_input

.check_key:
        cmp  byte [gstate], ST_GAMEOVER
        jne  .ck_play
        ; any key restarts
        cmp  eax, KEY_Q
        je   .quit
        cmp  eax, 'Q'
        je   .quit
        cmp  eax, KEY_ESC
        je   .quit
        call init_game
        jmp  .main_loop
.ck_play:
        cmp  eax, KEY_ESC
        je   .quit
        cmp  eax, KEY_Q
        je   .quit
        cmp  eax, 'Q'
        je   .quit
        ; R='r'→0, G='g'→1, B='b'→2, Y='y'→3
        cmp  eax, 'r'
        je   .kred
        cmp  eax, 'g'
        je   .kgrn
        cmp  eax, 'b'
        je   .kblu
        cmp  eax, 'y'
        je   .kyel
        jmp  .poll
.kred: mov eax, 0
        jmp .handle_input
.kgrn: mov eax, 1
        jmp .handle_input
.kblu: mov eax, 2
        jmp .handle_input
.kyel: mov eax, 3

.handle_input:
        cmp  byte [gstate], ST_INPUT
        jne  .poll
        ; Flash the button
        push eax
        call flash_button       ; EAX=btn index
        pop  eax
        ; check against sequence
        movzx ecx, byte [input_pos]
        cmp  al, [sequence + ecx]
        jne  .wrong
        inc  byte [input_pos]
        movzx ecx, byte [input_pos]
        cmp  ecx, [seq_len]
        jl   .poll
        ; completed round
        mov  byte [gstate], ST_CORRECT
        jmp  .main_loop
.wrong:
        mov  byte [gstate], ST_GAMEOVER
        call draw_gameover
        VBE_GAME_PRESENT
        jmp  .poll

.quit:
        mov eax, SYS_FRAMEBUF
        mov ebx, 2
        int 0x80
        mov eax, SYS_EXIT
        xor ebx, ebx
        int 0x80

;---------------------------------------
init_game:
        pushad
        mov dword [seq_len], 0
        mov byte  [gstate], ST_SHOW
        mov byte  [input_pos], 0
        mov byte  [go_played], 0
        mov esi, hs_name_simon
        call hs_load
        mov [hi_score], eax
        mov eax, SYS_GETTIME
        int 0x80
        mov [rng], eax
        call add_to_sequence
        popad
        ret

;---------------------------------------
add_to_sequence:
        pushad
        mov eax, [rng]
        imul eax, 1103515245
        add  eax, 12345
        mov  [rng], eax
        shr  eax, 16
        and  eax, 3
        mov  ecx, [seq_len]
        cmp  ecx, MAX_SEQ
        jge  .ats_done
        mov  [sequence + ecx], al
        inc  dword [seq_len]
.ats_done:
        popad
        ret

;---------------------------------------
; coord_to_button: EBX=x, ECX=y → EAX = button index (0-3) or -1
coord_to_button:
        pushad
        mov  eax, -1
        ; ignore clicks in the gap
        cmp  ebx, BTN_W
        jle  .ctb_check_lr
        cmp  ebx, 320 + GAP
        jl   .ctb_done          ; in gap

.ctb_check_lr:
        cmp  ecx, BTN_H
        jle  .ctb_top
        cmp  ecx, 240 + GAP
        jl   .ctb_done          ; in gap
        ; bottom half
        cmp  ebx, 320
        jl   .ctb_bl
        mov  eax, 3             ; Yellow BR
        jmp  .ctb_done
.ctb_bl:
        mov  eax, 2             ; Blue BL
        jmp  .ctb_done
.ctb_top:
        ; top half
        cmp  ebx, 320
        jl   .ctb_tl
        mov  eax, 1             ; Green TR
        jmp  .ctb_done
.ctb_tl:
        mov  eax, 0             ; Red TL
.ctb_done:
        mov  [esp + 28], eax
        popad
        ret

;---------------------------------------
; draw_board_all_dark - draw all 4 buttons in dark state
draw_board_all_dark:
        pushad
        ; Gap background
        mov  edx, COL_GAP
        call vbe_clear_screen
        ; Draw 4 dark panels
        mov  ebx, BTN0_X
        mov  ecx, BTN0_Y
        mov  edx, BTN_W
        mov  esi, BTN_H
        mov  edi, COL_RED_D
        call vbe_fill_rect

        mov  ebx, BTN1_X
        mov  ecx, BTN1_Y
        mov  edx, BTN_W
        mov  esi, BTN_H
        mov  edi, COL_GRN_D
        call vbe_fill_rect

        mov  ebx, BTN2_X
        mov  ecx, BTN2_Y
        mov  edx, BTN_W
        mov  esi, BTN_H
        mov  edi, COL_BLU_D
        call vbe_fill_rect

        mov  ebx, BTN3_X
        mov  ecx, BTN3_Y
        mov  edx, BTN_W
        mov  esi, BTN_H
        mov  edi, COL_YEL_D
        call vbe_fill_rect

        ; Round counter — dark panel behind text, scale 2
        mov  ebx, 242
        mov  ecx, 105
        mov  edx, 156
        mov  esi, 24
        mov  edi, 0x00222222
        call vbe_fill_rect
        mov  ebx, 248
        mov  ecx, 109
        mov  edx, str_round
        mov  esi, 0x00AAAAAA
        mov  eax, 2
        call vbe_draw_str
        ; "ROUND " = 6 chars × 12px/char = 72px → number at x=248+72=320
        mov  ebx, 320
        mov  ecx, 109
        mov  edx, [seq_len]
        mov  esi, 0x00FFFFFF
        mov  eax, 2
        call vbe_draw_num

        ; Key hints
        mov  ebx, 60
        mov  ecx, 100
        mov  edx, str_r
        mov  esi, COL_RED_B
        mov  eax, 1
        call vbe_draw_str

        mov  ebx, 380
        mov  ecx, 100
        mov  edx, str_g
        mov  esi, COL_GRN_B
        mov  eax, 1
        call vbe_draw_str

        mov  ebx, 60
        mov  ecx, 340
        mov  edx, str_b
        mov  esi, COL_BLU_B
        mov  eax, 1
        call vbe_draw_str

        mov  ebx, 380
        mov  ecx, 340
        mov  edx, str_y
        mov  esi, COL_YEL_B
        mov  eax, 1
        call vbe_draw_str

        popad
        ret

;---------------------------------------
; draw_button_bright: EAX = button index
draw_button_bright:
        pushad
        ; look up coords and bright colour
        cmp  eax, 0
        jne  .db1
        mov  ebx, BTN0_X
        mov  ecx, BTN0_Y
        mov  edi, COL_RED_B
        jmp  .db_draw
.db1:   cmp  eax, 1
        jne  .db2
        mov  ebx, BTN1_X
        mov  ecx, BTN1_Y
        mov  edi, COL_GRN_B
        jmp  .db_draw
.db2:   cmp  eax, 2
        jne  .db3
        mov  ebx, BTN2_X
        mov  ecx, BTN2_Y
        mov  edi, COL_BLU_B
        jmp  .db_draw
.db3:   mov  ebx, BTN3_X
        mov  ecx, BTN3_Y
        mov  edi, COL_YEL_B
.db_draw:
        mov  edx, BTN_W
        mov  esi, BTN_H
        call vbe_fill_rect
        popad
        ret

;---------------------------------------
; flash_button: EAX = button index — flash bright then dark with beep
flash_button:
        pushad
        call draw_board_all_dark
        call draw_button_bright     ; EAX still valid (pushad saves old)
        VBE_GAME_PRESENT

        ; beep
        push eax
        mov  ecx, eax
        mov  eax, SYS_BEEP
        mov  ebx, [beep_freq + ecx * 4]
        mov  ecx, 120
        int  0x80
        pop  eax

        mov  eax, SYS_SLEEP
        mov  ebx, FLASH_TICKS
        int  0x80

        call draw_board_all_dark
        VBE_GAME_PRESENT

        mov  eax, SYS_SLEEP
        mov  ebx, PAUSE_TICKS
        int  0x80
        popad
        ret

;---------------------------------------
show_sequence:
        pushad
        call draw_board_all_dark
        VBE_GAME_PRESENT
        mov  eax, SYS_SLEEP
        mov  ebx, 30
        int  0x80

        xor  ecx, ecx
.ss_loop:
        cmp  ecx, [seq_len]
        jge  .ss_done
        push ecx
        movzx eax, byte [sequence + ecx]
        call flash_button
        pop  ecx
        inc  ecx
        jmp  .ss_loop
.ss_done:
        call draw_board_all_dark
        VBE_GAME_PRESENT
        popad
        ret

;---------------------------------------
wait_mouse_release:
        push eax
        push ebx
        push ecx
.wmr:   mov  eax, SYS_MOUSE
        int  0x80
        test ecx, 1
        jnz  .wmr
        pop  ecx
        pop  ebx
        pop  eax
        ret

;---------------------------------------
draw_gameover:
        pushad
        ; Persist high score and play loss SFX once
        cmp byte [go_played], 0
        jne .dgo_drawn
        mov byte [go_played], 1
        mov eax, [seq_len]
        sub eax, 1
        mov ebx, eax
        mov esi, hs_name_simon
        call hs_update
        mov [hi_score], eax
        call audio_sfx_lose
.dgo_drawn:
        call draw_board_all_dark
        ; "GAME OVER" banner
        mov  ebx, 160
        mov  ecx, 216
        mov  edx, str_gameover
        mov  esi, 0x00FF4444
        mov  eax, 3
        call vbe_draw_str
        mov  ebx, 210
        mov  ecx, 260
        mov  edx, str_score
        mov  esi, 0x00FFFFFF
        mov  eax, 1
        call vbe_draw_str
        mov  ebx, 318
        mov  ecx, 260
        mov  edx, [seq_len]
        sub  edx, 1             ; failed on this round
        mov  esi, 0x00FFFF44
        mov  eax, 1
        call vbe_draw_num
        ; HIGH score
        mov  ebx, 210
        mov  ecx, 275
        mov  edx, str_hi
        mov  esi, 0x00FFFFFF
        mov  eax, 1
        call vbe_draw_str
        mov  ebx, 318
        mov  ecx, 275
        mov  edx, [hi_score]
        mov  esi, 0x00FFAA44
        mov  eax, 1
        call vbe_draw_num
        mov  ebx, 170
        mov  ecx, 285
        mov  edx, str_restart
        mov  esi, 0x00AAAAAA
        mov  eax, 1
        call vbe_draw_str
        popad
        ret

;---------------------------------------
str_round:   db "ROUND ", 0
str_r:       db "R", 0
str_g:       db "G", 0
str_b:       db "B", 0
str_y:       db "Y", 0
str_gameover: db "GAME OVER", 0
str_score:   db "SCORE  ", 0
str_hi:      db "HIGH   ", 0
str_restart: db "PRESS ANY KEY TO RESTART  Q=QUIT", 0

beep_freq:   dd BEEP_RED, BEEP_GRN, BEEP_BLU, BEEP_YEL

sequence:    times MAX_SEQ db 0
seq_len:     dd 0
input_pos:   db 0
gstate:      db ST_SHOW
rng:         dd 0
hi_score:    dd 0
go_played:   db 0
hs_name_simon: db "simon", 0
