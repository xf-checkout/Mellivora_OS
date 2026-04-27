; lights.asm - Lights Out puzzle for Mellivora OS
; VBE 1024x768x32bpp. Click a light to toggle it and its neighbours.
; Turn all lights off to win.
%include "syscalls.inc"
%include "lib/vbe_game.inc"
%include "lib/font.inc"
%include "lib/audio.inc"
%include "lib/highscore.inc"

GRID_DIM        equ 5
CELL_SZ         equ 100         ; pixel size of each cell
CELL_GAP        equ 8           ; gap between cells
; Grid origin (top-left of cell 0,0)
GRID_X          equ 262         ; (1024 - 5*(100+8) - (-8)) / 2 = 262
GRID_Y          equ 180

COL_BG          equ 0x00101820
COL_ON          equ 0x00FFEE44   ; lit cell
COL_OFF         equ 0x00223344   ; unlit cell
COL_BORDER      equ 0x00445566
COL_WHITE       equ 0x00FFFFFF
COL_YELLOW      equ 0x00FFE040
COL_GRAY        equ 0x00888888
COL_GREEN       equ 0x0033DD44

start:
.new_game:
        VBE_GAME_INIT

        ; Default solvable pattern
        xor eax, eax
        mov ecx, 25
        mov edi, grid
        rep stosb

        mov byte [grid + 0*5 + 2], 1
        mov byte [grid + 1*5 + 1], 1
        mov byte [grid + 1*5 + 2], 1
        mov byte [grid + 1*5 + 3], 1
        mov byte [grid + 2*5 + 0], 1
        mov byte [grid + 2*5 + 2], 1
        mov byte [grid + 2*5 + 4], 1
        mov byte [grid + 3*5 + 1], 1
        mov byte [grid + 3*5 + 2], 1
        mov byte [grid + 3*5 + 3], 1
        mov byte [grid + 4*5 + 2], 1
        mov dword [move_count], 0
        ; First-call: load persistent solves from /scores/lights
        cmp byte [hs_loaded], 0
        jne .ng_loaded
        mov byte [hs_loaded], 1
        pushad
        mov esi, hs_name_lt
        call hs_load
        mov [total_solves], eax
        popad
.ng_loaded:

        call draw_screen

.main_loop:
        ; Poll key
        mov eax, SYS_READ_KEY
        int 0x80
        cmp al, 'q'
        je .quit
        cmp al, 'Q'
        je .quit
        cmp al, KEY_ESC
        je .quit

        ; Poll mouse
        mov eax, SYS_MOUSE
        int 0x80
        ; EAX=x, EBX=y, ECX=buttons
        test ecx, ecx
        jz .no_click

        ; Was already pressed?
        cmp byte [last_btn], 0
        jne .update_btn

        ; New click — find which cell was clicked
        mov [last_btn], cl
        mov [mx_tmp], eax
        mov [my_tmp], ebx

        ; cell_col = (mx - GRID_X) / (CELL_SZ + CELL_GAP)
        mov eax, [mx_tmp]
        sub eax, GRID_X
        js .no_click
        mov ebx, CELL_SZ + CELL_GAP
        xor edx, edx
        div ebx
        cmp eax, GRID_DIM
        jge .no_click
        ; Reject clicks in the gap
        push eax
        imul eax, CELL_SZ + CELL_GAP
        add eax, GRID_X
        mov ecx, [mx_tmp]
        sub ecx, eax
        cmp ecx, CELL_SZ
        pop eax
        jge .no_click
        mov [sel_col], eax

        ; cell_row = (my - GRID_Y) / (CELL_SZ + CELL_GAP)
        mov eax, [my_tmp]
        sub eax, GRID_Y
        js .no_click
        mov ebx, CELL_SZ + CELL_GAP
        xor edx, edx
        div ebx
        cmp eax, GRID_DIM
        jge .no_click
        push eax
        imul eax, CELL_SZ + CELL_GAP
        add eax, GRID_Y
        mov ecx, [my_tmp]
        sub ecx, eax
        cmp ecx, CELL_SZ
        pop eax
        jge .no_click
        mov [sel_row], eax

        ; Toggle!
        call do_toggle
        inc dword [move_count]

        ; Check solved
        call check_solved
        test eax, eax
        jnz .solved

        call draw_screen
        jmp .no_click

.update_btn:
        mov [last_btn], cl
        jmp .no_click

.no_click:
        cmp dword [last_btn], 0
        je .skip_clear
        mov eax, SYS_MOUSE
        int 0x80
        test ecx, ecx
        jz .clear_btn
        jmp .skip_clear
.clear_btn:
        mov dword [last_btn], 0
.skip_clear:

        mov eax, SYS_SLEEP
        mov ebx, 2
        int 0x80
        jmp .main_loop

.solved:
        ; Bump persistent solves, save, win SFX (once per board)
        pushad
        mov eax, [total_solves]
        inc eax
        mov [total_solves], eax
        mov ebx, [total_solves]
        mov esi, hs_name_lt
        call hs_save
        call audio_sfx_win
        popad
        call draw_screen
        ; Flash "SOLVED" message and wait for key
.wait_solved:
        mov eax, SYS_READ_KEY
        int 0x80
        cmp al, 'q'
        je .quit
        cmp al, 'Q'
        je .quit
        cmp al, KEY_ESC
        je .quit
        test eax, eax
        jz .wait_solved
        jmp .new_game

