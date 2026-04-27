; checkers.asm - Checkers (draughts)
; VBE 1024x768x32bpp. 8x8 board. Arrow keys + Enter to select/move. Q to quit.
; Player=Red(moves up), AI=Black(moves down). Kings on back rank.
%include "syscalls.inc"
%include "lib/vbe_game.inc"
%include "lib/font.inc"
%include "lib/audio.inc"
%include "lib/highscore.inc"

BSIZE           equ 8
CELL_SZ         equ 80
CELL_GAP        equ 2
GRID_X          equ 100
GRID_Y          equ 80

EMPTY           equ 0
RED             equ 1
RED_K           equ 2
BLACK           equ 3
BLACK_K         equ 4

COL_DARK        equ 0x00633B1E
COL_LIGHT       equ 0x00DEB887
COL_RED_P       equ 0x00EE2222
COL_RED_K2      equ 0x00FF8888
COL_BLK_P       equ 0x00222222
COL_BLK_K2      equ 0x00888888
COL_SEL         equ 0x00FFEE44
COL_CURSOR      equ 0x0044FFCC
COL_BG          equ 0x000A0A0A
COL_WHITE       equ 0x00FFFFFF
COL_GRAY        equ 0x00888888
COL_GREEN       equ 0x0033EE55
COL_YELLOW      equ 0x00FFE040

DISC_R          equ 30

; States
STATE_SELECT    equ 0           ; cursor = pick a piece
STATE_MOVE      equ 1           ; piece selected, pick destination

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

        cmp dword [game_over], 1
        je .restart

        cmp al, KEY_UP
        je .cur_up
        cmp al, KEY_DOWN
        je .cur_down
        cmp al, KEY_LEFT
        je .cur_left
        cmp al, KEY_RIGHT
        je .cur_right
        cmp al, 0x0D
        je .action
        cmp al, 0x08
        je .cancel
        jmp .no_key

.cur_up:
        cmp dword [cur_row], 0
        je .no_key
        dec dword [cur_row]
        jmp .redraw
.cur_down:
        cmp dword [cur_row], BSIZE-1
        je .no_key
        inc dword [cur_row]
        jmp .redraw
.cur_left:
        cmp dword [cur_col], 0
        je .no_key
        dec dword [cur_col]
        jmp .redraw
.cur_right:
        cmp dword [cur_col], BSIZE-1
        je .no_key
        inc dword [cur_col]
        jmp .redraw

.action:
        cmp dword [state], STATE_SELECT
        je .select_piece
        ; Move phase
        call try_move
        jmp .redraw

.select_piece:
        ; Is there a red piece here?
        mov eax, [cur_row]
        imul eax, BSIZE
        add eax, [cur_col]
        movzx ecx, byte [board + eax]
        cmp ecx, RED
        je .sel_ok
        cmp ecx, RED_K
        jne .no_key
.sel_ok:
        mov eax, [cur_row]
        mov [sel_row], eax
        mov eax, [cur_col]
        mov [sel_col], eax
        mov dword [state], STATE_MOVE
        jmp .redraw

.cancel:
        mov dword [state], STATE_SELECT
        jmp .redraw

.restart:
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
        ; Clear board
        xor ecx, ecx
.ng_c:
        cmp ecx, BSIZE*BSIZE
        jge .ng_place
        mov byte [board + ecx], EMPTY
        inc ecx
        jmp .ng_c
.ng_place:
        ; Black pieces: rows 0-2, dark squares
        ; Red pieces: rows 5-7, dark squares
        xor ecx, ecx
.ng_loop:
        cmp ecx, BSIZE*BSIZE
        jge .ng_done
        mov eax, ecx
        xor edx, edx
        mov ebx, BSIZE
        div ebx             ; EAX=row, EDX=col
        ; Dark square: (row+col) odd
        mov ebx, eax
        add ebx, edx
        test ebx, 1
        jz .ng_skip
        cmp eax, 3
        jl .ng_black
        cmp eax, 5
        jl .ng_skip
        ; Red piece
        mov byte [board + ecx], RED
        jmp .ng_skip
.ng_black:
        mov byte [board + ecx], BLACK
.ng_skip:
        inc ecx
        jmp .ng_loop
.ng_done:
        mov dword [cur_row], 5
        mov dword [cur_col], 0
        mov dword [sel_row], -1
        mov dword [sel_col], -1
        mov dword [state], STATE_SELECT
        mov dword [game_over], 0
        mov byte [result_played], 0
        ; First-call: load persistent wins from /scores/checkers
        cmp byte [hs_loaded], 0
        jne .ng_loaded
        mov byte [hs_loaded], 1
        pushad
        mov esi, hs_name_ck
        call hs_load
        mov [total_wins], eax
        popad
