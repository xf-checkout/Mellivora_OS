; pipes.asm - Pipe Dream puzzle game for Mellivora OS
; VBE 1024x768. Arrows=cursor, Enter=place piece, Space=flow, R=restart, ESC=quit.

%include "syscalls.inc"
%include "lib/vbe_game.inc"
%include "lib/font.inc"
%include "lib/audio.inc"
%include "lib/highscore.inc"

GRID_X          equ 192
GRID_Y          equ 168
GRID_COLS       equ 10
GRID_ROWS       equ 8
CELL_SIZE       equ 64
GRID_W          equ (GRID_COLS * CELL_SIZE)
GRID_H          equ (GRID_ROWS * CELL_SIZE)

; Pipe types (packed bits: NESW = bit3..bit0)
PIPE_NONE       equ 0
PIPE_H          equ 0x05        ; E+W (horizontal)
PIPE_V          equ 0x0A        ; N+S (vertical)
PIPE_NE         equ 0x09        ; N+E (elbow)
PIPE_NW         equ 0x0C        ; N+W
PIPE_SE         equ 0x03        ; S+E
PIPE_SW         equ 0x06        ; S+W
PIPE_CROSS      equ 0x0F        ; all 4
NUM_PIECES      equ 7

; Direction bits
DIR_N           equ 8           ; bit 3
DIR_E           equ 1           ; bit 0
DIR_S           equ 2           ; bit 1
DIR_W           equ 4           ; bit 2

; Cell states
CELL_EMPTY      equ 0
CELL_PLACED     equ 1
CELL_FILLED     equ 2
CELL_SOURCE     equ 3
CELL_DRAIN      equ 4

; Game states
STATE_PLAY      equ 0
STATE_FLOWING   equ 1
STATE_WIN       equ 2
STATE_LOSE      equ 3

; Colors
COL_BG          equ 0x00334455
COL_GRID_BG     equ 0x00556677
COL_GRID_LINE   equ 0x00445566
COL_PIPE        equ 0x00CCCCCC
COL_PIPE_FILL   equ 0x003399FF
COL_SOURCE      equ 0x0044DD44
COL_DRAIN       equ 0x00DD4444
COL_HUD         equ 0x00FFFFFF
COL_HUD_BG      equ 0x00222233
COL_PREVIEW     equ 0x00AAAACC
COL_WIN_TEXT    equ 0x0044FF44
COL_LOSE_TEXT   equ 0x00FF4444
COL_CURSOR      equ 0x00FFFF44

start:
        VBE_GAME_INIT
        call init_game

.main_loop:
        cmp dword [game_state], STATE_FLOWING
        jne .not_flowing
        call advance_flow
.not_flowing:
        VBE_GAME_POLL_KEY
        cmp eax, -1
        je .no_key
        cmp al, KEY_ESC
        je .exit_game
        cmp al, 'q'
        je .exit_game
        cmp al, 'Q'
        je .exit_game
        cmp al, 'R'
        je .restart
        cmp al, KEY_UP
        je .cur_up
        cmp al, KEY_DOWN
        je .cur_down
        cmp al, KEY_LEFT
        je .cur_left
        cmp al, KEY_RIGHT
        je .cur_right
        cmp al, KEY_ENTER
        je .place_pipe
        cmp al, KEY_SPACE
        je .start_flow
        jmp .no_key

.cur_up:
        cmp dword [cursor_row], 0
        je .no_key
        dec dword [cursor_row]
        jmp .no_key
.cur_down:
        mov eax, [cursor_row]
        cmp eax, GRID_ROWS - 1
        je .no_key
        inc dword [cursor_row]
        jmp .no_key
.cur_left:
        cmp dword [cursor_col], 0
        je .no_key
        dec dword [cursor_col]
        jmp .no_key
.cur_right:
        mov eax, [cursor_col]
        cmp eax, GRID_COLS - 1
        je .no_key
        inc dword [cursor_col]
        jmp .no_key

.place_pipe:
        cmp dword [game_state], STATE_PLAY
        jne .no_key
        mov eax, [cursor_row]
        imul eax, GRID_COLS
        add eax, [cursor_col]
        cmp byte [grid_state + eax], CELL_EMPTY
        jne .no_key
        movzx edx, byte [next_piece]
        mov [grid_pipes + eax], dl
        mov byte [grid_state + eax], CELL_PLACED
        call gen_next_piece
        inc dword [pieces_placed]
        jmp .no_key

