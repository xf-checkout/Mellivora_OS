; battleship.asm - Classic Battleship game (player vs AI)
; VBE 1024x768x32bpp. 10x10 grids. Arrow keys + Enter to fire. Q to quit.
%include "syscalls.inc"
%include "lib/vbe_game.inc"
%include "lib/font.inc"
%include "lib/audio.inc"
%include "lib/highscore.inc"

GRID_SIZE       equ 10
CELL_SZ         equ 44
CELL_GAP        equ 2
; Player grid top-left
PG_X            equ 40
PG_Y            equ 120
; AI grid top-left
AG_X            equ 560
AG_Y            equ 120

; Cell values
WATER           equ 0
SHIP            equ 1
HIT             equ 2
MISS            equ 3

COL_BG          equ 0x00060C14
COL_WATER       equ 0x00003355
COL_SHIP        equ 0x00667788
COL_HIT         equ 0x00EE3333
COL_MISS        equ 0x00AAAAAA
COL_CURSOR      equ 0x00FFEE44
COL_GRID        equ 0x00334455
COL_WHITE       equ 0x00FFFFFF
COL_YELLOW      equ 0x00FFE040
COL_GREEN       equ 0x0033EE55
COL_GRAY        equ 0x00888888

; Ships: (length, count)
NUM_SHIPS       equ 5

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
        je .restart_check

        cmp al, KEY_UP
        je .cur_up
        cmp al, KEY_DOWN
        je .cur_down
        cmp al, KEY_LEFT
        je .cur_left
        cmp al, KEY_RIGHT
        je .cur_right
        cmp al, 0x0D
        je .fire
        jmp .no_key

.cur_up:
        cmp dword [cur_row], 0
        je .no_key
        dec dword [cur_row]
        jmp .redraw
.cur_down:
        cmp dword [cur_row], GRID_SIZE-1
        je .no_key
        inc dword [cur_row]
        jmp .redraw
.cur_left:
        cmp dword [cur_col], 0
        je .no_key
        dec dword [cur_col]
        jmp .redraw
.cur_right:
        cmp dword [cur_col], GRID_SIZE-1
        je .no_key
        inc dword [cur_col]
        jmp .redraw

.fire:
        ; Check not already shot
        mov eax, [cur_row]
        imul eax, GRID_SIZE
        add eax, [cur_col]
        movzx ecx, byte [ai_grid + eax]
        cmp ecx, HIT
        je .no_key
        cmp ecx, MISS
        je .no_key
        ; Fire
        call player_fire
        call check_ai_dead
        test eax, eax
        jnz .p_wins
        ; AI fires back
        call ai_fire
        call check_player_dead
        test eax, eax
        jnz .ai_wins
        jmp .redraw

.p_wins:
        mov dword [game_over], 1
        mov dword [player_won], 1
        ; Bump persistent wins, save, win SFX
        pushad
        mov eax, [total_wins]
        inc eax
        mov [total_wins], eax
        mov ebx, [total_wins]
        mov esi, hs_name_bs
        call hs_save
        call audio_sfx_win
        popad
        jmp .redraw
.ai_wins:
        mov dword [game_over], 1
        mov dword [player_won], 0
        call audio_sfx_lose
        jmp .redraw

.restart_check:
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
        ; Clear grids
        xor ecx, ecx
.ng_clear:
        cmp ecx, GRID_SIZE * GRID_SIZE
        jge .ng_clear_done
        mov byte [player_grid + ecx], WATER
        mov byte [ai_grid + ecx], WATER
        inc ecx
        jmp .ng_clear
.ng_clear_done:
        mov dword [cur_row], 0
        mov dword [cur_col], 0
        mov dword [game_over], 0
        mov dword [player_won], 0
        mov dword [ai_last_hit], -1
        ; First-call: load persistent wins from /scores/battleship
        cmp byte [hs_loaded], 0
        jne .ng_loaded
        mov byte [hs_loaded], 1
        pushad
        mov esi, hs_name_bs
        call hs_load
        mov [total_wins], eax
        popad
.ng_loaded:
        ; Place ships for both sides
        mov ebx, player_grid
        call place_ships
        mov ebx, ai_grid
        call place_ships
        ret

;--------------------------------------
; place_ships: EBX=grid base
; Ships: 5,4,3,3,2
;--------------------------------------
place_ships:
        mov dword [.lengths], 5
        mov dword [.lengths+4], 4
        mov dword [.lengths+8], 3
        mov dword [.lengths+12], 3
        mov dword [.lengths+16], 2
        xor ecx, ecx            ; ship index
.ps_ship:
        cmp ecx, NUM_SHIPS
        jge .ps_done
        push ecx
