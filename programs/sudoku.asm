; sudoku.asm - 9x9 Sudoku puzzle for Mellivora OS
; VBE 1024x768x32bpp.
;   Arrows = move cursor       1-9 = place digit
;   0 / SPACE = clear cell      R   = restart (new puzzle)
;   H = hint (fill one cell from solution)   ESC / Q = quit
; Solving the puzzle increments /scores/sudoku and plays the win SFX.
;-----------------------------------------------------------------------------

%include "syscalls.inc"
%include "lib/vbe_game.inc"
%include "lib/font.inc"
%include "lib/audio.inc"
%include "lib/highscore.inc"

;-----------------------------------------------------------------------------
; Layout (1024 x 768)
;-----------------------------------------------------------------------------
CELL_SZ         equ 64                  ; 9 * 64 = 576 wide
GRID_X          equ 96                  ; (1024-576)/2 ~ centred
GRID_Y          equ 80
HUD_X           equ 700
HUD_Y           equ 100

COL_BG          equ 0x000C1020
COL_GRID_LIGHT  equ 0x002A4070
COL_GRID_HEAVY  equ 0x0070A0FF
COL_CELL        equ 0x00161A30
COL_CELL_ALT    equ 0x001E2240          ; alternating 3x3 block
COL_CURSOR      equ 0x00FFEE40
COL_GIVEN       equ 0x00FFFFFF          ; pre-set clue digits
COL_USER        equ 0x0066D9FF          ; player-entered digits
COL_CONFLICT    equ 0x00FF6060          ; user digit that violates rules
COL_TEXT        equ 0x00C0C8E0
COL_HUD_TITLE   equ 0x00FFEE40
COL_WIN         equ 0x0044EE66

;-----------------------------------------------------------------------------
; start
;-----------------------------------------------------------------------------
start:
        VBE_GAME_INIT
        ; Load persistent solve count once
        mov esi, hs_name_sd
        call hs_load
        mov [total_solves], eax
        call new_puzzle
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
        cmp al, 'r'
        je .restart
        cmp al, 'R'
        je .restart

        ; Once won, only R/Q/ESC respond
        cmp dword [won_flag], 1
        je .no_key

        cmp al, 'h'
        je .hint
        cmp al, 'H'
        je .hint
        cmp al, KEY_UP
        je .cur_up
        cmp al, KEY_DOWN
        je .cur_down
        cmp al, KEY_LEFT
        je .cur_left
        cmp al, KEY_RIGHT
        je .cur_right
        cmp al, '0'
        je .clear_cell
        cmp al, KEY_SPACE
        je .clear_cell
        cmp al, '1'
        jl .no_key
        cmp al, '9'
        jg .no_key
        ; Digit 1..9
        movzx ebx, al
        sub ebx, '0'
        call place_digit
        call audio_sfx_click
        call check_win
        jmp .redraw

.cur_up:
        cmp dword [cur_row], 0
        je .no_key
        dec dword [cur_row]
        jmp .redraw
.cur_down:
        cmp dword [cur_row], 8
        jge .no_key
        inc dword [cur_row]
        jmp .redraw
.cur_left:
        cmp dword [cur_col], 0
        je .no_key
        dec dword [cur_col]
        jmp .redraw
.cur_right:
        cmp dword [cur_col], 8
        jge .no_key
        inc dword [cur_col]
        jmp .redraw

.clear_cell:
        xor ebx, ebx
        call place_digit
        call audio_sfx_click
        jmp .redraw

.hint:
        call apply_hint
        call audio_sfx_ok
        call check_win
        jmp .redraw

.restart:
        call new_puzzle
        jmp .redraw

.redraw:
        call draw_all
.no_key:
        mov eax, SYS_SLEEP
        mov ebx, 2
        int 0x80
        jmp .main_loop

.quit:
        mov eax, SYS_FRAMEBUF
        mov ebx, 2
        int 0x80
        xor eax, eax
        int 0x80


;-----------------------------------------------------------------------------
; place_digit  - write EBX (0..9) into [cur_row,cur_col] unless cell is given
;-----------------------------------------------------------------------------
place_digit:
        pushad
        mov eax, [cur_row]
        imul eax, 9
        add eax, [cur_col]
        cmp byte [given + eax], 0
        jne .pd_done
        mov [board + eax*4], ebx