.start_flow:
        cmp dword [game_state], STATE_PLAY
        jne .no_key
        mov dword [game_state], STATE_FLOWING
        mov dword [flow_timer], 0
        movzx eax, byte [source_row]
        imul eax, GRID_COLS
        movzx ebx, byte [source_col]
        add eax, ebx
        mov [flow_pos], eax
        mov byte [flow_dir], DIR_E
        jmp .no_key

.restart:
        call init_game
        jmp .main_loop

.no_key:
        call draw_all
        mov eax, SYS_SLEEP
        mov ebx, 2
        int 0x80
        jmp .main_loop

.exit_game:
        mov eax, SYS_FRAMEBUF
        mov ebx, 2
        int 0x80
        xor eax, eax
        int 0x80


; ─── init_game ───────────────────────────────────────────────
init_game:
        pushad
        ; Clear grid
        mov edi, grid_pipes
        mov ecx, GRID_COLS * GRID_ROWS
        xor eax, eax
        rep stosb
        mov edi, grid_state
        mov ecx, GRID_COLS * GRID_ROWS
        rep stosb

        mov dword [game_state], STATE_PLAY
        mov dword [pieces_placed], 0
        mov dword [score], 0
        mov dword [flow_timer], 0
        ; First-call: load persistent high score from /scores/pipes
        cmp byte [hs_loaded], 0
        jne .ig_loaded
        mov byte [hs_loaded], 1
        mov esi, hs_name_pp
        call hs_load
        mov [hi_score], eax
.ig_loaded:

        ; Place source at left side, random row
        mov eax, SYS_GETTIME
        int 0x80
        xor edx, edx
        mov ecx, GRID_ROWS - 2
        div ecx
        inc edx                  ; row 1..ROWS-2
        mov [source_row], dl
        mov byte [source_col], 0
        movzx eax, dl
        imul eax, GRID_COLS
        mov byte [grid_state + eax], CELL_SOURCE
        mov byte [grid_pipes + eax], DIR_E  ; source opens east

        ; Place drain at right side, random row
        mov eax, SYS_GETTIME
        int 0x80
        shr eax, 4
        xor edx, edx
        mov ecx, GRID_ROWS - 2
        div ecx
        inc edx
        mov [drain_row], dl
        mov byte [drain_col], GRID_COLS - 1
        movzx eax, dl
        imul eax, GRID_COLS
        add eax, GRID_COLS - 1
        mov byte [grid_state + eax], CELL_DRAIN
        mov byte [grid_pipes + eax], DIR_W  ; drain opens west

        ; Generate first piece
        call gen_next_piece

        popad
        ret


; ─── gen_next_piece ──────────────────────────────────────────
gen_next_piece:
        push eax
        push ecx
        push edx
        mov eax, SYS_GETTIME
        int 0x80
        xor edx, edx
        mov ecx, NUM_PIECES
        div ecx
        movzx eax, byte [piece_types + edx]
        mov [next_piece], al
        pop edx
        pop ecx
        pop eax
        ret


; ─── advance_flow ────────────────────────────────────────────
; Advance water one cell. Called each frame.
advance_flow:
        pushad
        ; Flow speed: advance every 15 frames
        inc dword [flow_timer]
        cmp dword [flow_timer], 15
        jl .af_done
        mov dword [flow_timer], 0

        ; Current position
        mov eax, [flow_pos]
        cmp eax, 0
        jl .af_lose
        cmp eax, GRID_COLS * GRID_ROWS
        jge .af_lose

        ; Mark current cell as filled
        mov byte [grid_state + eax], CELL_FILLED
        add dword [score], 10

        ; Determine next cell based on flow direction
        movzx ebx, byte [flow_dir]

        ; Get current pipe connectivity
        movzx ecx, byte [grid_pipes + eax]

        ; Check if current pipe has an opening in the flow direction
        ; (for source/pipe cells, check the bits)

        ; Find exit direction: flow_dir enters, need to find the other opening
        ; Invert entry direction to get entry side
        ; If flowing East, we enter from West -> entry bit = DIR_W
        ; Exit = pipe_bits & ~entry_bit
        mov edx, ebx               ; flow direction (which side we exit from prev cell)
        ; Convert to entry side of current cell
        ; N->S, E->W, S->N, W->E
        call invert_dir             ; edx = entry side
        mov esi, ecx
        and esi, edx                ; Does pipe have opening on entry side?
        test esi, esi
        jz .af_lose                 ; No entry -> water leaks

        ; Find exit: remove entry direction, remaining bits = possible exits
        not edx
        and ecx, edx
        and ecx, 0x0F              ; mask to 4 bits

        ; If no exit bits, dead end
        test ecx, ecx
        jz .af_lose

        ; Pick first available exit direction
        test ecx, DIR_N
        jnz .af_go_n
        test ecx, DIR_E
        jnz .af_go_e
        test ecx, DIR_S
        jnz .af_go_s
        test ecx, DIR_W
        jnz .af_go_w
        jmp .af_lose

