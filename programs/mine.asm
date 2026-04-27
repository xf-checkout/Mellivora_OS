; mine.asm - Minesweeper
; VBE 1024x768x32bpp. Arrows/WASD=move, Space/Enter=reveal, F=flag, R=restart, ESC=quit.
%include "syscalls.inc"
%include "lib/vbe_game.inc"
%include "lib/font.inc"
%include "lib/audio.inc"
%include "lib/highscore.inc"

MAP_W           equ 40
MAP_H           equ 20
MAP_SIZE        equ MAP_W * MAP_H
CELL_MINE       equ 0xFF

CELL_SZ         equ 22
CELL_CX         equ 8           ; (22-5)/2 x-offset for scale=1 char
CELL_CY         equ 7           ; (22-7)/2 y-offset for scale=1 char
GRID_X          equ 72          ; (1024 - 40*22) / 2
GRID_Y          equ 60

COL_BG          equ 0x00101010
COL_HIDDEN      equ 0x00336644
COL_REVEALED    equ 0x001A1A1A
COL_MINE_BG     equ 0x00880000
COL_CURSOR      equ 0x00CCCC44
COL_FLAG_FG     equ 0x00FF4444
COL_WIN         equ 0x0033CC44
COL_LOSE        equ 0x00CC2222
COL_WHITE       equ 0x00FFFFFF
COL_DIM         equ 0x00888888

start:
        VBE_GAME_INIT
        mov eax, SYS_GETTIME
        int 0x80
        mov [rand_seed], eax
        call new_game

;--------------------------------------
game_loop:
        VBE_GAME_POLL_KEY
        cmp eax, -1
        je .gl_nk
        cmp al, KEY_ESC
        je .gl_quit
        cmp al, 'q'
        je .gl_quit
        cmp al, 'Q'
        je .gl_quit

        cmp byte [game_active], 0
        jne .gl_active
        cmp al, 'r'
        je .gl_restart
        cmp al, 'R'
        je .gl_restart
        jmp .gl_nk

.gl_restart:
        mov eax, SYS_GETTIME
        int 0x80
        mov [rand_seed], eax
        call new_game
        jmp .gl_nk

.gl_active:
        cmp al, KEY_UP
        je .gl_up
        cmp al, 'w'
        je .gl_up
        cmp al, KEY_DOWN
        je .gl_down
        cmp al, 's'
        je .gl_down
        cmp al, KEY_LEFT
        je .gl_left
        cmp al, 'a'
        je .gl_left
        cmp al, KEY_RIGHT
        je .gl_right
        cmp al, 'd'
        je .gl_right
        cmp al, ' '
        je .gl_reveal
        cmp al, 0x0D
        je .gl_reveal
        cmp al, 'f'
        je .gl_flag
        cmp al, 'F'
        je .gl_flag
        jmp .gl_nk

.gl_up:
        cmp dword [cursor_y], 0
        je .gl_nk
        dec dword [cursor_y]
        call draw_all
        jmp .gl_nk
.gl_down:
        cmp dword [cursor_y], MAP_H-1
        jge .gl_nk
        inc dword [cursor_y]
        call draw_all
        jmp .gl_nk
.gl_left:
        cmp dword [cursor_x], 0
        je .gl_nk
        dec dword [cursor_x]
        call draw_all
        jmp .gl_nk
.gl_right:
        cmp dword [cursor_x], MAP_W-1
        jge .gl_nk
        inc dword [cursor_x]
        call draw_all
        jmp .gl_nk

.gl_flag:
        call cursor_to_index
        cmp byte [map_visible + eax], 1
        je .gl_nk
        xor byte [map_visible + eax], 2
        call draw_all
        jmp .gl_nk

.gl_reveal:
        call cursor_to_index
        cmp byte [map_visible + eax], 0
        jne .gl_nk
        cmp byte [map_unveiled + eax], CELL_MINE
        je .gl_mine
        mov eax, [cursor_x]
        mov ebx, [cursor_y]
        call flood_reveal
        mov eax, [cells_revealed]
        cmp eax, [safe_cells]
        jge .gl_win
        call draw_all
        jmp .gl_nk
.gl_mine:
        call reveal_all_mines
        mov byte [game_active], 0
        call audio_sfx_lose
        call draw_all
        jmp .gl_nk
