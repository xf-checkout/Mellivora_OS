; iago.asm - Reversi/Othello for Mellivora OS in VBE graphics mode
; Player=Black (mouse click), AI=White (greedy)

%include "syscalls.inc"
%include "lib/vbe_game.inc"
%include "lib/font.inc"
%include "lib/audio.inc"
%include "lib/highscore.inc"

EMPTY   equ 0
BLACK   equ 1
WHITE   equ 2
VALID   equ 3

CELL_SZ     equ 56
BOARD_CELLS equ 8
BOARD_SZ    equ (CELL_SZ * BOARD_CELLS)   ; 448
BOARD_X     equ 96
BOARD_Y     equ 20
DISC_R      equ 22

COL_BG      equ 0x00103010
COL_FELT    equ 0x00226622
COL_GRID    equ 0x00115511
COL_BLACK_D equ 0x00111111
COL_WHITE_D equ 0x00EEEEEE
COL_VALID_D equ 0x0044BB44
COL_GOLD    equ 0x00FFD700
COL_TEXT    equ 0x00CCEECC
COL_RED_T   equ 0x00FF4444

STATE_RUNNING equ 0
STATE_OVER    equ 1

start:
        VBE_GAME_INIT
        ; Load persistent total wins from /scores/iago
        mov  esi, hs_name_ig
        call hs_load
        mov  [total_wins], eax

.restart:
        call init_board
        mov  byte [game_state], STATE_RUNNING
        mov  byte [current_player], BLACK
        mov  byte [result_played], 0
        call mark_valid_moves

.main_loop:
        call count_score
        call render_board
        VBE_GAME_PRESENT

        cmp  byte [game_state], STATE_OVER
        je   .poll_end

        ; Check keyboard
        VBE_GAME_POLL_KEY
        cmp  eax, -1
        jne  .check_key

        ; Poll mouse
        mov  eax, SYS_MOUSE
        int  0x80
        test ecx, 1
        jz   .main_loop
        call wait_mouse_up_iago
        ; EAX=x, EBX=y
        mov  ecx, ebx
        mov  ebx, eax
        call try_player_click
        jmp  .main_loop

.check_key:
        cmp  eax, KEY_ESC
        je   .quit
        cmp  eax, KEY_Q
        je   .quit
        cmp  eax, 'Q'
        je   .quit
        cmp  eax, KEY_R
        je   .restart
        jmp  .main_loop

.poll_end:
        call count_score
        call render_board
        VBE_GAME_PRESENT
        VBE_GAME_POLL_KEY
        cmp  eax, -1
        je   .poll_end
        cmp  eax, KEY_ESC
        je   .quit
        cmp  eax, KEY_Q
        je   .quit
        cmp  eax, 'Q'
        je   .quit
        cmp  eax, KEY_R
        je   .restart
        jmp  .poll_end

.quit:
        mov  eax, SYS_FRAMEBUF
        mov  ebx, 2
        int  0x80
        mov  eax, SYS_EXIT
        xor  ebx, ebx
        int  0x80

;----------------------------------------------------
wait_mouse_up_iago:
        push eax
        push ebx
        push ecx
.wmu:   mov  eax, SYS_MOUSE
        int  0x80
        test ecx, 1
        jnz  .wmu
        pop  ecx
        pop  ebx
        pop  eax
        ret

;====================================================
; try_player_click  EBX=pixel_x, ECX=pixel_y
;====================================================
try_player_click:
        pushad
        ; Convert pixel to col/row
        mov  eax, ebx
        sub  eax, BOARD_X
        cmp  eax, 0
        jl   .tpc_done
        cmp  eax, BOARD_SZ - 1
        jg   .tpc_done
        xor  edx, edx
        mov  edi, CELL_SZ
        div  edi
        mov  [click_col], eax   ; col

        mov  eax, ecx
        sub  eax, BOARD_Y
        cmp  eax, 0
        jl   .tpc_done
        cmp  eax, BOARD_SZ - 1
        jg   .tpc_done
        xor  edx, edx
        div  edi
        mov  [click_row], eax   ; row

        ; Check if cell is valid
        mov  eax, [click_row]
        imul eax, 8
        add  eax, [click_col]
        cmp  byte [board + eax], VALID
        jne  .tpc_done

        ; Place black piece
        mov  eax, [click_row]
        mov  [pm_row], eax
        mov  eax, [click_col]
        mov  [pm_col], eax
        call do_place
        call unmark_valid

        ; White's turn
        mov  byte [current_player], WHITE
        call mark_valid_moves
        call has_valid_moves
        test eax, eax
        jz   .tpc_skip_white
        call ai_move