.quit:
        mov eax, SYS_FRAMEBUF
        mov ebx, 2
        int 0x80
        xor eax, eax
        int 0x80

;--------------------------------------
do_toggle:
        mov ebp, [sel_row]
        mov ecx, [sel_col]
        call toggle_cell
        mov ebp, [sel_row]
        dec ebp
        js .no_up
        mov ecx, [sel_col]
        call toggle_cell
.no_up:
        mov ebp, [sel_row]
        inc ebp
        cmp ebp, GRID_DIM
        jge .no_dn
        mov ecx, [sel_col]
        call toggle_cell
.no_dn:
        mov ebp, [sel_row]
        mov ecx, [sel_col]
        dec ecx
        js .no_lf
        call toggle_cell
.no_lf:
        mov ebp, [sel_row]
        mov ecx, [sel_col]
        inc ecx
        cmp ecx, GRID_DIM
        jge .no_rt
        call toggle_cell
.no_rt:
        ret

toggle_cell:
        mov eax, ebp
        imul eax, GRID_DIM
        add eax, ecx
        xor byte [grid + eax], 1
        ret

check_solved:
        xor ebp, ebp
.cs:    cmp ebp, 25
        jge .all_off
        movzx eax, byte [grid + ebp]
        test eax, eax
        jnz .not_solved
        inc ebp
        jmp .cs
.not_solved:
        xor eax, eax
        ret
.all_off:
        mov eax, 1
        ret

;--------------------------------------
draw_screen:
        pushad
        mov edx, COL_BG
        call vbe_clear_screen

        ; Title
        mov ebx, 370
        mov ecx, 50
        mov edx, msg_title
        mov esi, COL_YELLOW
        mov eax, 3
        call vbe_draw_str

        ; Instruction
        mov ebx, 215
        mov ecx, 115
        mov edx, msg_inst
        mov esi, COL_GRAY
        mov eax, 2
        call vbe_draw_str

        ; Draw 5x5 grid — use memory loop vars
        mov dword [.dr], 0      ; row counter
.dr_row:
        cmp dword [.dr], GRID_DIM
        jge .dr_done
        mov dword [.dc], 0      ; col counter
.dr_col:
        cmp dword [.dc], GRID_DIM
        jge .dr_col_done

        ; Cell top-left
        mov eax, [.dc]
        imul eax, CELL_SZ + CELL_GAP
        add eax, GRID_X
        mov [.cx], eax
        mov eax, [.dr]
        imul eax, CELL_SZ + CELL_GAP
        add eax, GRID_Y
        mov [.cy], eax

        ; Colour
        mov eax, [.dr]
        imul eax, GRID_DIM
        add eax, [.dc]
        movzx eax, byte [grid + eax]
        test eax, eax
        jz .cell_off
        mov edi, COL_ON
        jmp .draw_cell
.cell_off:
        mov edi, COL_OFF
.draw_cell:
        mov ebx, [.cx]
        mov ecx, [.cy]
        mov edx, CELL_SZ
        mov esi, CELL_SZ
        call vbe_fill_rect

        ; 1px border (4 lines)
        mov esi, COL_BORDER
        mov ebx, [.cx]        ; top
        mov ecx, [.cy]
        mov edx, CELL_SZ
        call vbe_draw_hline
        mov ecx, [.cy]        ; left
        add ecx, 1
        mov edx, CELL_SZ - 1
        call vbe_draw_vline
        mov ecx, [.cy]        ; bottom
        add ecx, CELL_SZ
        mov edx, CELL_SZ
        call vbe_draw_hline
        mov ebx, [.cx]        ; right
        add ebx, CELL_SZ
        mov ecx, [.cy]
        mov edx, CELL_SZ
        call vbe_draw_vline

        inc dword [.dc]
        jmp .dr_col
.dr_col_done:
        inc dword [.dr]
        jmp .dr_row

.dr_done:
        ; Moves counter
        mov ebx, 400
        mov ecx, GRID_Y + GRID_DIM * (CELL_SZ + CELL_GAP) + 20
        mov edx, msg_moves
        mov esi, COL_WHITE
        mov eax, 2
        call vbe_draw_str
        mov ebx, 470
        mov edx, [move_count]
        call vbe_draw_num

        ; Solved message?
        call check_solved
        test eax, eax
        jz .no_solved_msg
        mov ebx, 380
        mov ecx, GRID_Y + GRID_DIM * (CELL_SZ + CELL_GAP) + 70
        mov edx, msg_solved
        mov esi, COL_GREEN
        mov eax, 3
        call vbe_draw_str
.no_solved_msg:

        VBE_GAME_PRESENT
        popad
        ret

.cx: dd 0
.cy: dd 0
.dr: dd 0
.dc: dd 0

;=== Data ===
msg_title:  db "LIGHTS OUT", 0
msg_inst:   db "CLICK A LIGHT TO TOGGLE IT AND ITS NEIGHBOURS", 0
msg_moves:  db "MOVES:", 0
msg_solved: db "SOLVED!", 0

grid:       times 25 db 0
sel_row:    dd 0
sel_col:    dd 0
move_count: dd 0
last_btn:   dd 0
hs_name_lt:    db "lights", 0
hs_loaded:     db 0
total_solves:  dd 0
mx_tmp:     dd 0
my_tmp:     dd 0