.ng_loaded:
        ret

;--------------------------------------
; try_move: attempt to move sel→cur (player)
; Simple: 1-step diagonal or capture
;--------------------------------------
try_move:
        mov eax, [sel_row]
        mov ebx, [sel_col]
        mov ecx, [cur_row]
        mov edx, [cur_col]

        ; Dest must be empty
        mov esi, ecx
        imul esi, BSIZE
        add esi, edx
        movzx esi, byte [board + esi]
        test esi, esi
        jnz .tm_cancel

        ; Source must be red piece
        mov esi, eax
        imul esi, BSIZE
        add esi, ebx
        movzx esi, byte [board + esi]
        cmp esi, RED
        je .tm_piece
        cmp esi, RED_K
        jne .tm_cancel
        mov dword [.is_king], 1
        jmp .tm_calc
.tm_piece:
        mov dword [.is_king], 0

.tm_calc:
        ; dr = cur_row - sel_row, dc = cur_col - sel_col
        mov edi, ecx
        sub edi, eax        ; dr
        push ecx
        push edx
        mov ecx, edx
        sub ecx, ebx        ; dc
        mov [.dr], edi
        mov [.dc], ecx
        pop edx
        pop ecx

        ; Regular red moves UP (dr = -1) or king ±1
        cmp dword [.is_king], 0
        je .tm_check_dir

        ; King: allow dr = ±1
        mov esi, [.dr]
        cmp esi, 1
        je .tm_check_dc
        cmp esi, -1
        jne .tm_cancel
        jmp .tm_check_dc

.tm_check_dir:
        cmp dword [.dr], -1
        jne .tm_try_cap

.tm_check_dc:
        mov esi, [.dc]
        cmp esi, 1
        je .tm_ok
        cmp esi, -1
        jne .tm_try_cap
        jmp .tm_ok

.tm_try_cap:
        ; Try capture: dr=±2, dc=±2
        mov esi, [.dr]
        cmp esi, -2
        je .tm_cap_dr
        cmp dword [.is_king], 1
        jne .tm_cancel
        cmp esi, 2
        jne .tm_cancel

.tm_cap_dr:
        mov esi, [.dc]
        cmp esi, 2
        je .tm_cap_dc
        cmp esi, -2
        jne .tm_cancel

.tm_cap_dc:
        ; Check mid cell has opponent (black)
        mov esi, eax          ; sel_row
        add esi, [.dr]
        sar esi, 1            ; (sel_row + dr/2)
        ; Hmm, (sel_row + cur_row)/2
        mov esi, eax
        add esi, ecx
        sar esi, 1
        mov edi, ebx
        add edi, edx
        sar edi, 1
        push esi
        push edi
        imul esi, BSIZE
        add esi, edi
        movzx esi, byte [board + esi]
        pop edi
        pop esi
        cmp esi, BLACK
        je .tm_cap_ok
        cmp esi, BLACK_K
        jne .tm_cancel

.tm_cap_ok:
        ; Remove captured piece
        mov esi, eax
        add esi, ecx
        sar esi, 1
        mov edi, ebx
        add edi, edx
        sar edi, 1
        imul esi, BSIZE
        add esi, edi
        mov byte [board + esi], EMPTY

.tm_ok:
        ; Move piece from sel to cur
        ; EAX=sel_row, EBX=sel_col, ECX=cur_row, EDX=cur_col
        mov esi, eax
        imul esi, BSIZE
        add esi, ebx
        movzx edi, byte [board + esi]   ; EDI = piece
        mov [.piece_tmp], edi
        mov byte [board + esi], EMPTY

        mov esi, ecx
        imul esi, BSIZE
        add esi, edx
        mov ebx, [.piece_tmp]
        mov [board + esi], bl          ; write piece byte

        ; King promotion: row=0 for red
        cmp ecx, 0
        jne .tm_no_promote
        cmp byte [board + esi], RED
        jne .tm_no_promote
        mov byte [board + esi], RED_K
.tm_no_promote:

        mov dword [state], STATE_SELECT
        ; AI turn
        call ai_move
        call check_game_over
        ret

.tm_cancel:
        mov dword [state], STATE_SELECT
        ret

.is_king:   dd 0
.dr:        dd 0
.dc:        dd 0
.piece_tmp: dd 0

;--------------------------------------
; Greedy AI: find capture or any valid black move
;--------------------------------------
ai_move:
        ; Try captures first
        xor ecx, ecx