.pd_done:
        popad
        ret

;-----------------------------------------------------------------------------
; apply_hint - copy one missing/wrong cell from the solution into the board
;-----------------------------------------------------------------------------
apply_hint:
        pushad
        ; Try cursor cell first
        mov eax, [cur_row]
        imul eax, 9
        add eax, [cur_col]
        cmp byte [given + eax], 0
        jne .ah_scan
        mov edx, [solution + eax*4]
        cmp [board + eax*4], edx
        je .ah_scan
        mov [board + eax*4], edx
        jmp .ah_done
.ah_scan:
        xor ecx, ecx
.ah_loop:
        cmp ecx, 81
        jge .ah_done
        cmp byte [given + ecx], 0
        jne .ah_next
        mov edx, [solution + ecx*4]
        cmp [board + ecx*4], edx
        je .ah_next
        mov [board + ecx*4], edx
        jmp .ah_done
.ah_next:
        inc ecx
        jmp .ah_loop
.ah_done:
        popad
        ret

;-----------------------------------------------------------------------------
; check_win - if board==solution and not yet won, bump solves + win SFX
;-----------------------------------------------------------------------------
check_win:
        pushad
        cmp dword [won_flag], 1
        je .cw_done
        xor ecx, ecx
.cw_loop:
        cmp ecx, 81
        jge .cw_match
        mov eax, [board + ecx*4]
        cmp eax, [solution + ecx*4]
        jne .cw_done
        inc ecx
        jmp .cw_loop
.cw_match:
        mov dword [won_flag], 1
        inc dword [total_solves]
        mov esi, hs_name_sd
        mov ebx, [total_solves]
        call hs_save
        call audio_sfx_win
.cw_done:
        popad
        ret

;-----------------------------------------------------------------------------
; new_puzzle - cycle through hardcoded puzzles based on system time
;-----------------------------------------------------------------------------
new_puzzle:
        pushad
        mov dword [won_flag], 0
        mov dword [cur_row], 0
        mov dword [cur_col], 0

        ; Pick puzzle index 0..NUM_PUZZLES-1 from low bits of time
        mov eax, SYS_GETTIME
        int 0x80
        xor edx, edx
        mov ebx, NUM_PUZZLES
        div ebx                         ; edx = idx
        mov eax, edx
        ; offset = idx * 81
        mov ebx, 81
        mul ebx
        mov esi, eax                    ; esi = byte offset into puzzle tables

        ; Copy puzzle into board / given / solution
        xor ecx, ecx
.np_loop:
        cmp ecx, 81
        jge .np_done
        movzx eax, byte [puzzles + esi + ecx]
        mov [board + ecx*4], eax
        ; given byte = 1 if puzzle clue is non-zero, else 0
        test eax, eax
        setnz dl
        mov [given + ecx], dl
        movzx eax, byte [solutions + esi + ecx]
        mov [solution + ecx*4], eax
        inc ecx
        jmp .np_loop
.np_done:
        popad
        ret

;-----------------------------------------------------------------------------
; cell_violates  EBX=row ECX=col -> EAX=1 if value at (row,col) breaks
; row/col/box uniqueness, else EAX=0 (only meaningful for non-zero cells).
; Preserves all other registers.
;-----------------------------------------------------------------------------
cell_violates:
        push ebp
        push ebx
        push ecx
        push edx
        push esi
        push edi
        ; index = row*9 + col
        mov eax, ebx
        imul eax, 9
        add eax, ecx
        mov ebp, eax                    ; ebp = self index
        mov esi, [board + eax*4]        ; esi = our value (1..9)
        test esi, esi
        jz .cv_clean

        ; --- Row scan ---
        mov eax, ebx
        imul eax, 9
        mov edi, eax                    ; edi = base index for row
        xor edx, edx
.cv_row:
        cmp edx, 9
        jge .cv_col_init
        mov eax, edi
        add eax, edx
        cmp eax, ebp
        je .cv_row_n
        cmp [board + eax*4], esi
        je .cv_dirty
.cv_row_n:
        inc edx
        jmp .cv_row

.cv_col_init:
        ; --- Column scan ---
        xor edx, edx
.cv_col:
        cmp edx, 9
        jge .cv_box_init
        mov eax, edx
        imul eax, 9
        add eax, ecx
        cmp eax, ebp
        je .cv_col_n
        cmp [board + eax*4], esi
        je .cv_dirty