.af_go_n:
        sub eax, GRID_COLS
        mov byte [flow_dir], DIR_N
        jmp .af_moved
.af_go_e:
        inc eax
        mov byte [flow_dir], DIR_E
        jmp .af_moved
.af_go_s:
        add eax, GRID_COLS
        mov byte [flow_dir], DIR_S
        jmp .af_moved
.af_go_w:
        dec eax
        mov byte [flow_dir], DIR_W
        jmp .af_moved

.af_moved:
        ; Bounds check
        cmp eax, 0
        jl .af_lose
        cmp eax, GRID_COLS * GRID_ROWS
        jge .af_lose

        ; Check if we reached the drain
        cmp byte [grid_state + eax], CELL_DRAIN
        je .af_win

        ; Check if next cell has a pipe or is empty
        cmp byte [grid_state + eax], CELL_EMPTY
        je .af_lose
        cmp byte [grid_state + eax], CELL_FILLED
        je .af_lose              ; already filled = loop, lose

        mov [flow_pos], eax
        jmp .af_done

.af_win:
        mov byte [grid_state + eax], CELL_FILLED
        add dword [score], 100
        mov dword [game_state], STATE_WIN
        ; Persist high score (only if better) + win SFX
        mov esi, hs_name_pp
        mov ebx, [score]
        call hs_update
        mov [hi_score], eax
        call audio_sfx_win
        jmp .af_done

.af_lose:
        mov dword [game_state], STATE_LOSE
        call audio_sfx_lose

.af_done:
        popad
        ret


; ─── invert_dir ──────────────────────────────────────────────
; EDX = direction bit -> EDX = opposite direction
invert_dir:
        cmp edx, DIR_N
        je .inv_s
        cmp edx, DIR_S
        je .inv_n
        cmp edx, DIR_E
        je .inv_w
        cmp edx, DIR_W
        je .inv_e
        ret
.inv_n: mov edx, DIR_N
        ret
.inv_s: mov edx, DIR_S
        ret
.inv_e: mov edx, DIR_E
        ret
.inv_w: mov edx, DIR_W
        ret


; ─── draw_all ────────────────────────────────────────────────
draw_all:
        pushad

        ; Background
        mov edx, COL_BG
        call vbe_clear_screen

        ; HUD background
        mov ebx, 0
        mov ecx, 0
        mov edx, 1024
        mov esi, 80
        mov edi, COL_HUD_BG
        call vbe_fill_rect

        ; SCORE:
        mov ebx, 30
        mov ecx, 28
        mov edx, str_score
        mov esi, COL_HUD
        mov eax, 2
        call vbe_draw_str
        mov ebx, 150
        mov ecx, 28
        mov edx, [score]
        mov esi, COL_HUD
        mov eax, 2
        call vbe_draw_num

        ; NEXT:
        mov ebx, 300
        mov ecx, 28
        mov edx, str_next
        mov esi, COL_HUD
        mov eax, 2
        call vbe_draw_str

        ; Draw next piece preview (cell_size=64 in HUD)
        movzx eax, byte [next_piece]
        mov ebx, 400
        mov ecx, 8
        mov edx, COL_PREVIEW
        mov esi, 60
        call draw_pipe_vbe

        ; Controls hint
        mov ebx, 550
        mov ecx, 28
        mov edx, str_controls
        mov esi, 0x00778888
        mov eax, 1
        call vbe_draw_str

        ; Grid background
        mov ebx, GRID_X
        mov ecx, GRID_Y
        mov edx, GRID_W
        mov esi, GRID_H
        mov edi, COL_GRID_BG
        call vbe_fill_rect

        ; Draw cells
        mov dword [.dr], 0
.da_row:
        cmp dword [.dr], GRID_ROWS
        jge .da_done
        mov dword [.dc], 0