.ps_retry:
        ; Random position and direction
        call rand
        xor edx, edx
        push eax
        mov eax, edx
        pop eax
        xor edx, edx
        mov edi, GRID_SIZE
        div edi                 ; EAX=row, EDX unused
        xor edx, edx
        push eax
        call rand
        mov edi, GRID_SIZE
        xor edx, edx
        div edi                 ; EAX=col
        mov [.col], eax
        pop eax
        mov [.row], eax
        call rand
        and eax, 1
        mov [.horiz], eax

        ; Check bounds
        pop ecx
        push ecx
        mov edi, [.lengths + ecx*4]
        mov eax, [.row]
        mov edx, [.col]
        cmp dword [.horiz], 1
        je .ps_h
        ; vertical: row+len <= GRID_SIZE
        add eax, edi
        cmp eax, GRID_SIZE
        jg .ps_retry
        jmp .ps_fit
.ps_h:
        add edx, edi
        cmp edx, GRID_SIZE
        jg .ps_retry

.ps_fit:
        ; Check no collision
        xor esi, esi
.ps_check:
        cmp esi, edi
        jge .ps_place
        mov eax, [.row]
        mov edx, [.col]
        cmp dword [.horiz], 1
        je .ps_ch
        add eax, esi
        jmp .ps_ci
.ps_ch:
        add edx, esi
.ps_ci:
        imul eax, GRID_SIZE
        add eax, edx
        movzx eax, byte [ebx + eax]
        test eax, eax
        jnz .ps_retry
        inc esi
        jmp .ps_check

.ps_place:
        xor esi, esi
.ps_p2:
        cmp esi, edi
        jge .ps_next
        mov eax, [.row]
        mov edx, [.col]
        cmp dword [.horiz], 1
        je .ps_ph
        add eax, esi
        jmp .ps_pi
.ps_ph:
        add edx, esi
.ps_pi:
        imul eax, GRID_SIZE
        add eax, edx
        mov byte [ebx + eax], SHIP
        inc esi
        jmp .ps_p2

.ps_next:
        pop ecx
        inc ecx
        jmp .ps_ship

.ps_done:
        ret

.row:     dd 0
.col:     dd 0
.horiz:   dd 0
.lengths: times NUM_SHIPS dd 0

;--------------------------------------
player_fire:
        mov eax, [cur_row]
        imul eax, GRID_SIZE
        add eax, [cur_col]
        movzx ecx, byte [ai_grid + eax]
        cmp ecx, SHIP
        je .pf_hit
        mov byte [ai_grid + eax], MISS
        ret
.pf_hit:
        mov byte [ai_grid + eax], HIT
        ret

;--------------------------------------
; Simple AI: random shots, with hit-follow mode
;--------------------------------------
ai_fire:
.af_try:
        call rand
        xor edx, edx
        mov ebx, GRID_SIZE * GRID_SIZE
        div ebx
        movzx ecx, byte [player_grid + edx]
        cmp ecx, HIT
        je .af_try
        cmp ecx, MISS
        je .af_try
        cmp ecx, SHIP
        je .af_hit
        mov byte [player_grid + edx], MISS
        ret
.af_hit:
        mov byte [player_grid + edx], HIT
        ret

;--------------------------------------
check_ai_dead:
        xor ecx, ecx
        xor eax, eax
.cad_loop:
        cmp ecx, GRID_SIZE * GRID_SIZE
        jge .cad_done
        movzx edx, byte [ai_grid + ecx]
        cmp edx, SHIP
        je .cad_alive
        inc ecx
        jmp .cad_loop
.cad_alive:
        xor eax, eax
        ret
.cad_done:
        mov eax, 1
        ret

check_player_dead:
        xor ecx, ecx
.cpd_loop:
        cmp ecx, GRID_SIZE * GRID_SIZE
        jge .cpd_done
        movzx edx, byte [player_grid + ecx]
        cmp edx, SHIP
        je .cpd_alive
        inc ecx
        jmp .cpd_loop
.cpd_alive:
        xor eax, eax
        ret
.cpd_done:
        mov eax, 1
        ret

;--------------------------------------
rand:
        mov eax, [rand_state]
        imul eax, 1664525
        add eax, 1013904223
        mov [rand_state], eax
        ret

;--------------------------------------
; draw_grid: EBX=grid_base, ECX=top_left_x, EDX=top_left_y
;            ESI=show_ships(1=show, 0=hide)
;--------------------------------------
draw_grid:
        pushad
        mov [.gbase], ebx
        mov [.gx], ecx
        mov [.gy], edx
        mov [.show_ships], esi

        mov dword [.row], 0
.dg_row:
        cmp dword [.row], GRID_SIZE
        jge .dg_done
        mov dword [.col], 0
.dg_col:
        cmp dword [.col], GRID_SIZE
        jge .dg_col_done

        mov eax, [.col]
        imul eax, CELL_SZ + CELL_GAP
        add eax, [.gx]
        mov [.cx], eax
        mov eax, [.row]
        imul eax, CELL_SZ + CELL_GAP
        add eax, [.gy]
        mov [.cy], eax

        ; Get cell value
        mov eax, [.row]
        imul eax, GRID_SIZE
        add eax, [.col]
        mov ebx, [.gbase]
        movzx eax, byte [ebx + eax]

        ; Color
        cmp eax, HIT
        je .dg_hit
        cmp eax, MISS
        je .dg_miss
        cmp eax, SHIP
        je .dg_ship
        ; Water
        mov edi, COL_WATER
        jmp .dg_draw