.tpc_skip_white:
        call unmark_valid

        ; Back to black
        mov  byte [current_player], BLACK
        call mark_valid_moves
        call has_valid_moves
        test eax, eax
        jnz  .tpc_done        ; black has moves — continue

        ; Black has no moves
        call unmark_valid
        mov  byte [current_player], WHITE
        call mark_valid_moves
        call has_valid_moves
        test eax, eax
        jz   .tpc_game_over   ; neither can move
        ; White plays, black skipped
        call ai_move
        call unmark_valid
        mov  byte [current_player], BLACK
        call mark_valid_moves
        call has_valid_moves
        test eax, eax
        jnz  .tpc_done
        call unmark_valid
        jmp  .tpc_game_over

.tpc_game_over:
        mov  byte [game_state], STATE_OVER
        ; Fire SFX + persist on first detection
        cmp  byte [result_played], 0
        jne  .tpc_done
        mov  byte [result_played], 1
        call count_score
        mov  eax, [score_black]
        cmp  eax, [score_white]
        jle  .tpc_not_win
        ; Player (BLACK) won: bump persistent wins, save, win SFX
        mov  eax, [total_wins]
        inc  eax
        mov  [total_wins], eax
        mov  ebx, [total_wins]
        mov  esi, hs_name_ig
        call hs_save
        call audio_sfx_win
        jmp  .tpc_done
.tpc_not_win:
        je  .tpc_tie
        call audio_sfx_lose
        jmp  .tpc_done
.tpc_tie:
        call audio_sfx_click
.tpc_done:
        popad
        ret

;====================================================
; RENDERING
;====================================================
render_board:
        pushad

        ; Background
        mov  edx, COL_BG
        call vbe_clear_screen

        ; Board felt rectangle
        mov  ebx, BOARD_X - 4
        mov  ecx, BOARD_Y - 4
        mov  edx, BOARD_SZ + 8
        mov  esi, BOARD_SZ + 8
        mov  edi, COL_FELT
        call vbe_fill_rect

        ; Grid lines
        xor  esi, esi
.rg_vlines:
        cmp  esi, BOARD_CELLS + 1
        jg   .rg_hlines
        mov  ebx, BOARD_X
        imul eax, esi, CELL_SZ
        add  ebx, eax
        mov  ecx, BOARD_Y
        mov  edx, BOARD_SZ
        push esi
        mov  esi, COL_GRID
        call vbe_draw_vline
        pop  esi
        inc  esi
        jmp  .rg_vlines
.rg_hlines:
        xor  esi, esi
.rg_hl:
        cmp  esi, BOARD_CELLS + 1
        jg   .rg_cells
        mov  ebx, BOARD_X
        mov  ecx, BOARD_Y
        imul eax, esi, CELL_SZ
        add  ecx, eax
        mov  edx, BOARD_SZ
        push esi
        mov  esi, COL_GRID
        call vbe_draw_hline
        pop  esi
        inc  esi
        jmp  .rg_hl

.rg_cells:
        ; Draw each cell
        xor  esi, esi           ; row
.rg_row:
        cmp  esi, 8
        jge  .rg_ui
        xor  edi, edi           ; col