.gl_win:
        mov byte [game_active], 0
        ; Bump persistent wins, save, win SFX
        mov eax, [total_wins]
        inc eax
        mov [total_wins], eax
        mov ebx, [total_wins]
        mov esi, hs_name_mn
        call hs_save
        call audio_sfx_win
        call draw_all
        jmp .gl_nk

.gl_nk:
        mov eax, SYS_SLEEP
        mov ebx, 1
        int 0x80
        jmp game_loop

.gl_quit:
        mov eax, SYS_FRAMEBUF
        mov ebx, 2
        int 0x80
        xor eax, eax
        int 0x80

;--------------------------------------
new_game:
        mov dword [cursor_x], MAP_W / 2
        mov dword [cursor_y], MAP_H / 2
        mov dword [mines_total], 0
        mov byte  [game_active], 1
        mov dword [cells_revealed], 0
        ; First-call: load persistent wins from /scores/mine
        cmp byte [hs_loaded], 0
        jne .ng_post_load
        mov byte [hs_loaded], 1
        pushad
        mov esi, hs_name_mn
        call hs_load
        mov [total_wins], eax
        popad
.ng_post_load:

        ; Clear mine and unveiled maps
        mov edi, map_mines
        mov ecx, MAP_SIZE
        xor al, al
        rep stosb

        mov edi, map_unveiled
        mov ecx, MAP_SIZE
        xor al, al
        rep stosb

        mov edi, map_visible
        mov ecx, MAP_SIZE
        xor al, al
        rep stosb               ; 0 = hidden, 1 = revealed, 2 = flagged

        ; Populate mines (~12.5% chance per cell = 1/8)
        xor ecx, ecx
.populate:
        cmp ecx, MAP_SIZE
        jge .populate_done
        call rand
        test al, 0x07           ; if low 3 bits == 0 -> mine
        jnz .no_mine
        mov byte [map_mines + ecx], 1
        inc dword [mines_total]
.no_mine:
        inc ecx
        jmp .populate
.populate_done:

        ; Calculate numbers for each cell
        xor ecx, ecx           ; cell index
.number_loop:
        cmp ecx, MAP_SIZE
        jge .number_done

        ; If mine, store CELL_MINE
        cmp byte [map_mines + ecx], 1
        jne .count_neighbors
        mov byte [map_unveiled + ecx], CELL_MINE
        jmp .next_cell

.count_neighbors:
        ; Count mines around cell ECX
        xor edx, edx           ; neighbor mine count

        ; Get row/col
        mov eax, ecx
        xor ebx, ebx           ; remainder
        push ecx
        push edx
        mov ebx, MAP_W
        xor edx, edx
        div ebx                 ; eax=row, edx=col
        mov esi, eax            ; row
        mov edi, edx            ; col
        pop edx
        pop ecx

        ; Check all 8 neighbors
        ; Up (row-1)
        cmp esi, 0
        je .skip_up
        mov eax, ecx
        sub eax, MAP_W
        call check_mine
        add edx, eax
        ; Up-left
        cmp edi, 0
        je .skip_ul
        mov eax, ecx
        sub eax, MAP_W
        dec eax
        call check_mine
        add edx, eax
.skip_ul:
        ; Up-right
        lea eax, [edi + 1]
        cmp eax, MAP_W
        jge .skip_ur
        mov eax, ecx
        sub eax, MAP_W
        inc eax
        call check_mine
        add edx, eax
.skip_ur:
.skip_up:

        ; Down (row+1)
        lea eax, [esi + 1]
        cmp eax, MAP_H
        jge .skip_down
        mov eax, ecx
        add eax, MAP_W
        call check_mine
        add edx, eax
        ; Down-left
        cmp edi, 0
        je .skip_dl
        mov eax, ecx
        add eax, MAP_W
        dec eax
        call check_mine
        add edx, eax
.skip_dl:
        ; Down-right
        lea eax, [edi + 1]
        cmp eax, MAP_W
        jge .skip_dr
        mov eax, ecx
        add eax, MAP_W
        inc eax
        call check_mine
        add edx, eax
