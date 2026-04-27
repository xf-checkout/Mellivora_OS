; maze.asm - Random maze generator and solver
; VBE 1024x768x32bpp. Any key=new maze, ESC=quit.
%include "syscalls.inc"
%include "lib/vbe_game.inc"
%include "lib/font.inc"

MAZE_W  equ 39
MAZE_H  equ 21
MAZE_SZ equ MAZE_W * MAZE_H

WALL    equ '#'
PATH    equ ' '
VISITED equ '.'
SOLVE   equ '*'
START   equ 'S'
GOAL    equ 'E'

CELL_SZ equ 20
GRID_X  equ 122     ; (1024 - 39*20) / 2
GRID_Y  equ 80

COL_BG      equ 0x00080810
COL_WALL    equ 0x003060A0
COL_PATH    equ 0x000D0D18
COL_SOLVE   equ 0x0033FF66
COL_START   equ 0x00FF3333
COL_GOAL    equ 0x00FFCC00
COL_WHITE   equ 0x00FFFFFF
COL_DIM     equ 0x00888888

start:
        VBE_GAME_INIT
        call new_maze
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
        ; Any key = new maze
        call new_maze
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
new_maze:
        pushad
        mov eax, SYS_GETTIME
        int 0x80
        mov [prng_state], eax
        call generate_maze
        call solve_maze
        popad
        ret

;--------------------------------------
; VBE draw
;--------------------------------------
draw_all:
        pushad
        mov edx, COL_BG
        call vbe_clear_screen

        ; Title centered: "MAZE" 4 chars*15=60px, x=(1024-60)/2=482
        mov ebx, 482
        mov ecx, 20
        mov edx, msg_title
        mov esi, COL_WHITE
        mov eax, 3
        call vbe_draw_str

        mov dword [.row], 0
.da_row:
        cmp dword [.row], MAZE_H
        jge .da_done
        mov dword [.col], 0
.da_col:
        cmp dword [.col], MAZE_W
        jge .da_col_done

        ; Pixel position
        mov eax, [.col]
        imul eax, CELL_SZ
        add eax, GRID_X
        mov [.px], eax
        mov eax, [.row]
        imul eax, CELL_SZ
        add eax, GRID_Y
        mov [.py], eax

        ; Cell type
        mov eax, [.row]
        imul eax, MAZE_W
        add eax, [.col]
        movzx ecx, byte [maze + eax]

        cmp ecx, WALL
        je .da_wall
        cmp ecx, SOLVE
        je .da_solve
        cmp ecx, START
        je .da_start
        cmp ecx, GOAL
        je .da_goal
        mov edi, COL_PATH
        jmp .da_fill
.da_wall:
        mov edi, COL_WALL
        jmp .da_fill
.da_solve:
        mov edi, COL_SOLVE
        jmp .da_fill
.da_start:
        mov edi, COL_START
        jmp .da_fill
.da_goal:
        mov edi, COL_GOAL

.da_fill:
        mov ebx, [.px]
        mov ecx, [.py]
        mov edx, CELL_SZ
        mov esi, CELL_SZ
        call vbe_fill_rect

        inc dword [.col]
        jmp .da_col
.da_col_done:
        inc dword [.row]
        jmp .da_row

.da_done:
        ; Hint
        mov ebx, GRID_X
        mov ecx, GRID_Y + MAZE_H * CELL_SZ + 12
        mov edx, msg_hint
        mov esi, COL_DIM
        mov eax, 1
        call vbe_draw_str

        VBE_GAME_PRESENT
        popad
        ret

.row: dd 0
.col: dd 0
.px:  dd 0
.py:  dd 0