.dg_hit:
        mov edi, COL_HIT
        jmp .dg_draw
.dg_miss:
        mov edi, COL_MISS
        jmp .dg_draw
.dg_ship:
        cmp dword [.show_ships], 1
        je .dg_draw_ship
        mov edi, COL_WATER
        jmp .dg_draw
.dg_draw_ship:
        mov edi, COL_SHIP

.dg_draw:
        mov ebx, [.cx]
        mov ecx, [.cy]
        mov edx, CELL_SZ
        mov esi, CELL_SZ
        call vbe_fill_rect

        inc dword [.col]
        jmp .dg_col
.dg_col_done:
        inc dword [.row]
        jmp .dg_row
.dg_done:
        popad
        ret

.gbase: dd 0
.gx:    dd 0
.gy:    dd 0
.show_ships: dd 0
.row:   dd 0
.col:   dd 0
.cx:    dd 0
.cy:    dd 0

;--------------------------------------
draw_all:
        pushad
        mov edx, COL_BG
        call vbe_clear_screen

        ; Titles
        mov ebx, 110
        mov ecx, 70
        mov edx, msg_player
        mov esi, COL_WHITE
        mov eax, 2
        call vbe_draw_str

        mov ebx, 640
        mov ecx, 70
        mov edx, msg_ai
        mov esi, COL_WHITE
        mov eax, 2
        call vbe_draw_str

        ; Player grid (show ships)
        mov ebx, player_grid
        mov ecx, PG_X
        mov edx, PG_Y
        mov esi, 1
        call draw_grid

        ; AI grid (hide ships)
        mov ebx, ai_grid
        mov ecx, AG_X
        mov edx, AG_Y
        mov esi, 0
        call draw_grid

        ; Draw cursor on AI grid
        cmp dword [game_over], 1
        je .da_no_cursor
        mov eax, [cur_col]
        imul eax, CELL_SZ + CELL_GAP
        add eax, AG_X
        mov ebx, eax
        mov eax, [cur_row]
        imul eax, CELL_SZ + CELL_GAP
        add eax, AG_Y
        mov ecx, eax
        mov edx, CELL_SZ
        mov esi, COL_CURSOR
        call vbe_draw_hline
        mov ecx, eax
        call vbe_draw_vline
        mov ecx, eax
        add ecx, CELL_SZ
        call vbe_draw_hline
        mov ebx, [cur_col]
        imul ebx, CELL_SZ + CELL_GAP
        add ebx, AG_X + CELL_SZ
        mov eax, [cur_row]
        imul eax, CELL_SZ + CELL_GAP
        add eax, AG_Y
        mov ecx, eax
        mov edx, CELL_SZ
        call vbe_draw_vline

.da_no_cursor:
        ; Status
        mov ebx, 270
        mov ecx, PG_Y + GRID_SIZE*(CELL_SZ+CELL_GAP) + 20
        cmp dword [game_over], 0
        je .da_hint
        cmp dword [player_won], 1
        je .da_win
        mov edx, msg_lose
        mov esi, 0x00FF4444
        mov eax, 2
        call vbe_draw_str
        jmp .da_restart
.da_win:
        mov edx, msg_win
        mov esi, COL_GREEN
        mov eax, 2
        call vbe_draw_str
.da_restart:
        mov ebx, 300
        mov ecx, PG_Y + GRID_SIZE*(CELL_SZ+CELL_GAP) + 60
        mov edx, msg_restart
        mov esi, COL_GRAY
        mov eax, 1
        call vbe_draw_str
        jmp .da_end

.da_hint:
        mov edx, msg_hint
        mov esi, COL_GRAY
        mov eax, 1
        call vbe_draw_str

.da_end:
        VBE_GAME_PRESENT
        popad
        ret

;=== Data ===
msg_player:  db "YOUR FLEET", 0
msg_ai:      db "ENEMY WATERS", 0
msg_hint:    db "ARROWS=AIM  ENTER=FIRE  Q=QUIT", 0
msg_win:     db "VICTORY! ALL ENEMY SHIPS SUNK!", 0
msg_lose:    db "DEFEAT! YOUR FLEET IS GONE!", 0
msg_restart: db "ANY KEY TO PLAY AGAIN", 0

player_grid:    times GRID_SIZE*GRID_SIZE db 0
ai_grid:        times GRID_SIZE*GRID_SIZE db 0
cur_row:        dd 0
cur_col:        dd 0
game_over:      dd 0
player_won:     dd 0
ai_last_hit:    dd -1
rand_state:     dd 0xBEEFCAFE
hs_name_bs:     db "battleship", 0
hs_loaded:      db 0
total_wins:     dd 0