.cv_col_n:
        inc edx
        jmp .cv_col

.cv_box_init:
        ; --- 3x3 Box scan ---
        ; box_row_start = (row/3)*3,  box_col_start = (col/3)*3
        mov eax, ebx
        xor edx, edx
        mov edi, 3
        div edi
        imul eax, 3
        mov edi, eax                    ; edi = box_row_start
        mov eax, ecx
        xor edx, edx
        mov ecx, 3
        div ecx
        imul eax, 3                     ; eax = box_col_start
        ; iterate r in [edi..edi+2], c in [eax..eax+2]
        mov ebx, edi                    ; ebx = current row
.cv_box_r:
        mov edx, edi
        add edx, 3
        cmp ebx, edx
        jge .cv_clean
        mov ecx, eax                    ; current col
.cv_box_c:
        mov edx, eax
        add edx, 3
        cmp ecx, edx
        jge .cv_box_r_n
        ; idx = ebx*9 + ecx
        push eax
        mov eax, ebx
        imul eax, 9
        add eax, ecx
        cmp eax, ebp
        je .cv_box_skip
        cmp [board + eax*4], esi
        je .cv_dirty_pop
.cv_box_skip:
        pop eax
        inc ecx
        jmp .cv_box_c
.cv_box_r_n:
        inc ebx
        jmp .cv_box_r

.cv_dirty_pop:
        pop eax
.cv_dirty:
        pop edi
        pop esi
        pop edx
        pop ecx
        pop ebx
        pop ebp
        mov eax, 1
        ret

.cv_clean:
        pop edi
        pop esi
        pop edx
        pop ecx
        pop ebx
        pop ebp
        xor eax, eax
        ret

;-----------------------------------------------------------------------------
; draw_all
;-----------------------------------------------------------------------------
draw_all:
        pushad
        mov edx, COL_BG
        call vbe_clear_screen

        ; Title
        mov ebx, GRID_X
        mov ecx, 24
        mov edx, str_title
        mov esi, COL_HUD_TITLE
        mov eax, 3
        call vbe_draw_str

        call draw_grid
        call draw_digits
        call draw_cursor
        call draw_hud
        cmp dword [won_flag], 1
        jne .da_done
        call draw_win_banner
.da_done:
        VBE_GAME_PRESENT
        popad
        ret

;-----------------------------------------------------------------------------
; draw_grid - background cells + lines (heavy lines every 3)
;-----------------------------------------------------------------------------
draw_grid:
        pushad
        ; Cell backgrounds with alt-tint per 3x3 block
        xor ecx, ecx                    ; row
.dg_r:
        cmp ecx, 9
        jge .dg_lines
        xor edx, edx                    ; col
.dg_c:
        cmp edx, 9
        jge .dg_r_next

        ; pick color: alt tint when ((row/3)+(col/3)) is odd
        mov eax, ecx
        push edx
        xor edx, edx
        mov edi, 3
        div edi
        mov ebx, eax                    ; row/3
        pop edx
        push ecx
        mov eax, edx
        xor ecx, ecx
        mov edi, 3
        push edx
        xor edx, edx
        div edi
        pop edx
        add ebx, eax
        and ebx, 1
        pop ecx
        mov edi, COL_CELL
        test ebx, ebx
        jz .dg_paint
        mov edi, COL_CELL_ALT
.dg_paint:
        ; fill rect at (GRID_X + col*CELL_SZ, GRID_Y + row*CELL_SZ)
        mov eax, edx
        imul eax, CELL_SZ
        add eax, GRID_X
        mov ebx, eax                    ; ebx = x
        mov eax, ecx
        imul eax, CELL_SZ
        add eax, GRID_Y
        push ecx
        push edx
        mov ecx, eax                    ; ecx = y
        mov edx, CELL_SZ                ; w
        mov esi, CELL_SZ                ; h
        ; edi = colour already
        call vbe_fill_rect
        pop edx
        pop ecx
        inc edx
        jmp .dg_c
.dg_r_next:
        inc ecx
        jmp .dg_r

.dg_lines:
        ; Thin lines: draw a 2px tall/wide rect on every cell boundary
        ; Vertical lines at i=0..9
        xor ecx, ecx