.skip_dr:
.skip_down:

        ; Left
        cmp edi, 0
        je .skip_left
        mov eax, ecx
        dec eax
        call check_mine
        add edx, eax
.skip_left:

        ; Right
        lea eax, [edi + 1]
        cmp eax, MAP_W
        jge .skip_right
        mov eax, ecx
        inc eax
        call check_mine
        add edx, eax
.skip_right:

        mov [map_unveiled + ecx], dl

.next_cell:
        inc ecx
        jmp .number_loop
.number_done:

        ; Calculate safe cells count
        mov eax, MAP_SIZE
        sub eax, [mines_total]
        mov [safe_cells], eax

        call draw_all
        ret

;=================================
check_mine:
        cmp eax, 0
        jl .no
        cmp eax, MAP_SIZE
        jge .no
        movzx eax, byte [map_mines + eax]
        ret
.no:
        xor eax, eax
        ret
cursor_to_index:
        mov eax, [cursor_y]
        imul eax, MAP_W
        add eax, [cursor_x]
        ret

;=== Flood reveal from (EAX=x, EBX=y) - iterative with explicit stack ===
; Uses flood_stack[] array to avoid deep recursion
; Each entry is 2 dwords: [x, y]
FLOOD_STACK_MAX equ MAP_SIZE   ; max entries

flood_reveal:
        pushad
        ; Initialize stack pointer
        mov dword [flood_sp], 0

        ; Push initial cell
        mov [flood_stack], eax           ; x
        mov [flood_stack + 4], ebx       ; y
        mov dword [flood_sp], 1

.flood_loop:
        ; Pop a cell from the stack
        cmp dword [flood_sp], 0
        je .flood_done
        dec dword [flood_sp]
        mov ecx, [flood_sp]
        mov eax, [flood_stack + ecx*8]       ; x
        mov ebx, [flood_stack + ecx*8 + 4]   ; y

        ; Bounds check
        cmp eax, 0
        jl .flood_loop
        cmp eax, MAP_W
        jge .flood_loop
        cmp ebx, 0
        jl .flood_loop
        cmp ebx, MAP_H
        jge .flood_loop

        ; Calculate index: idx = y * MAP_W + x
        push eax
        push ebx
        imul ebx, MAP_W
        add ebx, eax
        mov edx, ebx            ; EDX = index
        pop ebx
        pop eax

        ; Already revealed or flagged?
        cmp byte [map_visible + edx], 0
        jne .flood_loop

        ; Mark revealed
        mov byte [map_visible + edx], 1
        inc dword [cells_revealed]

        ; Is it a numbered cell? Don't expand further
        cmp byte [map_unveiled + edx], 0
        jne .flood_loop

        ; Empty cell: push all 8 neighbors
        ; Check stack space
        mov ecx, [flood_sp]
        add ecx, 8
        cmp ecx, FLOOD_STACK_MAX
        jg .flood_loop          ; Stack full, skip expansion

        ; Push neighbors (up, down, left, right, 4 diagonals)
        mov ecx, [flood_sp]

        ; Up (x, y-1)
        mov [flood_stack + ecx*8], eax
        mov esi, ebx
        dec esi
        mov [flood_stack + ecx*8 + 4], esi
        inc ecx

        ; Down (x, y+1)
        mov [flood_stack + ecx*8], eax
        mov esi, ebx
        inc esi
        mov [flood_stack + ecx*8 + 4], esi
        inc ecx

        ; Left (x-1, y)
        mov esi, eax
        dec esi
        mov [flood_stack + ecx*8], esi
        mov [flood_stack + ecx*8 + 4], ebx
        inc ecx

        ; Right (x+1, y)
        mov esi, eax
        inc esi
        mov [flood_stack + ecx*8], esi
        mov [flood_stack + ecx*8 + 4], ebx
        inc ecx

        ; Up-Left (x-1, y-1)
        mov esi, eax
        dec esi
        mov [flood_stack + ecx*8], esi
        mov esi, ebx
        dec esi
        mov [flood_stack + ecx*8 + 4], esi
        inc ecx

        ; Up-Right (x+1, y-1)
        mov esi, eax
        inc esi
        mov [flood_stack + ecx*8], esi
        mov esi, ebx
        dec esi
        mov [flood_stack + ecx*8 + 4], esi
        inc ecx

        ; Down-Left (x-1, y+1)
        mov esi, eax
        dec esi
        mov [flood_stack + ecx*8], esi
        mov esi, ebx
        inc esi
        mov [flood_stack + ecx*8 + 4], esi
        inc ecx

        ; Down-Right (x+1, y+1)
        mov esi, eax
        inc esi
        mov [flood_stack + ecx*8], esi
        mov esi, ebx
        inc esi
        mov [flood_stack + ecx*8 + 4], esi
        inc ecx

        mov [flood_sp], ecx
        jmp .flood_loop