.da_col:
        cmp dword [.dc], GRID_COLS
        jge .da_row_next

        ; Cell index
        mov eax, [.dr]
        imul eax, GRID_COLS
        add eax, [.dc]
        mov [.da_idx], eax

        ; Cell pixel position
        mov ebx, [.dc]
        imul ebx, CELL_SIZE
        add ebx, GRID_X
        mov ecx, [.dr]
        imul ecx, CELL_SIZE
        add ecx, GRID_Y
        mov [.da_px], ebx
        mov [.da_py], ecx

        ; Cell border
        mov edx, CELL_SIZE
        mov esi, CELL_SIZE
        mov edi, COL_GRID_LINE
        call vbe_fill_rect

        ; Inner cell
        mov ebx, [.da_px]
        inc ebx
        mov ecx, [.da_py]
        inc ecx
        mov edx, CELL_SIZE - 2
        mov esi, CELL_SIZE - 2
        mov edi, COL_GRID_BG
        call vbe_fill_rect

        ; Cursor highlight
        mov eax, [.dr]
        cmp eax, [cursor_row]
        jne .da_no_cursor
        mov eax, [.dc]
        cmp eax, [cursor_col]
        jne .da_no_cursor
        mov ebx, [.da_px]
        mov ecx, [.da_py]
        mov edx, CELL_SIZE
        mov esi, 3
        mov edi, COL_CURSOR
        call vbe_fill_rect
        mov ebx, [.da_px]
        mov ecx, [.da_py]
        add ecx, CELL_SIZE - 3
        mov edx, CELL_SIZE
        mov esi, 3
        mov edi, COL_CURSOR
        call vbe_fill_rect
        mov ebx, [.da_px]
        mov ecx, [.da_py]
        mov edx, 3
        mov esi, CELL_SIZE
        mov edi, COL_CURSOR
        call vbe_fill_rect
        mov ebx, [.da_px]
        add ebx, CELL_SIZE - 3
        mov ecx, [.da_py]
        mov edx, 3
        mov esi, CELL_SIZE
        mov edi, COL_CURSOR
        call vbe_fill_rect
.da_no_cursor:

        ; Draw cell content
        mov eax, [.da_idx]
        cmp byte [grid_state + eax], CELL_EMPTY
        je .da_next_cell
        cmp byte [grid_state + eax], CELL_SOURCE
        je .da_source
        cmp byte [grid_state + eax], CELL_DRAIN
        je .da_drain
        cmp byte [grid_state + eax], CELL_FILLED
        je .da_filled
        ; Placed pipe
        mov eax, [.da_idx]
        movzx eax, byte [grid_pipes + eax]
        mov ebx, [.da_px]
        add ebx, 1
        mov ecx, [.da_py]
        add ecx, 1
        mov edx, COL_PIPE
        mov esi, CELL_SIZE - 2
        call draw_pipe_vbe
        jmp .da_next_cell
.da_source:
        mov ebx, [.da_px]
        add ebx, 4
        mov ecx, [.da_py]
        add ecx, 4
        mov edx, CELL_SIZE - 8
        mov esi, CELL_SIZE - 8
        mov edi, COL_SOURCE
        call vbe_fill_rect
        jmp .da_next_cell
.da_drain:
        mov ebx, [.da_px]
        add ebx, 4
        mov ecx, [.da_py]
        add ecx, 4
        mov edx, CELL_SIZE - 8
        mov esi, CELL_SIZE - 8
        mov edi, COL_DRAIN
        call vbe_fill_rect
        jmp .da_next_cell
.da_filled:
        mov eax, [.da_idx]
        movzx eax, byte [grid_pipes + eax]
        mov ebx, [.da_px]
        add ebx, 1
        mov ecx, [.da_py]
        add ecx, 1
        mov edx, COL_PIPE_FILL
        mov esi, CELL_SIZE - 2
        call draw_pipe_vbe
.da_next_cell:
        inc dword [.dc]
        jmp .da_col
.da_row_next:
        inc dword [.dr]
        jmp .da_row

.da_done:
        ; State overlays
        cmp dword [game_state], STATE_WIN
        je .da_win
        cmp dword [game_state], STATE_LOSE
        je .da_lose
        jmp .da_present

.da_win:
        mov ebx, 342
        mov ecx, 340
        mov edx, str_win
        mov esi, COL_WIN_TEXT
        mov eax, 3
        call vbe_draw_str
        jmp .da_present

