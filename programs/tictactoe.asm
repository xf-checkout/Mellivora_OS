; tictactoe.asm - Tic-Tac-Toe vs COMP
; VBE 1024x768x32bpp. Click cell or press 1-9. COMP plays O.
%include "syscalls.inc"
%include "lib/vbe_game.inc"
%include "lib/font.inc"
%include "lib/vbe_ui.inc"
%include "lib/audio.inc"
%include "lib/highscore.inc"

CELL_SZ         equ 160
CELL_GAP        equ 6
GRID_X          equ 232         ; (1024 - 3*(160+6)) / 2
GRID_Y          equ 160

; Local color aliases reuse the project palette so the visual style stays
; in sync with the rest of the suite. (See programs/lib/palette.inc.)
COL_BG          equ MV_BG_DARK
COL_GRID        equ 0x00334466
COL_X           equ 0x00FF6644
COL_O           equ 0x0044AAFF
COL_WIN         equ MV_ACCENT_YELLOW
COL_WHITE       equ MV_FG_WHITE
COL_GRAY        equ MV_FG_DIM
COL_GREEN       equ MV_STATUS_OK
COL_PANEL       equ 0x00101828

EMPTY           equ 0
PLAYER          equ 1           ; X
COMP            equ 2           ; O

start:
        VBE_GAME_INIT
        call init_game
        call draw_all

.main_loop:
        ; Poll mouse
        mov eax, SYS_MOUSE
        int 0x80
        mov [mx], eax
        mov [my], ebx
        test ecx, ecx
        jz .no_click

        cmp dword [last_btn], 1
        je .held
        mov dword [last_btn], 1

        ; Only act if game still running
        cmp dword [game_state], 0
        jne .no_click

        ; Hit-test: cell = (mx - GRID_X) / (CELL_SZ + CELL_GAP)
        mov eax, [mx]
        sub eax, GRID_X
        js .no_click
        mov ebx, CELL_SZ + CELL_GAP
        xor edx, edx
        div ebx
        cmp eax, 3
        jge .no_click
        push eax                ; save col
        imul eax, CELL_SZ + CELL_GAP
        add eax, GRID_X
        mov ecx, [mx]
        sub ecx, eax
        cmp ecx, CELL_SZ
        pop eax
        jge .no_click
        mov [sel_col], eax

        mov eax, [my]
        sub eax, GRID_Y
        js .no_click
        mov ebx, CELL_SZ + CELL_GAP
        xor edx, edx
        div ebx
        cmp eax, 3
        jge .no_click
        push eax
        imul eax, CELL_SZ + CELL_GAP
        add eax, GRID_Y
        mov ecx, [my]
        sub ecx, eax
        cmp ecx, CELL_SZ
        pop eax
        jge .no_click
        mov [sel_row], eax

        call player_move
        jmp .after_click

.held:
        jmp .no_click

.no_click:
        cmp ecx, 0
        je .btn_released
        jmp .poll_key
.btn_released:
        mov dword [last_btn], 0

.poll_key:
        VBE_GAME_POLL_KEY
        cmp eax, -1
        je .after_key

        cmp al, 'q'
        je .quit
        cmp al, 'Q'
        je .quit
        cmp al, KEY_ESC
        je .quit

        ; R = restart at any time (style-guide convention)
        cmp al, 'r'
        je .restart_now
        cmp al, 'R'
        je .restart_now

        ; Number keys 1-9
        cmp al, '1'
        jl .after_key
        cmp al, '9'
        jg .after_key

        cmp dword [game_state], 0
        jne .game_over_key

        sub al, '1'
        movzx eax, al
        xor edx, edx
        mov ebx, 3
        div ebx
        mov [sel_row], eax
        mov [sel_col], edx
        call player_move
        jmp .after_key

.restart_now:
        call init_game
        jmp .after_key

.game_over_key:
        ; Any key restarts
        call init_game

.after_key:
        call draw_all
        mov eax, SYS_SLEEP
        mov ebx, 1
        int 0x80
        jmp .main_loop

.after_click:
        call draw_all
        jmp .main_loop

.quit:
        mov eax, SYS_FRAMEBUF
        mov ebx, 2
        int 0x80
        xor eax, eax
        int 0x80