.flood_done:
        popad
        ret

;=== Reveal all mines (game over) ===
reveal_all_mines:
        pushad
        xor ecx, ecx
.loop:
        cmp ecx, MAP_SIZE
        jge .done
        cmp byte [map_unveiled + ecx], CELL_MINE
        jne .skip
        mov byte [map_visible + ecx], 1
.skip:
        inc ecx
        jmp .loop
.done:
        popad
        ret

;--------------------------------------
draw_all:
        pushad
        mov edx, COL_BG
        call vbe_clear_screen

        ; Header: title + mine count
        mov ebx, 10
        mov ecx, 14
        mov edx, msg_title
        mov esi, COL_WHITE
        mov eax, 2
        call vbe_draw_str

        mov ebx, 700
        mov ecx, 14
        mov edx, msg_mines_lbl
        mov esi, COL_WHITE
        mov eax, 2
        call vbe_draw_str

        mov ebx, 830
        mov ecx, 14
        mov edx, [mines_total]
        mov esi, COL_WHITE
        mov eax, 2
        call vbe_draw_num

        ; Draw all cells
        mov dword [.ci], 0
.da_loop:
        cmp dword [.ci], MAP_SIZE
        jge .da_done

        mov eax, [.ci]
        xor edx, edx
        mov ebx, MAP_W
        div ebx             ; EAX=row, EDX=col
        mov [.cr], eax
        mov [.cc], edx

        ; Pixel position
        imul edx, CELL_SZ
        add edx, GRID_X
        mov [.px], edx
        mov eax, [.cr]
        imul eax, CELL_SZ
        add eax, GRID_Y
        mov [.py], eax

        ; Fill color
        mov ecx, [.ci]
        movzx ebx, byte [map_visible + ecx]
        cmp ebx, 1
        je .da_rev_check
        cmp ebx, 2
        je .da_flag
        ; Hidden
        mov edi, COL_HIDDEN
        jmp .da_fill
.da_flag:
        mov edi, COL_REVEALED
        jmp .da_fill
.da_rev_check:
        mov ecx, [.ci]
        cmp byte [map_unveiled + ecx], CELL_MINE
        jne .da_rev_normal
        mov edi, COL_MINE_BG
        jmp .da_fill
.da_rev_normal:
        mov edi, COL_REVEALED

.da_fill:
        mov ebx, [.px]
        mov ecx, [.py]
        mov edx, CELL_SZ
        mov esi, CELL_SZ
        call vbe_fill_rect

        ; Draw symbol
        mov ecx, [.ci]
        movzx ebx, byte [map_visible + ecx]
        cmp ebx, 2
        je .da_sym_flag
        cmp ebx, 1
        jne .da_next_cell
        ; Revealed: what's here?
        mov ecx, [.ci]
        movzx eax, byte [map_unveiled + ecx]
        test eax, eax
        je .da_next_cell        ; 0=empty, no char
        cmp eax, CELL_MINE
        je .da_sym_mine
        ; Number 1-8
        mov [.num_tmp], eax
        dec eax
        mov esi, [num_colors_vbe + eax*4]
        mov ebx, [.px]
        add ebx, CELL_CX
        mov ecx, [.py]
        add ecx, CELL_CY
        mov eax, [.num_tmp]
        add eax, '0'
        mov edx, eax
        mov eax, 1
        call vbe_draw_char
        jmp .da_next_cell

.da_sym_mine:
        mov ebx, [.px]
        add ebx, CELL_CX
        mov ecx, [.py]
        add ecx, CELL_CY
        mov edx, '*'
        mov esi, COL_WHITE
        mov eax, 1
        call vbe_draw_char
        jmp .da_next_cell