.ai_cap:
        cmp ecx, BSIZE*BSIZE
        jge .ai_step
        mov eax, ecx
        xor edx, edx
        mov ebx, BSIZE
        div ebx
        movzx esi, byte [board + ecx]
        cmp esi, BLACK
        je .ai_cap_try
        cmp esi, BLACK_K
        jne .ai_cap_next
.ai_cap_try:
        push ecx
        push eax
        push edx
        ; Try 4 diagonal captures
        mov [.srow], eax
        mov [.scol], edx
        cmp esi, BLACK_K
        je .ai_try_cap_all
        ; Regular: only dr=+2
        call .try_cap_fwd
        pop edx
        pop eax
        pop ecx
        jmp .ai_cap_next

.ai_try_cap_all:
        call .try_cap_fwd
        pop edx
        pop eax
        pop ecx
        jmp .ai_cap_next

.ai_cap_next:
        inc ecx
        jmp .ai_cap

.ai_step:
        ; No capture: simple move
        xor ecx, ecx
.ai_mv:
        cmp ecx, BSIZE*BSIZE
        jge .ai_done
        mov eax, ecx
        xor edx, edx
        mov ebx, BSIZE
        div ebx
        movzx esi, byte [board + ecx]
        cmp esi, BLACK
        je .ai_mv_try
        cmp esi, BLACK_K
        jne .ai_mv_next
.ai_mv_try:
        push ecx
        push eax
        push edx
        mov [.srow], eax
        mov [.scol], edx
        ; Try dr=+1, dc=±1
        mov edi, eax
        add edi, 1
        call .try_step
        pop edx
        pop eax
        pop ecx
.ai_mv_next:
        inc ecx
        jmp .ai_mv

.ai_done:
        ret

.try_step:
        ; EDI=dst_row; try dc=-1 and dc=+1
        mov esi, [.scol]
        dec esi
        call .step_one
        mov esi, [.scol]
        inc esi
        call .step_one
        ret

.step_one:
        ; EDI=dst_row, ESI=dst_col
        cmp edi, 0
        jl .so_ret
        cmp edi, BSIZE
        jge .so_ret
        cmp esi, 0
        jl .so_ret
        cmp esi, BSIZE
        jge .so_ret
        push edi
        push esi
        imul edi, BSIZE
        add edi, esi
        movzx edi, byte [board + edi]
        test edi, edi
        pop esi
        pop edi
        jnz .so_ret
        ; Move!
        mov eax, [.srow]
        mov ebx, [.scol]
        imul eax, BSIZE
        add eax, ebx
        movzx ecx, byte [board + eax]
        mov byte [board + eax], EMPTY
        push ecx
        push edi
        push esi
        imul edi, BSIZE
        add edi, esi
        pop esi
        pop edi
        pop ecx
        push edi
        push esi
        push ecx
        imul edi, BSIZE
        add edi, esi
        pop ecx
        mov [board + edi], cl
        pop esi
        pop edi
        ; King promotion: row=7 for black
        cmp edi, BSIZE-1
        jne .so_np
        push esi
        push edi
        imul edi, BSIZE
        add edi, esi
        movzx ecx, byte [board + edi]
        cmp ecx, BLACK
        jne .so_np2
        mov byte [board + edi], BLACK_K
.so_np2:
        pop edi
        pop esi
.so_np:
        ret
.so_ret:
        ret

.try_cap_fwd:
        ; Try dr=+2, dc=±2 captures for black
        mov eax, [.srow]
        add eax, 2
        cmp eax, BSIZE
        jge .tcf_ret
        mov ebx, [.scol]
        dec ebx
        dec ebx
        call .cap_one
        mov ebx, [.scol]
        add ebx, 2
        call .cap_one
.tcf_ret:
        ret

.cap_one:
        ; EAX=dst_row, EBX=dst_col
        cmp ebx, 0
        jl .co_ret
        cmp ebx, BSIZE
        jge .co_ret
        ; Check dst empty
        push eax
        push ebx
        imul eax, BSIZE
        add eax, ebx
        movzx ecx, byte [board + eax]
        pop ebx
        pop eax
        test ecx, ecx
        jnz .co_ret
        ; Check mid has red
        mov ecx, [.srow]
        add ecx, eax
        sar ecx, 1
        mov edx, [.scol]
        add edx, ebx
        sar edx, 1
        push ecx
        push edx
        imul ecx, BSIZE
        add ecx, edx
        movzx ecx, byte [board + ecx]
        pop edx
        pop ecx
        cmp ecx, RED
        je .co_ok
        cmp ecx, RED_K
        jne .co_ret