;--------------------------------------
init_game:
        mov dword [board+0], EMPTY
        mov dword [board+4], EMPTY
        mov dword [board+8], EMPTY
        mov dword [board+12], EMPTY
        mov dword [board+16], EMPTY
        mov dword [board+20], EMPTY
        mov dword [board+24], EMPTY
        mov dword [board+28], EMPTY
        mov dword [board+32], EMPTY
        mov dword [game_state], 0   ; 0=playing, 1=X win, 2=O win, 3=draw
        mov dword [win_line], -1
        mov byte [result_played], 0
        ; First-call: load persistent win counter from /scores/tictactoe
        cmp byte [hs_loaded], 0
        jne .ig_done
        mov byte [hs_loaded], 1
        mov esi, hs_name_ttt
        call hs_load
        mov [total_wins], eax
.ig_done:
        ret

;--------------------------------------
player_move:
        ; Check cell empty
        mov eax, [sel_row]
        imul eax, 3
        add eax, [sel_col]
        mov edx, [board + eax*4]
        test edx, edx
        jnz .pm_ret

        mov dword [board + eax*4], PLAYER
        call check_winner
        test eax, eax
        jnz .pm_ret             ; game over
        call check_draw
        test eax, eax
        jnz .pm_ret
        call cpu_move
.pm_ret:
        ret

;--------------------------------------
; cpu_move: pick best available cell
; Strategy: win > block > center > corner > any
;--------------------------------------
cpu_move:
        ; Try to win
        call try_win_or_block
        test eax, eax
        jnz .cm_placed
        ; fallthrough: pick center, then corner, then any
        cmp dword [board+16], EMPTY
        jne .cm_no_center
        mov dword [board+16], COMP
        call check_winner
        call check_draw
        ret
.cm_no_center:
        ; Corners: 0,2,6,8
        push 0
        call try_cell_idx
        pop ecx
        test eax, eax
        jnz .cm_placed
        push 2
        call try_cell_idx
        pop ecx
        test eax, eax
        jnz .cm_placed
        push 6
        call try_cell_idx
        pop ecx
        test eax, eax
        jnz .cm_placed
        push 8
        call try_cell_idx
        pop ecx
        test eax, eax
        jnz .cm_placed
        ; Any empty
        mov ecx, 0
.cm_any:
        cmp ecx, 9
        jge .cm_placed
        cmp dword [board + ecx*4], EMPTY
        jne .cm_any_next
        mov dword [board + ecx*4], COMP
        call check_winner
        call check_draw
        ret
.cm_any_next:
        inc ecx
        jmp .cm_any
.cm_placed:
        ret

;--------------------------------------
; try_cell_idx: takes cell index on stack, places COMP if empty
; returns EAX=1 if placed, 0 otherwise
;--------------------------------------
try_cell_idx:
        mov eax, [esp+4]
        cmp dword [board + eax*4], EMPTY
        jne .tci_no
        mov dword [board + eax*4], COMP
        call check_winner
        call check_draw
        mov eax, 1
        ret
.tci_no:
        xor eax, eax
        ret

;--------------------------------------
; try_win_or_block: first try to win, then block player
; sets EAX=1 if placed
;--------------------------------------
try_win_or_block:
        ; Try win
        mov dword [.player], COMP
        call try_lines
        test eax, eax
        jnz .twob_done
        ; Try block
        mov dword [.player], PLAYER
        call try_lines
.twob_done:
        ret
.player: dd 0

;--------------------------------------
; try_lines: for each win line, if two cells = [.player] and one empty, place COMP there
;--------------------------------------
try_lines:
        mov esi, win_lines
        mov ecx, 8
.tl_loop:
        movzx eax, byte [esi]
        movzx ebx, byte [esi+1]
        movzx edx, byte [esi+2]
        push ecx
        push esi
        call check_line_place
        pop esi
        pop ecx
        test eax, eax
        jnz .tl_found
        add esi, 3
        loop .tl_loop
        xor eax, eax
        ret
.tl_found:
        mov eax, 1
        ret

check_line_place:
        ; EAX=i0, EBX=i1, EDX=i2; [.player]
        ; Count matching cells, find empty
        push ebx
        push edx
        push eax
        xor edi, edi            ; match count
        mov dword [.empty_idx], -1

        mov ecx, [esp]          ; i0
        call .check_one
        mov ecx, [esp+4]        ; i1
        call .check_one
        mov ecx, [esp+8]        ; i2
        call .check_one

        pop eax
        pop edx
        pop ebx

        cmp edi, 2
        jne .clp_no
        cmp dword [.empty_idx], -1
        je .clp_no
        mov eax, [.empty_idx]
        mov dword [board + eax*4], COMP
        call check_winner
        call check_draw
        mov eax, 1
        ret