.da_lose:
        mov ebx, 252
        mov ecx, 340
        mov edx, str_lose
        mov esi, COL_LOSE_TEXT
        mov eax, 3
        call vbe_draw_str

.da_present:
        VBE_GAME_PRESENT
        popad
        ret

.dr:    dd 0
.dc:    dd 0
.da_idx: dd 0
.da_px: dd 0
.da_py: dd 0


; draw_pipe_vbe: EAX=pipe_type, EBX=x, ECX=y, EDX=color, ESI=cell_size
draw_pipe_vbe:
        pushad
        mov [.dp_type], al
        mov [.dp_x], ebx
        mov [.dp_y], ecx
        mov [.dp_col], edx
        mov eax, esi
        shr eax, 1
        mov [.dp_half], eax
        shr eax, 1
        mov [.dp_qrtr], eax

        movzx eax, byte [.dp_type]
        test al, DIR_N
        jz .dp_no_n
        mov eax, [.dp_qrtr]
        shr eax, 1
        mov ebx, [.dp_x]
        add ebx, [.dp_half]
        sub ebx, eax
        mov ecx, [.dp_y]
        mov edx, [.dp_qrtr]
        mov esi, [.dp_half]
        mov edi, [.dp_col]
        call vbe_fill_rect
.dp_no_n:
        movzx eax, byte [.dp_type]
        test al, DIR_S
        jz .dp_no_s
        mov eax, [.dp_qrtr]
        shr eax, 1
        mov ebx, [.dp_x]
        add ebx, [.dp_half]
        sub ebx, eax
        mov ecx, [.dp_y]
        add ecx, [.dp_half]
        mov edx, [.dp_qrtr]
        mov esi, [.dp_half]
        mov edi, [.dp_col]
        call vbe_fill_rect
.dp_no_s:
        movzx eax, byte [.dp_type]
        test al, DIR_E
        jz .dp_no_e
        mov eax, [.dp_qrtr]
        shr eax, 1
        mov ecx, [.dp_y]
        add ecx, [.dp_half]
        sub ecx, eax
        mov ebx, [.dp_x]
        add ebx, [.dp_half]
        mov edx, [.dp_half]
        mov esi, [.dp_qrtr]
        mov edi, [.dp_col]
        call vbe_fill_rect
.dp_no_e:
        movzx eax, byte [.dp_type]
        test al, DIR_W
        jz .dp_no_w
        mov eax, [.dp_qrtr]
        shr eax, 1
        mov ecx, [.dp_y]
        add ecx, [.dp_half]
        sub ecx, eax
        mov ebx, [.dp_x]
        mov edx, [.dp_half]
        mov esi, [.dp_qrtr]
        mov edi, [.dp_col]
        call vbe_fill_rect
.dp_no_w:
        popad
        ret

.dp_type: db 0
.dp_x:    dd 0
.dp_y:    dd 0
.dp_col:  dd 0
.dp_half: dd 0
.dp_qrtr: dd 0


; ═════════════════════════════════════════════════════════════
; DATA
; ═════════════════════════════════════════════════════════════

str_score:      db "SCORE:", 0
str_next:       db "NEXT:", 0
str_controls:   db "ARROWS=MOVE  ENTER=PLACE  SPACE=FLOW  R=RESTART  ESC=QUIT", 0
str_win:        db "YOU WIN  R=RESTART", 0
str_lose:       db "LEAKED  R=RESTART", 0

; Available piece types
piece_types:    db PIPE_H, PIPE_V, PIPE_NE, PIPE_NW, PIPE_SE, PIPE_SW, PIPE_CROSS


; ═════════════════════════════════════════════════════════════
; BSS
; ═════════════════════════════════════════════════════════════

game_state:     dd 0
score:          dd 0
hs_name_pp:     db "pipes", 0
hs_loaded:      db 0
hi_score:       dd 0
pieces_placed:  dd 0
flow_timer:     dd 0
flow_pos:       dd 0
flow_dir:       db 0
next_piece:     db 0
source_row:     db 0
source_col:     db 0
drain_row:      db 0
drain_col:      db 0
align 4
cursor_row:     dd 0
cursor_col:     dd 0

grid_pipes:     times GRID_COLS * GRID_ROWS db 0
grid_state:     times GRID_COLS * GRID_ROWS db 0
