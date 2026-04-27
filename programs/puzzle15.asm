; puzzle15.asm - 15-puzzle (4x4 sliding tiles)
; VBE 1024x768x32bpp. Arrow keys to slide tiles. R to reshuffle. Q to quit.
%include "syscalls.inc"
%include "lib/vbe_game.inc"
%include "lib/font.inc"
%include "lib/audio.inc"
%include "lib/highscore.inc"

CELL_SZ         equ 150
CELL_GAP        equ 6
GRID_X          equ 200
GRID_Y          equ 120

COL_BG          equ 0x000A0E18
COL_TILE        equ 0x00224488
COL_TEXT        equ 0x00FFFFFF
COL_BORDER      equ 0x001122AA
COL_YELLOW      equ 0x00FFE040
COL_GREEN       equ 0x0033EE55
COL_GRAY        equ 0x00888888

DIM             equ 4

start:
        VBE_GAME_INIT
        call init_solved
        call shuffle_board
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
        cmp al, 'r'
        je .reshuffle

        cmp dword [solved_flag], 1
        je .no_key

        cmp al, KEY_UP
        je .move_up
        cmp al, KEY_DOWN
        je .move_down
        cmp al, KEY_LEFT
        je .move_left
        cmp al, KEY_RIGHT
        je .move_right
        jmp .no_key

.move_up:
        call try_up
        jmp .after_move
.move_down:
        call try_down
        jmp .after_move
.move_left:
        call try_left
        jmp .after_move
.move_right:
        call try_right
        jmp .after_move

.reshuffle:
        call init_solved
        call shuffle_board
        mov dword [solved_flag], 0
        mov dword [move_count], 0
.after_move:
        call check_solved
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
init_solved:
        xor ecx, ecx
.is_loop:
        cmp ecx, 16
        jge .is_done
        mov eax, ecx
        add eax, 1
        cmp ecx, 15
        jne .is_store
        xor eax, eax
.is_store:
        mov [board + ecx*4], eax
        inc ecx
        jmp .is_loop
.is_done:
        mov dword [blank_pos], 15
        mov dword [move_count], 0
        mov dword [solved_flag], 0
        ; First-call: load persistent solve count from /scores/puzzle15
        cmp byte [hs_loaded], 0
        jne .is_ret
        mov byte [hs_loaded], 1
        pushad
        mov esi, hs_name_p15
        call hs_load
        mov [total_solves], eax
        popad
.is_ret:
        ret

;--------------------------------------
shuffle_board:
        mov ecx, 500
.sh_loop:
        push ecx
        call rand
        xor edx, edx
        mov ebx, 4
        div ebx
        cmp eax, 0
        je .sh_up
        cmp eax, 1
        je .sh_down
        cmp eax, 2
        je .sh_left
        call try_right
        jmp .sh_next
.sh_up:
        call try_up
        jmp .sh_next
.sh_down:
        call try_down
        jmp .sh_next
.sh_left:
        call try_left
.sh_next:
        pop ecx
        loop .sh_loop
        mov dword [move_count], 0
        ret

;--------------------------------------
try_up:
        mov eax, [blank_pos]
        add eax, DIM
        cmp eax, 16
        jge .tu_ret
        call swap_with_blank
        inc dword [move_count]
.tu_ret:
        ret

try_down:
        mov eax, [blank_pos]
        sub eax, DIM
        js .td_ret
        call swap_with_blank
        inc dword [move_count]
.td_ret:
        ret

try_left:
        mov eax, [blank_pos]
        xor edx, edx
        push eax
        mov ebx, DIM
        div ebx
        mov [.col], edx
        pop eax
        cmp dword [.col], DIM-1
        je .tl_ret
        add eax, 1
        call swap_with_blank
        inc dword [move_count]
.tl_ret:
        ret
.col: dd 0

try_right:
        mov eax, [blank_pos]
        xor edx, edx
        push eax
        mov ebx, DIM
        div ebx
        mov [.col], edx
        pop eax
        cmp dword [.col], 0
        je .tr_ret
        sub eax, 1
        call swap_with_blank
        inc dword [move_count]
.tr_ret:
        ret
.col: dd 0

;--------------------------------------
swap_with_blank:
        mov ecx, [blank_pos]
        mov edx, [board + eax*4]
        mov [board + ecx*4], edx
        mov dword [board + eax*4], 0
        mov [blank_pos], eax
        ret

;--------------------------------------
check_solved:
        xor ecx, ecx
