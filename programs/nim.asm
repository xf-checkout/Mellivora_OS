; nim.asm - Nim (misere) VBE graphics game for Mellivora OS
; Three rows: 5, 4, 3 objects. Take any number from one row.
; Player who takes the last object LOSES (misere nim).
; Controls: 1/2/3 select row, 1-5 select count.

%include "syscalls.inc"
%include "lib/vbe_game.inc"
%include "lib/font.inc"
%include "lib/audio.inc"
%include "lib/highscore.inc"

; Layout
OBJ_R           equ 18
OBJ_SPACING     equ 52
ROW1_Y          equ 145
ROW2_Y          equ 255
ROW3_Y          equ 365
ROW_X_START     equ 120

; Scancodes for keys 1-7
SC_1 equ '1'
SC_2 equ '2'
SC_3 equ '3'
SC_4 equ '4'
SC_5 equ '5'
SC_6 equ 0x07
SC_7 equ 0x08

; Game states
ST_PICK_ROW equ 0
ST_PICK_CNT equ 1
ST_AI       equ 2
ST_WIN      equ 3
ST_LOSE     equ 4

; Colours
COL_BG     equ 0x001A1A2E
COL_OBJ    equ 0x0033BB66
COL_OBJSEL equ 0x0066FFAA
COL_ROWHL  equ 0x00334422
COL_TEXT   equ 0x00DDDDFF
COL_WIN    equ 0x0044FF88
COL_LOSE   equ 0x00FF4444
COL_LABEL  equ 0x00AAAACC

start:
        VBE_GAME_INIT
        ; Load persistent wins from /scores/nim into score_w (clamp 0..255)
        mov esi, hs_name_nm
        call hs_load
        cmp eax, 255
        jbe .hs_ok
        mov eax, 255
.hs_ok:
        mov [score_w], al
        call init_game

.game_loop:
        call draw_scene
        VBE_GAME_PRESENT

        cmp byte [gstate], ST_AI
        jne .poll_key
        call ai_move
        call check_over
        cmp byte [gstate], ST_WIN
        je .game_loop
        cmp byte [gstate], ST_LOSE
        je .game_loop
        mov byte [gstate], ST_PICK_ROW
        jmp .game_loop

.poll_key:
        VBE_GAME_POLL_KEY
        cmp eax, -1
        je  .game_loop

        cmp eax, KEY_ESC
        je  .quit
        cmp eax, KEY_Q
        je  .quit
        cmp eax, 'Q'
        je  .quit
        cmp eax, KEY_R
        je  .restart

        cmp byte [gstate], ST_WIN
        je  .restart
        cmp byte [gstate], ST_LOSE
        je  .restart

        cmp byte [gstate], ST_PICK_ROW
        je  .handle_row
        cmp byte [gstate], ST_PICK_CNT
        je  .handle_cnt
        jmp .game_loop

.handle_row:
        cmp eax, SC_1
        jne .hr2
        cmp dword [row0], 0
        je  .game_loop
        mov byte [chosen], 0
        mov byte [gstate], ST_PICK_CNT
        jmp .game_loop
.hr2:   cmp eax, SC_2
        jne .hr3
        cmp dword [row1], 0
        je  .game_loop
        mov byte [chosen], 1
        mov byte [gstate], ST_PICK_CNT
        jmp .game_loop
.hr3:   cmp eax, SC_3
        jne .game_loop
        cmp dword [row2], 0
        je  .game_loop
        mov byte [chosen], 2
        mov byte [gstate], ST_PICK_CNT
        jmp .game_loop

.handle_cnt:
        cmp eax, KEY_ESC
        je  .cancel_cnt
        ; map scancode to count 1-5
        sub eax, SC_1
        inc eax             ; 1-based
        cmp eax, 0
        jle .game_loop
        cmp eax, 7
        jg  .game_loop
        ; validate vs row
        movzx ecx, byte [chosen]
        mov edx, ecx
        imul edx, 4
        lea edx, [row0 + edx]
        cmp eax, [edx]
        jg  .game_loop
        sub [edx], eax
        call check_over
        cmp byte [gstate], ST_WIN
        je  .game_loop
        cmp byte [gstate], ST_LOSE
        je  .game_loop
        mov byte [aitook], 0
        mov byte [gstate], ST_AI
        jmp .game_loop

.cancel_cnt:
        mov byte [gstate], ST_PICK_ROW
        jmp .game_loop