.rg_col:
        cmp  edi, 8
        jge  .rg_col_done
        ; Cell centre
        mov  eax, esi
        imul eax, CELL_SZ
        add  eax, BOARD_Y
        add  eax, CELL_SZ / 2
        mov  ecx, eax           ; cy

        mov  eax, edi
        imul eax, CELL_SZ
        add  eax, BOARD_X
        add  eax, CELL_SZ / 2
        mov  ebx, eax           ; cx

        ; Get cell value
        push esi
        push edi
        mov  eax, esi
        imul eax, 8
        add  eax, edi
        movzx eax, byte [board + eax]

        cmp  eax, BLACK
        je   .rg_black
        cmp  eax, WHITE
        je   .rg_white
        cmp  eax, VALID
        je   .rg_valid
        jmp  .rg_cell_done

.rg_black:
        mov  edx, DISC_R
        mov  esi, COL_BLACK_D
        call vbe_fill_circle
        jmp  .rg_cell_done
.rg_white:
        mov  edx, DISC_R
        mov  esi, COL_WHITE_D
        call vbe_fill_circle
        jmp  .rg_cell_done
.rg_valid:
        mov  edx, 7
        mov  esi, COL_VALID_D
        call vbe_fill_circle
.rg_cell_done:
        pop  edi
        pop  esi
        inc  edi
        jmp  .rg_col
.rg_col_done:
        inc  esi
        jmp  .rg_row