.clp_no:
        xor eax, eax
        ret

.check_one:
        mov eax, [try_win_or_block.player]
        cmp [board + ecx*4], eax
        jne .co_empty
        inc edi
        ret
.co_empty:
        cmp dword [board + ecx*4], EMPTY
        jne .co_skip
        mov [.empty_idx], ecx
.co_skip:
        ret
.empty_idx: dd -1

;--------------------------------------
; check_winner: sets game_state=1 (X) or 2 (O), win_line=line idx
; returns EAX=1 if someone won
;--------------------------------------
check_winner:
        mov esi, win_lines
        xor ecx, ecx
.cw_loop:
        cmp ecx, 8
        jge .cw_no
        ; ecx*3 — compute offset since *3 not a valid scale
        lea edi, [ecx + ecx*2]  ; edi = ecx*3
        movzx eax, byte [esi + edi]
        movzx ebx, byte [esi + edi + 1]
        movzx edx, byte [esi + edi + 2]
        mov eax, [board + eax*4]
        test eax, eax
        jz .cw_next
        cmp [board + ebx*4], eax
        jne .cw_next
        cmp [board + edx*4], eax
        jne .cw_next
        ; Winner!
        mov [game_state], eax
        mov [win_line], ecx
        ; Fire SFX + persist on first detection
        cmp byte [result_played], 0
        jne .cw_yes
        mov byte [result_played], 1
        cmp eax, PLAYER
        jne .cw_comp_won
        ; Player win: bump persistent total_wins, save, play win SFX
        mov eax, [total_wins]
        inc eax
        mov [total_wins], eax
        mov esi, hs_name_ttt
        mov ebx, [total_wins]
        call hs_save
        call audio_sfx_win
        jmp .cw_yes
.cw_comp_won:
        call audio_sfx_lose
.cw_yes:
        mov eax, 1
        ret
.cw_next:
        inc ecx
        jmp .cw_loop
.cw_no:
        xor eax, eax
        ret

;--------------------------------------
check_draw:
        xor ecx, ecx
.cd_loop:
        cmp ecx, 9
        jge .cd_draw
        cmp dword [board + ecx*4], EMPTY
        je .cd_no
        inc ecx
        jmp .cd_loop
.cd_draw:
        mov dword [game_state], 3
        cmp byte [result_played], 0
        jne .cd_yes
        mov byte [result_played], 1
        call audio_sfx_click
.cd_yes:
        mov eax, 1
        ret
.cd_no:
        xor eax, eax
        ret

;--------------------------------------
draw_all:
        pushad
        mov edx, COL_BG
        call vbe_clear_screen

        ; Header band (shared widget)
        mov edx, msg_title
        mov esi, msg_subtitle
        call vbe_ui_header_bar

        ; Grid lines
        ; 3 columns, 3 rows of cells with CELL_GAP separators
        ; Draw 2 vertical + 2 horizontal dividers
        ; Vertical line after col 0
        mov ebx, GRID_X + CELL_SZ + CELL_GAP/2
        mov ecx, GRID_Y
        mov edx, 3*(CELL_SZ + CELL_GAP) - CELL_GAP
        mov esi, COL_GRID
        call vbe_draw_vline
        ; Vertical after col 1
        mov ebx, GRID_X + 2*(CELL_SZ + CELL_GAP) + CELL_GAP/2 - CELL_GAP
        call vbe_draw_vline

        ; Horizontal after row 0
        mov ebx, GRID_X
        mov ecx, GRID_Y + CELL_SZ + CELL_GAP/2
        mov edx, 3*(CELL_SZ + CELL_GAP) - CELL_GAP
        call vbe_draw_hline
        ; Horizontal after row 1
        mov ecx, GRID_Y + 2*(CELL_SZ + CELL_GAP) + CELL_GAP/2 - CELL_GAP
        call vbe_draw_hline

        ; Draw cells
        mov dword [.dr], 0
.dr_row:
        cmp dword [.dr], 3
        jge .dr_done
        mov dword [.dc], 0
.dr_col:
        cmp dword [.dc], 3
        jge .dr_col_done

        mov eax, [.dc]
        imul eax, CELL_SZ + CELL_GAP
        add eax, GRID_X
        mov [.cx], eax
        mov eax, [.dr]
        imul eax, CELL_SZ + CELL_GAP
        add eax, GRID_Y
        mov [.cy], eax

        ; Get cell state
        mov eax, [.dr]
        imul eax, 3
        add eax, [.dc]
        mov eax, [board + eax*4]

        cmp eax, PLAYER
        je .draw_x
        cmp eax, COMP
        je .draw_o
        jmp .cell_done