.restart:
        call init_game
        jmp .game_loop

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
        mov dword [row0], 5
        mov dword [row1], 4
        mov dword [row2], 3
        mov byte  [gstate], ST_PICK_ROW
        mov byte  [chosen], 0
        mov byte  [aitook], 0
        popad
        ret

;---------------------------------------
check_over:
        mov eax, [row0]
        add eax, [row1]
        add eax, [row2]
        test eax, eax
        jnz .co_not
        ; whoever took last loses
        cmp byte [aitook], 1
        je  .co_ai_took
        ; player took last → player loses
        mov byte [gstate], ST_LOSE
        inc byte [score_l]
        call audio_sfx_lose
        ret
.co_ai_took:
        mov byte [gstate], ST_WIN
        inc byte [score_w]
        ; persist + win SFX
        movzx ebx, byte [score_w]
        mov esi, hs_name_nm
        call hs_save
        call audio_sfx_win
        ret
.co_not:
        ret

;---------------------------------------
ai_move:
        pushad
        mov byte [aitook], 1
        ; compute nim-sum
        mov eax, [row0]
        xor eax, [row1]
        xor eax, [row2]
        test eax, eax
        jz  .aim_rand
        mov [nimsum], eax
        ; find row: (row XOR nim-sum) < row
        xor ecx, ecx
.aim_find:
        cmp ecx, 3
        jge .aim_rand
        mov edx, ecx
        imul edx, 4
        mov ebx, [row0 + edx]
        test ebx, ebx
        jz  .aim_next
        mov eax, ebx
        xor eax, [nimsum]
        cmp eax, ebx
        jge .aim_next
        ; take (row - (row XOR nim-sum))
        mov [row0 + edx], eax
        jmp .aim_done
.aim_next:
        inc ecx
        jmp .aim_find
.aim_rand:
        ; take 1 from first non-empty row
        xor ecx, ecx
.aim_r:
        cmp ecx, 3
        jge .aim_done
        mov edx, ecx
        imul edx, 4
        cmp dword [row0 + edx], 0
        je  .aim_rn
        dec dword [row0 + edx]
        jmp .aim_done
.aim_rn:
        inc ecx
        jmp .aim_r
.aim_done:
        popad
        ret

;---------------------------------------
; get_row_y: ECX = row index (0-2) → EAX = pixel Y
get_row_y:
        cmp ecx, 0
        jne .gr1
        mov eax, ROW1_Y
        ret
.gr1:   cmp ecx, 1
        jne .gr2
        mov eax, ROW2_Y
        ret
.gr2:   mov eax, ROW3_Y
        ret

;---------------------------------------
draw_scene:
        pushad
        ; Background
        mov  edx, COL_BG
        call vbe_clear_screen

        ; Title
        mov  ebx, 258
        mov  ecx, 22
        mov  edx, str_title
        mov  esi, 0x00EEEEFF
        mov  eax, 2
        call vbe_draw_str

        ; Score panel (right side, x=410..608, y=105..230)
        mov  ebx, 410
        mov  ecx, 105
        mov  edx, 200
        mov  esi, 110
        mov  edi, 0x00181830
        call vbe_fill_rect

        ; WINS
        mov  ebx, 420
        mov  ecx, 114
        mov  edx, str_sw
        mov  esi, COL_WIN
        mov  eax, 1
        call vbe_draw_str
        mov  ebx, 420
        mov  ecx, 127
        movzx edx, byte [score_w]
        mov  esi, COL_WIN
        mov  eax, 3
        call vbe_draw_num

        ; LOSS
        mov  ebx, 420
        mov  ecx, 163
        mov  edx, str_sl
        mov  esi, COL_LOSE
        mov  eax, 1
        call vbe_draw_str
        mov  ebx, 420
        mov  ecx, 176
        movzx edx, byte [score_l]
        mov  esi, COL_LOSE
        mov  eax, 3
        call vbe_draw_num

        ; Draw 3 rows using local variables (no stack juggling)
        mov  dword [ds_row], 0