.co_ok:
        ; Capture: remove mid, move piece
        push ecx
        push edx
        imul ecx, BSIZE
        add ecx, edx
        mov byte [board + ecx], EMPTY
        pop edx
        pop ecx
        ; Move
        mov ecx, [.srow]
        mov edx, [.scol]
        push ecx
        push edx
        imul ecx, BSIZE
        add ecx, edx
        movzx ecx, byte [board + ecx]
        mov [.piece], ecx
        pop edx
        pop ecx
        imul ecx, BSIZE
        add ecx, edx
        mov byte [board + ecx], EMPTY
        push eax
        push ebx
        imul eax, BSIZE
        add eax, ebx
        mov ecx, [.piece]
        mov [board + eax], cl
        pop ebx
        pop eax
.co_ret:
        ret

.srow:   dd 0
.scol:   dd 0
.piece:  dd 0

;--------------------------------------
check_game_over:
        ; If no red or no black pieces remain → game over
        xor ecx, ecx
        xor edi, edi    ; red count
        xor esi, esi    ; black count
.cgo_loop:
        cmp ecx, BSIZE*BSIZE
        jge .cgo_check
        movzx eax, byte [board + ecx]
        cmp eax, RED
        je .cgo_r
        cmp eax, RED_K
        je .cgo_r
        cmp eax, BLACK
        je .cgo_b
        cmp eax, BLACK_K
        je .cgo_b
        inc ecx
        jmp .cgo_loop
.cgo_r:
        inc edi
        inc ecx
        jmp .cgo_loop
.cgo_b:
        inc esi
        inc ecx
        jmp .cgo_loop
.cgo_check:
        test edi, edi
        jz .cgo_over
        test esi, esi
        jz .cgo_over
        ret
.cgo_over:
        mov dword [game_over], 1
        mov [.red_cnt], edi
        mov [.blk_cnt], esi
        ; Fire SFX + persist on first detection
        cmp byte [result_played], 0
        jne .cgo_done
        mov byte [result_played], 1
        ; Player (RED) wins iff black count = 0 (esi==0)
        test esi, esi
        jnz .cgo_lose
        ; Win: bump persistent wins, save, win SFX
        pushad
        mov eax, [total_wins]
        inc eax
        mov [total_wins], eax
        mov ebx, [total_wins]
        mov esi, hs_name_ck
        call hs_save
        call audio_sfx_win
        popad
        ret
.cgo_lose:
        call audio_sfx_lose
.cgo_done:
        ret
.red_cnt: dd 0
.blk_cnt: dd 0

;--------------------------------------
draw_all:
        pushad
        mov edx, COL_BG
        call vbe_clear_screen

        mov dword [.ri], 0
.da_row:
        cmp dword [.ri], BSIZE
        jge .da_done
        mov dword [.ci], 0
.da_col:
        cmp dword [.ci], BSIZE
        jge .da_col_done

        mov eax, [.ci]
        imul eax, CELL_SZ + CELL_GAP
        add eax, GRID_X
        mov [.cx], eax
        mov eax, [.ri]
        imul eax, CELL_SZ + CELL_GAP
        add eax, GRID_Y
        mov [.cy], eax

        ; Square colour (dark on odd sum)
        mov eax, [.ri]
        add eax, [.ci]
        test eax, 1
        jnz .da_dark
        mov edi, COL_LIGHT
        jmp .da_sq
.da_dark:
        mov edi, COL_DARK
.da_sq:
        mov ebx, [.cx]
        mov ecx, [.cy]
        mov edx, CELL_SZ
        mov esi, CELL_SZ
        call vbe_fill_rect

        ; Highlight selected piece
        cmp dword [state], STATE_MOVE
        jne .da_piece
        mov eax, [.ri]
        cmp eax, [sel_row]
        jne .da_piece
        mov eax, [.ci]
        cmp eax, [sel_col]
        jne .da_piece
        mov ebx, [.cx]
        mov ecx, [.cy]
        mov edx, CELL_SZ
        mov esi, COL_SEL
        call vbe_draw_hline
        mov ecx, [.cy]
        call vbe_draw_vline
        mov ecx, [.cy]
        add ecx, CELL_SZ - 1
        call vbe_draw_hline
        mov ebx, [.cx]
        add ebx, CELL_SZ - 1
        mov ecx, [.cy]
        call vbe_draw_vline