.da_sym_flag:
        mov ebx, [.px]
        add ebx, CELL_CX
        mov ecx, [.py]
        add ecx, CELL_CY
        mov edx, 'F'
        mov esi, COL_FLAG_FG
        mov eax, 1
        call vbe_draw_char

.da_next_cell:
        inc dword [.ci]
        jmp .da_loop

.da_done:
        ; Cursor border
        mov eax, [cursor_x]
        imul eax, CELL_SZ
        add eax, GRID_X
        mov [.cpx], eax
        mov eax, [cursor_y]
        imul eax, CELL_SZ
        add eax, GRID_Y
        mov [.cpy], eax

        mov ebx, [.cpx]
        mov ecx, [.cpy]
        mov edx, CELL_SZ
        mov esi, COL_CURSOR
        call vbe_draw_hline
        mov ecx, [.cpy]
        call vbe_draw_vline
        mov ecx, [.cpy]
        add ecx, CELL_SZ - 1
        call vbe_draw_hline
        mov ebx, [.cpx]
        add ebx, CELL_SZ - 1
        mov ecx, [.cpy]
        call vbe_draw_vline

        ; Status
        mov ecx, GRID_Y + MAP_H * CELL_SZ + 12
        cmp byte [game_active], 0
        jne .da_hint

        mov eax, [cells_revealed]
        cmp eax, [safe_cells]
        jge .da_win_msg
        ; Lose
        mov ebx, GRID_X + 60
        mov edx, msg_gameover
        mov esi, COL_LOSE
        mov eax, 2
        call vbe_draw_str
        jmp .da_restart_msg
.da_win_msg:
        mov ebx, GRID_X + 60
        mov edx, msg_win
        mov esi, COL_WIN
        mov eax, 2
        call vbe_draw_str
.da_restart_msg:
        add ecx, 35
        mov ebx, GRID_X
        mov edx, msg_restart
        mov esi, COL_DIM
        mov eax, 1
        call vbe_draw_str
        jmp .da_end

.da_hint:
        mov ebx, GRID_X
        mov edx, msg_hint
        mov esi, COL_DIM
        mov eax, 1
        call vbe_draw_str

.da_end:
        VBE_GAME_PRESENT
        popad
        ret

.ci:      dd 0
.cr:      dd 0
.cc:      dd 0
.px:      dd 0
.py:      dd 0
.num_tmp: dd 0
.cpx:     dd 0
.cpy:     dd 0


;=== Simple PRNG ===
rand:
        push ebx
        push ecx
        mov eax, [rand_seed]
        imul eax, 1103515245
        add eax, 12345
        mov [rand_seed], eax
        shr eax, 16
        and eax, 0x7FFF
        pop ecx
        pop ebx
        ret

;=== Data ===
num_colors_vbe:
        dd 0x004488FF   ; 1 blue
        dd 0x0033CC66   ; 2 green
        dd 0x00FF4444   ; 3 red
        dd 0x00224488   ; 4 dark blue
        dd 0x00AA3333   ; 5 maroon
        dd 0x0033BBCC   ; 6 teal
        dd 0x00BBBBBB   ; 7 light gray
        dd 0x00666666   ; 8 gray

msg_title:     db "MINESWEEPER", 0
msg_mines_lbl: db "MINES:", 0
msg_hint:      db "ARROWS=MOVE  SPACE=REVEAL  F=FLAG  R=RESTART  ESC=QUIT", 0
msg_gameover:  db "GAME OVER", 0
msg_win:       db "YOU WIN!", 0
msg_restart:   db "R=RESTART  ESC=QUIT", 0

;=== BSS ===
rand_seed:      dd 0
cursor_x:       dd 0
cursor_y:       dd 0
mines_total:    dd 0
safe_cells:     dd 0
cells_revealed: dd 0
game_active:    db 0
hs_name_mn:     db "mine", 0
hs_loaded:      db 0
total_wins:     dd 0
map_mines:      times MAP_SIZE db 0
map_unveiled:   times MAP_SIZE db 0
map_visible:    times MAP_SIZE db 0
flood_sp:       dd 0
flood_stack:    times FLOOD_STACK_MAX * 2 dd 0   ; Each entry = 2 dwords (x, y)