.ds_rowloop:
        mov  esi, [ds_row]
        cmp  esi, 3
        jge  .ds_rows_done

        ; row_y
        mov  ecx, esi
        call get_row_y
        mov  [ds_row_y], eax

        ; row count
        mov  edx, esi
        imul edx, 4
        mov  eax, [row0 + edx]
        mov  [ds_count], eax

        ; Highlight row if in ST_PICK_CNT and this is the chosen row
        cmp  byte [gstate], ST_PICK_CNT
        jne  .ds_no_hl
        movzx edx, byte [chosen]
        cmp  esi, edx
        jne  .ds_no_hl
        mov  ebx, 70
        mov  ecx, [ds_row_y]
        sub  ecx, OBJ_R + 6
        mov  edx, 490
        mov  esi, OBJ_R * 2 + 12
        mov  edi, COL_ROWHL
        call vbe_fill_rect
        mov  esi, [ds_row]      ; restore row index

.ds_no_hl:
        ; Row label digit ('1', '2', '3')
        mov  ebx, 50
        mov  ecx, [ds_row_y]
        sub  ecx, 10
        mov  esi, [ds_row]
        mov  edx, esi
        add  edx, '1'
        mov  esi, COL_LABEL
        mov  eax, 2
        call vbe_draw_char

        ; Draw circles for each object in this row
        mov  dword [ds_obj], 0
.ds_obj_loop:
        mov  ecx, [ds_obj]
        cmp  ecx, [ds_count]
        jge  .ds_obj_done

        ; cx = ROW_X_START + obj * OBJ_SPACING + OBJ_R
        imul ebx, ecx, OBJ_SPACING
        add  ebx, ROW_X_START + OBJ_R
        ; cy = row_y
        mov  ecx, [ds_row_y]
        ; radius
        mov  edx, OBJ_R
        ; colour: bright if this is the chosen row in count-pick state
        mov  esi, [ds_row]
        cmp  byte [gstate], ST_PICK_CNT
        jne  .ds_col_norm
        movzx eax, byte [chosen]
        cmp  esi, eax
        je   .ds_col_sel
.ds_col_norm:
        mov  esi, COL_OBJ
        jmp  .ds_col_done
.ds_col_sel:
        mov  esi, COL_OBJSEL
.ds_col_done:
        call vbe_fill_circle
        inc  dword [ds_obj]
        jmp  .ds_obj_loop

.ds_obj_done:
        inc  dword [ds_row]
        jmp  .ds_rowloop

.ds_rows_done:
        ; Status line
        mov  ebx, 20
        mov  ecx, 440
        cmp  byte [gstate], ST_PICK_ROW
        jne  .ds_s1
        mov  edx, str_pick_row
        mov  esi, COL_TEXT
        mov  eax, 1
        call vbe_draw_str
        jmp  .ds_sdone
.ds_s1: cmp  byte [gstate], ST_PICK_CNT
        jne  .ds_s2
        mov  edx, str_pick_cnt
        mov  esi, 0x00FFCC44
        mov  eax, 1
        call vbe_draw_str
        jmp  .ds_sdone
.ds_s2: cmp  byte [gstate], ST_AI
        jne  .ds_s3
        mov  edx, str_ai_turn
        mov  esi, 0x00FF8844
        mov  eax, 1
        call vbe_draw_str
        jmp  .ds_sdone
.ds_s3: cmp  byte [gstate], ST_WIN
        jne  .ds_s4
        mov  ebx, 190
        mov  ecx, 430
        mov  edx, str_you_win
        mov  esi, COL_WIN
        mov  eax, 2
        call vbe_draw_str
        jmp  .ds_sdone
.ds_s4: cmp  byte [gstate], ST_LOSE
        jne  .ds_sdone
        mov  ebx, 190
        mov  ecx, 430
        mov  edx, str_you_lose
        mov  esi, COL_LOSE
        mov  eax, 2
        call vbe_draw_str
.ds_sdone:
        popad
        ret

;---------------------------------------
str_title:    db "NIM", 0
str_pick_row: db "PRESS 1  2  OR 3 TO CHOOSE A ROW", 0
str_pick_cnt: db "PRESS 1-5 TO TAKE OBJECTS  ESC=CANCEL", 0
str_ai_turn:  db "AI IS THINKING...", 0
str_you_win:  db "YOU WIN!", 0
str_you_lose: db "YOU LOSE!", 0
str_sw:       db "WINS", 0
str_sl:       db "LOSS", 0

row0:    dd 5
row1:    dd 4
row2:    dd 3
nimsum:  dd 0
chosen:  db 0
gstate:  db ST_PICK_ROW
aitook:  db 0
ds_row:   dd 0
ds_row_y: dd 0
ds_count: dd 0
ds_obj:   dd 0
score_w:  db 0
score_l:  db 0
hs_name_nm: db "nim", 0