;---------------------------------------
; Generate maze using iterative backtracking
; Uses stack-based DFS with PRNG for direction shuffling
;---------------------------------------
generate_maze:
        pushad
        ; Fill with walls
        mov edi, maze
        mov ecx, MAZE_SZ
        mov al, WALL
        rep stosb

        ; Start carving at (1,1)
        mov dword [stack_ptr], 0
        mov eax, 1*MAZE_W + 1
        mov byte [maze + eax], PATH
        push eax               ; push starting cell

        ; Push to DFS stack
        mov edi, [stack_ptr]
        mov [dfs_stack + edi*4], eax
        inc dword [stack_ptr]

.gen_loop:
        mov ecx, [stack_ptr]
        cmp ecx, 0
        je .gen_done

        ; Peek current cell
        dec ecx
        mov eax, [dfs_stack + ecx*4]
        ; Convert to row/col
        xor edx, edx
        mov ebx, MAZE_W
        div ebx
        ; eax = row, edx = col
        mov [.cur_row], eax
        mov [.cur_col], edx

        ; Find unvisited neighbors (2 cells away)
        mov dword [.n_count], 0

        ; Up
        mov eax, [.cur_row]
        sub eax, 2
        cmp eax, 0
        jl .gen_no_up
        mov ebx, eax
        imul ebx, MAZE_W
        add ebx, [.cur_col]
        cmp byte [maze + ebx], WALL
        jne .gen_no_up
        mov ecx, [.n_count]
        mov [.neighbors + ecx*4], ebx
        mov dword [.n_dir + ecx*4], 0  ; direction 0=up
        inc dword [.n_count]
.gen_no_up:
        ; Down
        mov eax, [.cur_row]
        add eax, 2
        cmp eax, MAZE_H
        jge .gen_no_down
        mov ebx, eax
        imul ebx, MAZE_W
        add ebx, [.cur_col]
        cmp byte [maze + ebx], WALL
        jne .gen_no_down
        mov ecx, [.n_count]
        mov [.neighbors + ecx*4], ebx
        mov dword [.n_dir + ecx*4], 1
        inc dword [.n_count]
.gen_no_down:
        ; Left
        mov eax, [.cur_col]
        sub eax, 2
        cmp eax, 0
        jl .gen_no_left
        mov ebx, [.cur_row]
        imul ebx, MAZE_W
        add ebx, eax
        cmp byte [maze + ebx], WALL
        jne .gen_no_left
        mov ecx, [.n_count]
        mov [.neighbors + ecx*4], ebx
        mov dword [.n_dir + ecx*4], 2
        inc dword [.n_count]
.gen_no_left:
        ; Right
        mov eax, [.cur_col]
        add eax, 2
        cmp eax, MAZE_W
        jge .gen_no_right
        mov ebx, [.cur_row]
        imul ebx, MAZE_W
        add ebx, eax
        cmp byte [maze + ebx], WALL
        jne .gen_no_right
        mov ecx, [.n_count]
        mov [.neighbors + ecx*4], ebx
        mov dword [.n_dir + ecx*4], 3
        inc dword [.n_count]
.gen_no_right:

        cmp dword [.n_count], 0
        je .gen_backtrack

        ; Pick random neighbor
        call prng
        xor edx, edx
        div dword [.n_count]
        ; edx = random index
        mov eax, [.neighbors + edx*4]
        mov ecx, [.n_dir + edx*4]

        ; Carve the wall between current and chosen
        mov byte [maze + eax], PATH
        ; Find wall cell (midpoint)
        push eax
        mov ebx, [.cur_row]
        imul ebx, MAZE_W
        add ebx, [.cur_col]
        add ebx, eax
        shr ebx, 1              ; midpoint index
        mov byte [maze + ebx], PATH
        pop eax

        ; Push chosen onto stack
        mov ecx, [stack_ptr]
        mov [dfs_stack + ecx*4], eax
        inc dword [stack_ptr]
        jmp .gen_loop

.gen_backtrack:
        dec dword [stack_ptr]
        jmp .gen_loop