.dg_vl:
        cmp ecx, 10
        jg .dg_hl
        mov eax, ecx
        imul eax, CELL_SZ
        add eax, GRID_X
        mov ebx, eax                    ; x
        mov edi, COL_GRID_LIGHT
        mov edx, ecx
        xor edx, edx
        mov edx, ecx
        ; if ecx % 3 == 0 use heavy
        mov eax, ecx
        xor edx, edx
        mov esi, 3
        div esi
        test edx, edx
        jnz .dg_vl_thin
        mov edi, COL_GRID_HEAVY
        sub ebx, 1                      ; thicker line
.dg_vl_thin:
        push ecx
        mov ecx, GRID_Y
        mov edx, 3
        ; if heavy, width=3 already; else 2
        cmp edi, COL_GRID_HEAVY
        je .dg_vl_w
        mov edx, 2
.dg_vl_w:
        mov esi, CELL_SZ * 9
        call vbe_fill_rect
        pop ecx
        inc ecx
        jmp .dg_vl

.dg_hl:
        xor ecx, ecx
.dg_hl_loop:
        cmp ecx, 10
        jg .dg_done
        mov eax, ecx
        imul eax, CELL_SZ
        add eax, GRID_Y
        mov edi, COL_GRID_LIGHT
        mov eax, ecx
        xor edx, edx
        mov esi, 3
        div esi
        test edx, edx
        jnz .dg_hl_thin
        mov edi, COL_GRID_HEAVY
.dg_hl_thin:
        mov eax, ecx
        imul eax, CELL_SZ
        add eax, GRID_Y
        push ecx
        mov ebx, GRID_X
        mov ecx, eax
        cmp edi, COL_GRID_HEAVY
        jne .dg_hl_thin_w
        sub ecx, 1
        mov edx, CELL_SZ * 9
        mov esi, 3
        jmp .dg_hl_paint
.dg_hl_thin_w:
        mov edx, CELL_SZ * 9
        mov esi, 2
.dg_hl_paint:
        call vbe_fill_rect
        pop ecx
        inc ecx
        jmp .dg_hl_loop

.dg_done:
        popad
        ret

;-----------------------------------------------------------------------------
; draw_digits - render board values
;-----------------------------------------------------------------------------
draw_digits:
        pushad
        xor ecx, ecx                    ; row
.dd_r:
        cmp ecx, 9
        jge .dd_done
        xor edx, edx                    ; col
.dd_c:
        cmp edx, 9
        jge .dd_r_next
        mov eax, ecx
        imul eax, 9
        add eax, edx                    ; eax = idx
        mov edi, [board + eax*4]
        test edi, edi
        jz .dd_n
        ; Determine colour
        movzx esi, byte [given + eax]
        test esi, esi
        jnz .dd_g
        ; user cell — check for conflict
        push edi                        ; save digit
        push ebx
        push ecx
        push edx
        mov ebx, ecx
        ; cell_violates expects EBX=row, ECX=col, returns EAX=1 if conflict
        mov ecx, edx
        call cell_violates
        mov ebp, eax                    ; ebp = conflict flag (scratch)
        pop edx
        pop ecx
        pop ebx
        pop edi                         ; restore digit
        test ebp, ebp
        jz .dd_user_ok
        mov esi, COL_CONFLICT
        jmp .dd_paint
.dd_user_ok:
        mov esi, COL_USER
        jmp .dd_paint
.dd_g:
        mov esi, COL_GIVEN
.dd_paint:
        ; pos = (GRID_X + col*CELL_SZ + 22, GRID_Y + row*CELL_SZ + 18)
        mov eax, edx
        imul eax, CELL_SZ
        add eax, GRID_X
        add eax, 22
        push ebx
        mov ebx, eax
        mov eax, ecx
        imul eax, CELL_SZ
        add eax, GRID_Y
        add eax, 16
        push ecx
        mov ecx, eax
        push edx
        ; digit char value = '0' + edi
        mov edx, edi
        add edx, '0'
        ; esi already colour
        mov eax, 3
        call vbe_draw_char
        pop edx
        pop ecx
        pop ebx
.dd_n:
        inc edx
        jmp .dd_c
.dd_r_next:
        inc ecx
        jmp .dd_r
.dd_done:
        popad
        ret