.draw_x:
        ; X = two diagonal lines
        mov ebx, [.cx]
        add ebx, 20
        mov ecx, [.cy]
        add ecx, 20
        mov edx, [.cx]
        add edx, CELL_SZ - 20
        mov esi, [.cy]
        add esi, CELL_SZ - 20
        mov edi, COL_X
        call vbe_draw_line
        mov ebx, [.cx]
        add ebx, CELL_SZ - 20
        mov ecx, [.cy]
        add ecx, 20
        mov edx, [.cx]
        add edx, 20
        mov esi, [.cy]
        add esi, CELL_SZ - 20
        call vbe_draw_line
        jmp .cell_done

.draw_o:
        mov ebx, [.cx]
        add ebx, CELL_SZ/2
        mov ecx, [.cy]
        add ecx, CELL_SZ/2
        mov edx, CELL_SZ/2 - 20
        mov esi, COL_O
        call vbe_draw_circle

.cell_done:
        inc dword [.dc]
        jmp .dr_col
.dr_col_done:
        inc dword [.dr]
        jmp .dr_row
.dr_done:

        ; Status message
        mov ebx, 380
        mov ecx, GRID_Y + 3*(CELL_SZ + CELL_GAP) + 20
        cmp dword [game_state], 0
        jne .gs_over
        mov edx, msg_your_turn
        mov esi, COL_GRAY
        mov eax, 2
        call vbe_draw_str
        jmp .gs_done

.gs_over:
        cmp dword [game_state], 1
        jne .gs_o_win
        mov edx, msg_x_wins
        mov esi, COL_X
        mov eax, 2
        call vbe_draw_str
        jmp .gs_show_restart

.gs_o_win:
        cmp dword [game_state], 2
        jne .gs_draw
        mov edx, msg_o_wins
        mov esi, COL_O
        mov eax, 2
        call vbe_draw_str
        jmp .gs_show_restart

.gs_draw:
        mov edx, msg_draw
        mov esi, COL_WIN
        mov eax, 2
        call vbe_draw_str

.gs_show_restart:
        mov ebx, 360
        mov ecx, GRID_Y + 3*(CELL_SZ + CELL_GAP) + 60
        mov edx, msg_restart
        mov esi, COL_GRAY
        mov eax, 1
        call vbe_draw_str

.gs_done:
        ; WINS counter (top-right, under header)
        mov ebx, 800
        mov ecx, 110
        mov edx, str_wins
        mov esi, COL_GRAY
        mov eax, 2
        call vbe_draw_str
        mov ebx, 880
        mov ecx, 110
        mov edx, [total_wins]
        mov esi, COL_WIN
        mov eax, 2
        call vbe_draw_num
        ; Status bar at the bottom (shared widget)
        mov edx, msg_status_bar
        call vbe_ui_status_bar

        VBE_GAME_PRESENT
        popad
        ret

.cx: dd 0
.cy: dd 0
.dr: dd 0
.dc: dd 0

;=== Data ===
msg_title:    db "TIC-TAC-TOE", 0
msg_subtitle: db "X = YOU   O = COMP", 0
msg_status_bar: db "CLICK CELL OR PRESS 1-9   R=NEW GAME   Q/ESC=QUIT", 0
msg_your_turn:db "YOUR TURN - CLICK OR PRESS 1-9", 0
msg_x_wins:   db "YOU WIN!", 0
msg_o_wins:   db "COMP WINS!", 0
msg_draw:     db "DRAW!", 0
msg_restart:  db "ANY KEY TO PLAY AGAIN. Q TO QUIT.", 0

; Win-line table: 8 lines × 3 cell indices
win_lines:
        db 0,1,2  ; top row
        db 3,4,5  ; mid row
        db 6,7,8  ; bot row
        db 0,3,6  ; left col
        db 1,4,7  ; mid col
        db 2,5,8  ; right col
        db 0,4,8  ; diag
        db 2,4,6  ; anti-diag

board:          times 9 dd EMPTY
game_state:     dd 0
win_line:       dd -1
sel_row:        dd 0
sel_col:        dd 0
mx:             dd 0
my:             dd 0
last_btn:       dd 0

; --- v6.5 highscore + audio state ---
hs_name_ttt:    db "tictactoe", 0
hs_loaded:      db 0
result_played:  db 0
total_wins:     dd 0
str_wins:       db "WINS:", 0