.cs_loop:
        cmp ecx, 15
        jge .cs_ok
        mov eax, [board + ecx*4]
        mov ebx, ecx
        add ebx, 1
        cmp eax, ebx
        jne .cs_no
        inc ecx
        jmp .cs_loop
.cs_ok:
        cmp dword [solved_flag], 1
        je .cs_already
        mov dword [solved_flag], 1
        ; First-time solved: bump persistent solve count, save, win SFX
        pushad
        mov eax, [total_solves]
        inc eax
        mov [total_solves], eax
        mov ebx, [total_solves]
        mov esi, hs_name_p15
        call hs_save
        call audio_sfx_win
        popad
.cs_already:
        ret
.cs_no:
        mov dword [solved_flag], 0
        ret

;--------------------------------------
rand:
        mov eax, [rand_state]
        imul eax, 1664525
        add eax, 1013904223
        mov [rand_state], eax
        shr eax, 16
        and eax, 0x7FFF
        ret

;--------------------------------------
draw_all:
        pushad
        mov edx, COL_BG
        call vbe_clear_screen

        mov ebx, 410
        mov ecx, 40
        mov edx, msg_title
        mov esi, COL_YELLOW
        mov eax, 3
        call vbe_draw_str

        mov dword [.di], 0
.da_loop:
        cmp dword [.di], 16
        jge .da_done

        mov eax, [.di]
        xor edx, edx
        mov ebx, DIM
        div ebx
        imul eax, CELL_SZ + CELL_GAP
        add eax, GRID_Y
        mov [.cy], eax
        imul edx, CELL_SZ + CELL_GAP
        add edx, GRID_X
        mov [.cx], edx

        mov eax, [.di]
        mov eax, [board + eax*4]
        test eax, eax
        jz .da_skip

        mov ebx, [.cx]
        mov ecx, [.cy]
        mov edx, CELL_SZ
        mov esi, CELL_SZ
        mov edi, COL_TILE
        call vbe_fill_rect

        mov ebx, [.cx]
        mov ecx, [.cy]
        mov edx, CELL_SZ
        mov esi, COL_BORDER
        call vbe_draw_hline
        mov ebx, [.cx]
        add ebx, CELL_SZ
        mov ecx, [.cy]
        mov edx, CELL_SZ
        call vbe_draw_vline
        mov ebx, [.cx]
        mov ecx, [.cy]
        add ecx, CELL_SZ
        mov edx, CELL_SZ
        call vbe_draw_hline
        mov ebx, [.cx]
        mov ecx, [.cy]
        mov edx, CELL_SZ
        call vbe_draw_vline

        mov ebx, [.cx]
        add ebx, 55
        mov ecx, [.cy]
        add ecx, 55
        mov eax, [.di]
        mov edx, [board + eax*4]
        mov esi, COL_TEXT
        mov eax, 3
        call vbe_draw_num

.da_skip:
        inc dword [.di]
        jmp .da_loop
.da_done:

        mov ebx, 430
        mov ecx, GRID_Y + 4*(CELL_SZ + CELL_GAP) + 20
        mov edx, msg_moves
        mov esi, COL_GRAY
        mov eax, 2
        call vbe_draw_str
        add ebx, 70
        mov edx, [move_count]
        mov esi, COL_TEXT
        mov eax, 2
        call vbe_draw_num

        cmp dword [solved_flag], 1
        jne .da_hint
        mov ebx, 410
        mov ecx, GRID_Y + 4*(CELL_SZ + CELL_GAP) + 65
        mov edx, msg_solved
        mov esi, COL_GREEN
        mov eax, 3
        call vbe_draw_str
        jmp .da_end

.da_hint:
        mov ebx, 310
        mov ecx, GRID_Y + 4*(CELL_SZ + CELL_GAP) + 65
        mov edx, msg_hint
        mov esi, COL_GRAY
        mov eax, 1
        call vbe_draw_str

.da_end:
        VBE_GAME_PRESENT
        popad
        ret

.cx: dd 0
.cy: dd 0
.di: dd 0

;=== Data ===
msg_title:  db "15 PUZZLE", 0
msg_moves:  db "MOVES:", 0
msg_solved: db "SOLVED!", 0
msg_hint:   db "ARROWS=SLIDE  R=SHUFFLE  Q=QUIT", 0

board:          times 16 dd 0
blank_pos:      dd 15
move_count:     dd 0
solved_flag:    dd 0
rand_state:     dd 0xDEADBEEF
hs_name_p15:    db "puzzle15", 0
hs_loaded:      db 0
total_solves:   dd 0