.rg_ui:
        ; Title
        mov  ebx, 258
        mov  ecx, 2
        mov  edx, str_title
        mov  esi, COL_GOLD
        mov  eax, 2
        call vbe_draw_str

        ; Score labels
        mov  ebx, BOARD_X + BOARD_SZ + 16
        mov  ecx, 40
        mov  edx, str_black_label
        mov  esi, COL_TEXT
        mov  eax, 1
        call vbe_draw_str

        mov  ecx, 60
        mov  edx, [score_black]
        mov  esi, COL_TEXT
        mov  eax, 2
        call vbe_draw_num

        mov  ecx, 90
        mov  edx, str_white_label
        mov  esi, COL_TEXT
        mov  eax, 1
        call vbe_draw_str

        mov  ecx, 110
        mov  edx, [score_white]
        mov  esi, COL_TEXT
        mov  eax, 2
        call vbe_draw_num

        ; Whose turn / game over message
        cmp  byte [game_state], STATE_OVER
        je   .rg_gameover_msg

        cmp  byte [current_player], BLACK
        je   .rg_your_turn
        ; AI thinking? (shouldn't reach here)
        jmp  .rg_status_done

.rg_your_turn:
        mov  ebx, BOARD_X + BOARD_SZ + 16
        mov  ecx, 160
        mov  edx, str_your_turn
        mov  esi, COL_TEXT
        mov  eax, 1
        call vbe_draw_str
        jmp  .rg_status_done

.rg_gameover_msg:
        ; Determine winner
        mov  eax, [score_black]
        mov  ebx, [score_white]
        cmp  eax, ebx
        jg   .rg_black_wins
        jl   .rg_white_wins
        ; Draw
        mov  ebx, BOARD_X + BOARD_SZ + 16
        mov  ecx, 160
        mov  edx, str_draw
        mov  esi, COL_GOLD
        mov  eax, 1
        call vbe_draw_str
        jmp  .rg_status_done
.rg_black_wins:
        mov  ebx, BOARD_X + BOARD_SZ + 16
        mov  ecx, 160
        mov  edx, str_you_win
        mov  esi, COL_GOLD
        mov  eax, 1
        call vbe_draw_str
        jmp  .rg_status_done
.rg_white_wins:
        mov  ebx, BOARD_X + BOARD_SZ + 16
        mov  ecx, 160
        mov  edx, str_ai_wins
        mov  esi, COL_RED_T
        mov  eax, 1
        call vbe_draw_str

.rg_status_done:
        ; Help text
        mov  ebx, BOARD_X + BOARD_SZ + 16
        mov  ecx, 440
        mov  edx, str_help
        mov  esi, 0x00779977
        mov  eax, 1
        call vbe_draw_str

        popad
        ret

;====================================================
; count_score — updates score_black / score_white
;====================================================
count_score:
        pushad
        xor  ecx, ecx
        xor  edx, edx
        xor  ebp, ebp
.cs:
        cmp  ebp, 64
        jge  .cs_done
        movzx eax, byte [board + ebp]
        cmp  eax, BLACK
        jne  .cs_w
        inc  ecx
        jmp  .cs_next
.cs_w:
        cmp  eax, WHITE
        jne  .cs_next
        inc  edx
.cs_next:
        inc  ebp
        jmp  .cs
.cs_done:
        mov  [score_black], ecx
        mov  [score_white], edx
        popad
        ret

;====================================================
; GAME LOGIC (from reversi.asm, unchanged)
;====================================================
init_board:
        mov  edi, board
        mov  ecx, 64
        xor  eax, eax
        rep  stosb
        mov  byte [board + 3*8 + 3], WHITE
        mov  byte [board + 3*8 + 4], BLACK
        mov  byte [board + 4*8 + 3], BLACK
        mov  byte [board + 4*8 + 4], WHITE
        ret

mark_valid_moves:
        xor  ebp, ebp
.mv_scan:
        cmp  ebp, 64
        jge  .mv_done
        movzx eax, byte [board + ebp]
        test eax, eax
        jnz  .mv_next
        push ebp
        call count_flips
        pop  ebp
        test eax, eax
        jz   .mv_next
        mov  byte [board + ebp], VALID
.mv_next:
        inc  ebp
        jmp  .mv_scan
.mv_done:
        ret

unmark_valid:
        xor  ebp, ebp
.uv:
        cmp  ebp, 64
        jge  .uv_done
        cmp  byte [board + ebp], VALID
        jne  .uv_next
        mov  byte [board + ebp], EMPTY
.uv_next:
        inc  ebp
        jmp  .uv
.uv_done:
        ret

has_valid_moves:
        xor  ebp, ebp
.hv:
        cmp  ebp, 64
        jge  .hv_no
        cmp  byte [board + ebp], VALID
        je   .hv_yes
        inc  ebp
        jmp  .hv
.hv_yes:
        mov  eax, 1
        ret
.hv_no:
        xor  eax, eax
        ret

; count_flips: EBP=position, current_player=[current_player]
; Returns EAX = flip count
count_flips:
        pushad
        xor  edi, edi
        mov  eax, ebp
        xor  edx, edx
        mov  ecx, 8
        div  ecx
        mov  [cf_row], eax
        mov  [cf_col], edx

        mov  esi, 0
.cf_dir:
        cmp  esi, 8
        jge  .cf_done
        movsx eax, byte [dir_dr + esi]
        movsx ecx, byte [dir_dc + esi]
        mov  [cur_dr], eax
        mov  [cur_dc], ecx
        mov  eax, [cf_row]
        add  eax, [cur_dr]
        mov  [walk_r], eax
        mov  eax, [cf_col]
        add  eax, [cur_dc]
        mov  [walk_c], eax
        xor  ecx, ecx

.cf_walk:
        cmp  dword [walk_r], 0
        jl   .cf_no_flip
        cmp  dword [walk_r], 7
        jg   .cf_no_flip
        cmp  dword [walk_c], 0
        jl   .cf_no_flip
        cmp  dword [walk_c], 7
        jg   .cf_no_flip
        mov  eax, [walk_r]
        imul eax, 8
        add  eax, [walk_c]
        movzx ebx, byte [board + eax]
        cmp  ebx, EMPTY
        je   .cf_no_flip
        cmp  ebx, VALID
        je   .cf_no_flip
        movzx edx, byte [current_player]
        cmp  ebx, edx
        je   .cf_found_own
        inc  ecx
        mov  eax, [walk_r]
        add  eax, [cur_dr]
        mov  [walk_r], eax
        mov  eax, [walk_c]
        add  eax, [cur_dc]
        mov  [walk_c], eax
        jmp  .cf_walk

.cf_found_own:
        add  edi, ecx
        jmp  .cf_next_dir

.cf_no_flip:
.cf_next_dir:
        inc  esi
        jmp  .cf_dir

.cf_done:
        mov  [esp + 28], edi
        popad
        ret

do_place:
        mov  eax, [pm_row]
        imul eax, 8
        add  eax, [pm_col]
        movzx ecx, byte [current_player]
        mov  [board + eax], cl

        mov  esi, 0
.dp_dir:
        cmp  esi, 8
        jge  .dp_done
        movsx eax, byte [dir_dr + esi]
        movsx ecx, byte [dir_dc + esi]
        mov  [cur_dr], eax
        mov  [cur_dc], ecx
        mov  eax, [pm_row]
        add  eax, [cur_dr]
        mov  [walk_r], eax
        mov  eax, [pm_col]
        add  eax, [cur_dc]
        mov  [walk_c], eax
        mov  dword [flip_count], 0

.dp_walk:
        cmp  dword [walk_r], 0
        jl   .dp_no_flip
        cmp  dword [walk_r], 7
        jg   .dp_no_flip
        cmp  dword [walk_c], 0
        jl   .dp_no_flip
        cmp  dword [walk_c], 7
        jg   .dp_no_flip
        mov  eax, [walk_r]
        imul eax, 8
        add  eax, [walk_c]
        movzx ebx, byte [board + eax]
        cmp  ebx, EMPTY
        je   .dp_no_flip
        cmp  ebx, VALID
        je   .dp_no_flip
        movzx edx, byte [current_player]
        cmp  ebx, edx
        je   .dp_do_flip
        mov  ecx, [flip_count]
        mov  [flip_buf + ecx*4], eax
        inc  dword [flip_count]
        mov  eax, [walk_r]
        add  eax, [cur_dr]
        mov  [walk_r], eax
        mov  eax, [walk_c]
        add  eax, [cur_dc]
        mov  [walk_c], eax
        jmp  .dp_walk

.dp_do_flip:
        mov  ecx, [flip_count]
        test ecx, ecx
        jz   .dp_no_flip
        movzx edx, byte [current_player]
.dp_flip_loop:
        dec  ecx
        js   .dp_next_dir
        mov  eax, [flip_buf + ecx*4]
        mov  [board + eax], dl
        jmp  .dp_flip_loop

.dp_no_flip:
.dp_next_dir:
        inc  esi
        jmp  .dp_dir
.dp_done:
        ret

ai_move:
        mov  dword [best_pos], -1
        mov  dword [best_flips], -1
        xor  ebp, ebp
.ai_scan:
        cmp  ebp, 64
        jge  .ai_done_scan
        cmp  byte [board + ebp], VALID
        jne  .ai_next
        call count_flips
        cmp  eax, [best_flips]
        jle  .ai_next
        mov  [best_flips], eax
        mov  [best_pos], ebp
.ai_next:
        inc  ebp
        jmp  .ai_scan
.ai_done_scan:
        cmp  dword [best_pos], -1
        je   .ai_no_move
        mov  ebp, [best_pos]
        mov  eax, ebp
        xor  edx, edx
        mov  ecx, 8
        div  ecx
        mov  [pm_row], eax
        mov  [pm_col], edx
        call do_place
.ai_no_move:
        ret

;====================================================
; DATA
;====================================================
str_title:       db "IAGO", 0
str_black_label: db "BLACK:", 0
str_white_label: db "WHITE:", 0
str_your_turn:   db "YOUR TURN", 0
str_draw:        db "DRAW!", 0
str_you_win:     db "YOU WIN!", 0
str_ai_wins:     db "AI WINS!", 0
str_help:        db "R=RESTART Q=QUIT", 0

dir_dr:         db -1, -1, -1,  0,  0,  1,  1,  1
dir_dc:         db -1,  0,  1, -1,  1, -1,  0,  1

current_player: db BLACK
game_state:     db STATE_RUNNING
score_black:    dd 2
score_white:    dd 2
hs_name_ig:     db "iago", 0
result_played:  db 0
total_wins:     dd 0
click_row:      dd 0
click_col:      dd 0
cf_row:         dd 0
cf_col:         dd 0
cur_dr:         dd 0
cur_dc:         dd 0
walk_r:         dd 0
walk_c:         dd 0
pm_row:         dd 0
pm_col:         dd 0
best_pos:       dd -1
best_flips:     dd -1
flip_count:     dd 0
flip_buf:       times 8 dd 0
board:          times 64 db 0