;-----------------------------------------------------------------------------
; draw_cursor - 4 px hollow border around current cell
;-----------------------------------------------------------------------------
draw_cursor:
        pushad
        mov eax, [cur_col]
        imul eax, CELL_SZ
        add eax, GRID_X
        mov ebx, eax
        mov eax, [cur_row]
        imul eax, CELL_SZ
        add eax, GRID_Y
        mov ecx, eax
        ; top edge
        push ecx
        push ebx
        mov edx, CELL_SZ
        mov esi, 4
        mov edi, COL_CURSOR
        call vbe_fill_rect
        pop ebx
        pop ecx
        ; bottom edge
        push ecx
        push ebx
        add ecx, CELL_SZ
        sub ecx, 4
        mov edx, CELL_SZ
        mov esi, 4
        mov edi, COL_CURSOR
        call vbe_fill_rect
        pop ebx
        pop ecx
        ; left edge
        push ecx
        push ebx
        mov edx, 4
        mov esi, CELL_SZ
        mov edi, COL_CURSOR
        call vbe_fill_rect
        pop ebx
        pop ecx
        ; right edge
        add ebx, CELL_SZ
        sub ebx, 4
        mov edx, 4
        mov esi, CELL_SZ
        mov edi, COL_CURSOR
        call vbe_fill_rect
        popad
        ret

;-----------------------------------------------------------------------------
; draw_hud - on-screen help + persistent solve count
;-----------------------------------------------------------------------------
draw_hud:
        pushad
        ; "SUDOKU" label
        mov ebx, HUD_X
        mov ecx, HUD_Y
        mov edx, str_solves
        mov esi, COL_HUD_TITLE
        mov eax, 2
        call vbe_draw_str

        mov ebx, HUD_X
        mov ecx, HUD_Y + 36
        mov edx, [total_solves]
        mov esi, COL_GIVEN
        mov eax, 3
        call vbe_draw_num

        ; Help block
        mov ebx, HUD_X
        mov ecx, HUD_Y + 110
        mov edx, str_help1
        mov esi, COL_TEXT
        mov eax, 1
        call vbe_draw_str
        mov ebx, HUD_X
        mov ecx, HUD_Y + 134
        mov edx, str_help2
        mov esi, COL_TEXT
        mov eax, 1
        call vbe_draw_str
        mov ebx, HUD_X
        mov ecx, HUD_Y + 158
        mov edx, str_help3
        mov esi, COL_TEXT
        mov eax, 1
        call vbe_draw_str
        mov ebx, HUD_X
        mov ecx, HUD_Y + 182
        mov edx, str_help4
        mov esi, COL_TEXT
        mov eax, 1
        call vbe_draw_str
        mov ebx, HUD_X
        mov ecx, HUD_Y + 206
        mov edx, str_help5
        mov esi, COL_TEXT
        mov eax, 1
        call vbe_draw_str
        popad
        ret

;-----------------------------------------------------------------------------
; draw_win_banner
;-----------------------------------------------------------------------------
draw_win_banner:
        pushad
        mov ebx, GRID_X
        mov ecx, GRID_Y + CELL_SZ * 9 + 18
        mov edx, str_win
        mov esi, COL_WIN
        mov eax, 3
        call vbe_draw_str
        popad
        ret

;-----------------------------------------------------------------------------
; Data
;-----------------------------------------------------------------------------

NUM_PUZZLES     equ 4

str_title       db "SUDOKU", 0
str_solves      db "SOLVES", 0
str_win         db "SOLVED!  R = NEW PUZZLE", 0
str_help1       db "ARROWS: MOVE", 0
str_help2       db "1-9: PLACE   0/SP: CLEAR", 0
str_help3       db "H: HINT      R: NEW PUZZLE", 0
str_help4       db "RED = RULE CONFLICT", 0
str_help5       db "ESC / Q: QUIT", 0

hs_name_sd      db "sudoku", 0

; --- Puzzle bank: 4 puzzles, 81 bytes each (0 = blank) ---
puzzles:
; #1 (easy)
        db 5,3,0, 0,7,0, 0,0,0
        db 6,0,0, 1,9,5, 0,0,0
        db 0,9,8, 0,0,0, 0,6,0
        db 8,0,0, 0,6,0, 0,0,3
        db 4,0,0, 8,0,3, 0,0,1
        db 7,0,0, 0,2,0, 0,0,6
        db 0,6,0, 0,0,0, 2,8,0
        db 0,0,0, 4,1,9, 0,0,5
        db 0,0,0, 0,8,0, 0,7,9