.da_piece:
        ; Get piece
        mov eax, [.ri]
        imul eax, BSIZE
        add eax, [.ci]
        movzx eax, byte [board + eax]
        test eax, eax
        jz .da_cursor

        ; Disc
        mov ebx, [.cx]
        add ebx, CELL_SZ/2
        mov ecx, [.cy]
        add ecx, CELL_SZ/2
        mov edx, DISC_R

        cmp eax, RED
        je .da_red
        cmp eax, RED_K
        je .da_redk
        cmp eax, BLACK
        je .da_blk
        ; BLACK_K
        mov esi, COL_BLK_P
        call vbe_fill_circle
        ; Crown ring
        mov edx, DISC_R - 10
        mov esi, COL_BLK_K2
        call vbe_fill_circle
        jmp .da_cursor
.da_red:
        mov esi, COL_RED_P
        call vbe_fill_circle
        jmp .da_cursor
.da_redk:
        mov esi, COL_RED_P
        call vbe_fill_circle
        mov edx, DISC_R - 10
        mov esi, COL_RED_K2
        call vbe_fill_circle
        jmp .da_cursor
.da_blk:
        mov esi, COL_BLK_P
        call vbe_fill_circle

.da_cursor:
        ; Cursor highlight
        mov eax, [.ri]
        cmp eax, [cur_row]
        jne .da_no_cur
        mov eax, [.ci]
        cmp eax, [cur_col]
        jne .da_no_cur
        mov ebx, [.cx]
        mov ecx, [.cy]
        mov edx, CELL_SZ
        mov esi, COL_CURSOR
        call vbe_draw_hline
        mov ecx, [.cy]
        call vbe_draw_vline
        mov ecx, [.cy]
        add ecx, CELL_SZ - 1
        call vbe_draw_hline
        mov ebx, [.cx]
        add ebx, CELL_SZ - 1
        mov ecx, [.cy]
        call vbe_draw_vline
.da_no_cur:

        inc dword [.ci]
        jmp .da_col
.da_col_done:
        inc dword [.ri]
        jmp .da_row

.da_done:
        ; Status panel
        mov ebx, GRID_X + BSIZE*(CELL_SZ+CELL_GAP) + 30
        mov ecx, GRID_Y + 20

        cmp dword [game_over], 1
        jne .da_hint

        ; Count remaining
        xor edi, edi
        xor esi, esi
        xor ecx, ecx
.da_cnt:
        cmp ecx, BSIZE*BSIZE
        jge .da_cnt_done
        movzx eax, byte [board + ecx]
        cmp eax, RED
        je .da_cr
        cmp eax, RED_K
        je .da_cr
        cmp eax, BLACK
        je .da_cb
        cmp eax, BLACK_K
        je .da_cb
        inc ecx
        jmp .da_cnt
.da_cr: inc edi
        inc ecx
        jmp .da_cnt
.da_cb: inc esi
        inc ecx
        jmp .da_cnt
.da_cnt_done:

        mov ebx, GRID_X + BSIZE*(CELL_SZ+CELL_GAP) + 30
        mov ecx, GRID_Y + 20
        cmp edi, 0
        je .da_ai_win
        mov edx, msg_pwin
        mov esi, COL_GREEN
        mov eax, 2
        call vbe_draw_str
        jmp .da_restart
.da_ai_win:
        mov edx, msg_awin
        mov esi, COL_RED_P
        mov eax, 2
        call vbe_draw_str
.da_restart:
        add ecx, 35
        mov edx, msg_restart
        mov esi, COL_GRAY
        mov eax, 1
        call vbe_draw_str
        jmp .da_end

.da_hint:
        cmp dword [state], STATE_SELECT
        je .da_hint_sel
        mov edx, msg_move_hint
        jmp .da_sh
.da_hint_sel:
        mov edx, msg_sel_hint
.da_sh:
        mov ebx, GRID_X + BSIZE*(CELL_SZ+CELL_GAP) + 30
        mov ecx, GRID_Y + 20
        mov esi, COL_GRAY
        mov eax, 1
        call vbe_draw_str

.da_end:
        VBE_GAME_PRESENT
        popad
        ret

.ri: dd 0
.ci: dd 0
.cx: dd 0
.cy: dd 0

;=== Data ===
msg_sel_hint:  db "ARROWS=MOVE  ENTER=SELECT  Q=QUIT", 0
msg_move_hint: db "ARROWS=DEST  ENTER=MOVE  BKSP=CANCEL", 0
msg_pwin:      db "YOU WIN!", 0
msg_awin:      db "AI WINS!", 0
msg_restart:   db "ANY KEY = NEW GAME", 0

board:      times BSIZE*BSIZE db 0
cur_row:    dd 0
cur_col:    dd 0
sel_row:    dd -1
sel_col:    dd -1
state:      dd 0
game_over:  dd 0
hs_name_ck:    db "checkers", 0
hs_loaded:     db 0
result_played: db 0
total_wins:    dd 0