.gen_done:
        ; Set start and end
        mov byte [maze + 1*MAZE_W + 1], START
        mov eax, (MAZE_H-2)*MAZE_W + (MAZE_W-2)
        mov byte [maze + eax], GOAL
        pop eax
        popad
        ret

.cur_row:   dd 0
.cur_col:   dd 0
.n_count:   dd 0
.neighbors: dd 0, 0, 0, 0
.n_dir:     dd 0, 0, 0, 0

;---------------------------------------
; Solve maze using BFS
;---------------------------------------
solve_maze:
        pushad
        ; Clear visited
        mov edi, visited
        mov ecx, MAZE_SZ
        xor al, al
        rep stosb
        ; Clear parent
        mov edi, parent
        mov ecx, MAZE_SZ
        mov eax, -1
.sp_fill:
        mov [edi], eax
        add edi, 4
        dec ecx
        jnz .sp_fill

        ; BFS from start (1,1)
        mov dword [q_head], 0
        mov dword [q_tail], 0
        mov eax, 1*MAZE_W + 1
        mov byte [visited + eax], 1
        mov ecx, [q_tail]
        mov [bfs_queue + ecx*4], eax
        inc dword [q_tail]

        mov ebx, (MAZE_H-2)*MAZE_W + (MAZE_W-2)  ; goal index

.bfs_loop:
        mov ecx, [q_head]
        cmp ecx, [q_tail]
        jge .bfs_done

        mov eax, [bfs_queue + ecx*4]
        inc dword [q_head]

        cmp eax, ebx
        je .bfs_found

        ; Try 4 neighbors
        ; Up
        mov edx, eax
        sub edx, MAZE_W
        cmp edx, 0
        jl .bfs_no_up
        call .bfs_try
.bfs_no_up:
        ; Down
        mov edx, eax
        add edx, MAZE_W
        cmp edx, MAZE_SZ
        jge .bfs_no_down
        call .bfs_try
.bfs_no_down:
        ; Left
        mov edx, eax
        dec edx
        call .bfs_try
        ; Right
        mov edx, eax
        inc edx
        call .bfs_try

        jmp .bfs_loop

.bfs_try:
        cmp byte [visited + edx], 0
        jne .bfs_tr
        cmp byte [maze + edx], WALL
        je .bfs_tr
        mov byte [visited + edx], 1
        mov [parent + edx*4], eax
        push ecx
        mov ecx, [q_tail]
        mov [bfs_queue + ecx*4], edx
        inc dword [q_tail]
        pop ecx
.bfs_tr:
        ret

.bfs_found:
        ; Trace back from goal
        mov eax, ebx
.bfs_trace:
        cmp byte [maze + eax], START
        je .bfs_done
        cmp byte [maze + eax], GOAL
        je .bfs_trace_skip
        mov byte [maze + eax], SOLVE
.bfs_trace_skip:
        mov eax, [parent + eax*4]
        cmp eax, -1
        jne .bfs_trace

.bfs_done:
        popad
        ret

;---------------------------------------
; Simple PRNG (LCG)
;---------------------------------------
prng:
        push ebx
        mov eax, [prng_state]
        imul eax, 1103515245
        add eax, 12345
        mov [prng_state], eax
        shr eax, 16
        and eax, 0x7FFF
        pop ebx
        ret

;---------------------------------------
; Data
;---------------------------------------
msg_title:      db "MAZE", 0
msg_hint:       db "ANY KEY = NEW MAZE   ESC = QUIT", 0

; Seed PRNG from a constant (will be varied by timing)
prng_state: dd 31337

;---------------------------------------
; BSS - must come after data
;---------------------------------------
maze:       times MAZE_SZ db 0
visited:    times MAZE_SZ db 0
parent:     times MAZE_SZ dd 0
dfs_stack:  times MAZE_SZ dd 0
stack_ptr:  dd 0
bfs_queue:  times MAZE_SZ dd 0
q_head:     dd 0
q_tail:     dd 0