; #2 (medium)
        db 0,0,0, 2,6,0, 7,0,1
        db 6,8,0, 0,7,0, 0,9,0
        db 1,9,0, 0,0,4, 5,0,0
        db 8,2,0, 1,0,0, 0,4,0
        db 0,0,4, 6,0,2, 9,0,0
        db 0,5,0, 0,0,3, 0,2,8
        db 0,0,9, 3,0,0, 0,7,4
        db 0,4,0, 0,5,0, 0,3,6
        db 7,0,3, 0,1,8, 0,0,0
; #3 (medium)
        db 1,0,0, 4,8,9, 0,0,6
        db 7,3,0, 0,0,0, 0,4,0
        db 0,0,0, 0,0,1, 2,9,5
        db 0,0,7, 1,2,0, 6,0,0
        db 5,0,0, 7,0,3, 0,0,8
        db 0,0,6, 0,9,5, 7,0,0
        db 9,1,4, 6,0,0, 0,0,0
        db 0,2,0, 0,0,0, 0,3,7
        db 8,0,0, 5,1,2, 0,0,4
; #4 (harder)
        db 0,0,0, 6,0,0, 4,0,0
        db 7,0,0, 0,0,3, 6,0,0
        db 0,0,0, 0,9,1, 0,8,0
        db 0,0,0, 0,0,0, 0,0,0
        db 0,5,0, 1,8,0, 0,0,3
        db 0,0,0, 3,0,6, 0,4,5
        db 0,4,0, 2,0,0, 0,6,0
        db 9,0,3, 0,0,0, 0,0,0
        db 0,2,0, 0,0,0, 1,0,0

solutions:
; #1
        db 5,3,4, 6,7,8, 9,1,2
        db 6,7,2, 1,9,5, 3,4,8
        db 1,9,8, 3,4,2, 5,6,7
        db 8,5,9, 7,6,1, 4,2,3
        db 4,2,6, 8,5,3, 7,9,1
        db 7,1,3, 9,2,4, 8,5,6
        db 9,6,1, 5,3,7, 2,8,4
        db 2,8,7, 4,1,9, 6,3,5
        db 3,4,5, 2,8,6, 1,7,9
; #2
        db 4,3,5, 2,6,9, 7,8,1
        db 6,8,2, 5,7,1, 4,9,3
        db 1,9,7, 8,3,4, 5,6,2
        db 8,2,6, 1,9,5, 3,4,7
        db 3,7,4, 6,8,2, 9,1,5
        db 9,5,1, 7,4,3, 6,2,8
        db 5,1,9, 3,2,6, 8,7,4
        db 2,4,8, 9,5,7, 1,3,6
        db 7,6,3, 4,1,8, 2,5,9
; #3
        db 1,5,2, 4,8,9, 3,7,6
        db 7,3,9, 2,5,6, 8,4,1
        db 4,6,8, 3,7,1, 2,9,5
        db 3,8,7, 1,2,4, 6,5,9
        db 5,9,1, 7,6,3, 4,2,8
        db 2,4,6, 8,9,5, 7,1,3
        db 9,1,4, 6,3,7, 5,8,2
        db 6,2,5, 9,4,8, 1,3,7
        db 8,7,3, 5,1,2, 9,6,4
; #4
        db 5,8,1, 6,7,2, 4,3,9
        db 7,9,2, 8,4,3, 6,5,1
        db 3,6,4, 5,9,1, 7,8,2
        db 4,3,8, 9,5,7, 2,1,6
        db 2,5,6, 1,8,4, 9,7,3
        db 1,7,9, 3,2,6, 8,4,5
        db 8,4,5, 2,1,9, 3,6,7
        db 9,1,3, 7,6,8, 5,2,4
        db 6,2,7, 4,3,5, 1,9,8

; --- Mutable state (initialized at runtime) ---
board:          times 81 dd 0
solution:       times 81 dd 0
given:          times 81 db 0
cur_row:        dd 0
cur_col:        dd 0
won_flag:       dd 0
total_solves:   dd 0
