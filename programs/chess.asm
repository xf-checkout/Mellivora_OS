; chess.asm - Chess for Mellivora OS
; VBE 1024x768. Type move in e2e4 format, N=new game, ESC=quit.
%include "syscalls.inc"
%include "lib/vbe_game.inc"
%include "lib/font.inc"

; Board layout
CELL_SZ     equ 80
BOARD_X     equ 192
BOARD_Y     equ 64

; Piece constants
EMPTY       equ 0
PAWN        equ 1
KNIGHT      equ 2
BISHOP      equ 3
ROOK        equ 4
QUEEN       equ 5
KING        equ 6
WHITE       equ 0x10
BLACK       equ 0x20
COLOR_MASK  equ 0xF0
PIECE_MASK  equ 0x0F

; Colors
COL_LIGHT_SQ     equ 0x00D4A96A
COL_DARK_SQ      equ 0x00805030
COL_WHITE_PIECE  equ 0x00EEEECC
COL_BLACK_PIECE  equ 0x00222244

start:
        VBE_GAME_INIT
        call init_board
        call draw_board

.main_loop:
        VBE_GAME_POLL_KEY
        cmp eax, -1
        je .poll_wait

        ; Normalize uppercase letters to lowercase
        cmp al, 'A'
        jl .not_upper
        cmp al, 'Z'
        jg .not_upper
        or al, 0x20
.not_upper:
        cmp al, 'q'
        je .do_quit
        cmp al, 'Q'
        je .do_quit
        cmp al, KEY_ESC
        je .do_quit
        cmp al, 'n'
        je .do_new
        cmp al, 0x08        ; BKSP
        je .do_bksp

        ; Accept valid input char based on position
        movzx ecx, byte [input_len]
        cmp ecx, 4
        jge .main_loop

        test ecx, 1
        jz .expect_file
        ; Odd position: expect rank digit 1-8
        cmp al, '1'
        jl .main_loop
        cmp al, '8'
        jg .main_loop
        jmp .store_char
.expect_file:
        ; Even position: expect file letter a-h
        cmp al, 'a'
        jl .main_loop
        cmp al, 'h'
        jg .main_loop

.store_char:
        movzx ecx, byte [input_len]
        mov [input_buf + ecx], al
        cmp ecx, 0
        jne .no_err_clear
        mov byte [input_err], 0
.no_err_clear:
        inc byte [input_len]
        cmp byte [input_len], 4
        jl .do_redraw
        ; Try to execute move
        mov esi, input_buf
        call parse_move
        test eax, eax
        jnz .pm_err
        call validate_move
        test eax, eax
        jnz .vm_err
        call make_move
        xor byte [turn], 1
        mov byte [input_len], 0
        mov byte [input_err], 0
        call draw_board
        jmp .main_loop
.pm_err:
        mov byte [input_err], 1
        mov byte [input_len], 0
        call draw_board
        jmp .main_loop
.vm_err:
        mov byte [input_err], 2
        mov byte [input_len], 0
        call draw_board
        jmp .main_loop

.do_bksp:
        cmp byte [input_len], 0
        je .main_loop
        dec byte [input_len]
        mov byte [input_err], 0
.do_redraw:
        call draw_board
        jmp .main_loop

.do_new:
        call init_board
        mov byte [input_len], 0
        mov byte [input_err], 0
        call draw_board
        jmp .main_loop

.poll_wait:
        mov eax, SYS_SLEEP
        mov ebx, 2
        int 0x80
        jmp .main_loop

.do_quit:
        mov eax, SYS_FRAMEBUF
        mov ebx, 2
        int 0x80
        xor eax, eax
        int 0x80

;=======================================
; init_board - Set up starting position
;=======================================
init_board:
        pushad
        ; Clear board
        mov edi, board
        mov ecx, 64
        xor al, al
        rep stosb

        ; Rank 1 (row 0): white pieces
        mov byte [board + 0], WHITE | ROOK
        mov byte [board + 1], WHITE | KNIGHT
        mov byte [board + 2], WHITE | BISHOP
        mov byte [board + 3], WHITE | QUEEN
        mov byte [board + 4], WHITE | KING
        mov byte [board + 5], WHITE | BISHOP
        mov byte [board + 6], WHITE | KNIGHT
        mov byte [board + 7], WHITE | ROOK

        ; Rank 2: white pawns
        mov ecx, 8
        lea edi, [board + 8]
.wp:    mov byte [edi], WHITE | PAWN
        inc edi
        loop .wp

        ; Rank 7: black pawns
        mov ecx, 8
        lea edi, [board + 48]
.bp:    mov byte [edi], BLACK | PAWN
        inc edi
        loop .bp

        ; Rank 8 (row 7): black pieces
        mov byte [board + 56], BLACK | ROOK
        mov byte [board + 57], BLACK | KNIGHT
        mov byte [board + 58], BLACK | BISHOP
        mov byte [board + 59], BLACK | QUEEN
        mov byte [board + 60], BLACK | KING
        mov byte [board + 61], BLACK | BISHOP
        mov byte [board + 62], BLACK | KNIGHT
        mov byte [board + 63], BLACK | ROOK

        mov byte [turn], 0     ; White starts
        mov dword [move_count], 0

        popad
        ret

;=======================================
; draw_board - Display the chess board
;=======================================
draw_board:
        pushad

        mov edx, 0x00222222
        call vbe_clear_screen

        ; Title
        mov ebx, 330
        mov ecx, 10
        mov edx, title_str
        mov esi, 0x00EEEECC
        mov eax, 2
        call vbe_draw_str

        ; Draw board squares and pieces
        mov dword [.dbr], 0
.db_sqrow:
        cmp dword [.dbr], 8
        jge .db_sq_done
        mov dword [.dbc], 0
.db_sqcol:
        cmp dword [.dbc], 8
        jge .db_sqnr

        ; Square color: (dbr+dbc) even=dark, odd=light
        mov eax, [.dbr]
        add eax, [.dbc]
        and eax, 1
        jz .db_dark_sq
        mov edi, COL_LIGHT_SQ
        jmp .db_draw_sq
.db_dark_sq:
        mov edi, COL_DARK_SQ
.db_draw_sq:
        ; x = dbc*CELL_SZ + BOARD_X
        mov ebx, [.dbc]
        imul ebx, CELL_SZ
        add ebx, BOARD_X
        ; y = (7-dbr)*CELL_SZ + BOARD_Y  (rank 8 at top)
        mov eax, 7
        sub eax, [.dbr]
        imul eax, CELL_SZ
        add eax, BOARD_Y
        mov ecx, eax
        mov edx, CELL_SZ
        mov esi, CELL_SZ
        call vbe_fill_rect

        ; Draw piece if present
        mov eax, [.dbr]
        imul eax, 8
        add eax, [.dbc]
        movzx eax, byte [board + eax]
        test eax, eax
        jz .db_nopce

        ; Decode piece type and color
        mov ebx, eax
        and ebx, PIECE_MASK
        dec ebx
        movzx edx, byte [piece_chars + ebx]   ; piece char
        mov ebx, eax
        and ebx, COLOR_MASK
        cmp ebx, WHITE
        jne .db_blk_pce
        mov esi, COL_WHITE_PIECE
        jmp .db_drw_pce
.db_blk_pce:
        mov esi, COL_BLACK_PIECE
.db_drw_pce:
        ; Center piece char (scale=2: 10x14px) in cell
        mov ebx, [.dbc]
        imul ebx, CELL_SZ
        add ebx, BOARD_X + (CELL_SZ - 10) / 2
        mov eax, 7
        sub eax, [.dbr]
        imul eax, CELL_SZ
        add eax, BOARD_Y + (CELL_SZ - 14) / 2
        mov ecx, eax
        mov eax, 2
        call vbe_draw_char
.db_nopce:
        inc dword [.dbc]
        jmp .db_sqcol
.db_sqnr:
        inc dword [.dbr]
        jmp .db_sqrow

.db_sq_done:
        ; Rank labels 1-8 (left of board)
        mov dword [.dbr], 0
.db_rklbl:
        cmp dword [.dbr], 8
        jge .db_rk_done
        mov eax, 7
        sub eax, [.dbr]
        imul eax, CELL_SZ
        add eax, BOARD_Y + (CELL_SZ - 14) / 2
        mov ecx, eax
        mov ebx, BOARD_X - 22
        mov eax, [.dbr]
        add eax, '1'
        mov edx, eax
        mov esi, 0x00CCCCCC
        mov eax, 2
        call vbe_draw_char
        inc dword [.dbr]
        jmp .db_rklbl
.db_rk_done:

        ; File labels A-H (below board)
        mov dword [.dbc], 0
.db_fllbl:
        cmp dword [.dbc], 8
        jge .db_fl_done
        mov eax, [.dbc]
        imul eax, CELL_SZ
        add eax, BOARD_X + (CELL_SZ - 10) / 2
        mov ebx, eax
        mov ecx, BOARD_Y + 8 * CELL_SZ + 8
        mov eax, [.dbc]
        add eax, 'A'
        mov edx, eax
        mov esi, 0x00CCCCCC
        mov eax, 2
        call vbe_draw_char
        inc dword [.dbc]
        jmp .db_fllbl
.db_fl_done:

        ; Right info panel: turn indicator
        cmp byte [turn], 0
        jne .db_black_turn
        mov edx, str_white_move
        jmp .db_show_turn
.db_black_turn:
        mov edx, str_black_move
.db_show_turn:
        mov ebx, BOARD_X + 8 * CELL_SZ + 20
        mov ecx, BOARD_Y + 20
        mov esi, 0x00EEEECC
        mov eax, 2
        call vbe_draw_str

        ; Input label
        mov ebx, BOARD_X + 8 * CELL_SZ + 20
        mov ecx, BOARD_Y + 80
        mov edx, str_input
        mov esi, 0x00AAAAAA
        mov eax, 2
        call vbe_draw_str

        ; Show typed chars (or _ for untyped)
        mov dword [.dbc], 0
.db_inpch:
        cmp dword [.dbc], 4
        jge .db_inp_done
        movzx eax, byte [input_len]
        cmp dword [.dbc], eax
        jl .db_inp_typed
        mov edx, '_'
        jmp .db_inp_show
.db_inp_typed:
        mov eax, [.dbc]
        movzx edx, byte [input_buf + eax]
        cmp dl, 'a'
        jl .db_inp_show
        sub dl, 0x20            ; uppercase
.db_inp_show:
        mov eax, [.dbc]
        imul eax, 16
        add eax, BOARD_X + 8 * CELL_SZ + 20
        mov ebx, eax
        mov ecx, BOARD_Y + 120
        mov esi, 0x00FFFF44
        mov eax, 2
        call vbe_draw_char
        inc dword [.dbc]
        jmp .db_inpch
.db_inp_done:

        ; Error message
        cmp byte [input_err], 0
        je .db_no_err
        cmp byte [input_err], 1
        je .db_fmt_err
        mov edx, str_illegal
        jmp .db_show_err
.db_fmt_err:
        mov edx, str_invalid
.db_show_err:
        mov ebx, BOARD_X + 8 * CELL_SZ + 20
        mov ecx, BOARD_Y + 160
        mov esi, 0x00FF4444
        mov eax, 2
        call vbe_draw_str
.db_no_err:

        ; Controls hint
        mov ebx, 40
        mov ecx, 740
        mov edx, str_hint
        mov esi, 0x00778888
        mov eax, 1
        call vbe_draw_str

        VBE_GAME_PRESENT
        popad
        ret

.dbr:   dd 0
.dbc:   dd 0

;=======================================
; parse_move: ESI=input -> sets from/to, EAX=0 ok
;=======================================
parse_move:
        push ebx
        push ecx

        ; Expected format: a-h digit a-h digit (4 chars)
        movzx eax, byte [esi]
        sub al, 'a'
        cmp al, 7
        ja .pm_err
        mov [from_col], eax

        movzx eax, byte [esi + 1]
        sub al, '1'
        cmp al, 7
        ja .pm_err
        mov [from_row], eax

        movzx eax, byte [esi + 2]
        sub al, 'a'
        cmp al, 7
        ja .pm_err
        mov [to_col], eax

        movzx eax, byte [esi + 3]
        sub al, '1'
        cmp al, 7
        ja .pm_err
        mov [to_row], eax

        xor eax, eax
        pop ecx
        pop ebx
        ret
.pm_err:
        mov eax, 1
        pop ecx
        pop ebx
        ret

;=======================================
; validate_move - Check if move is legal, EAX=0 ok
;=======================================
validate_move:
        pushad

        ; Get source piece
        mov eax, [from_row]
        imul eax, 8
        add eax, [from_col]
        movzx ebx, byte [board + eax]

        ; Must have a piece
        test ebx, ebx
        jz .vm_illegal

        ; Must be current player's piece
        mov ecx, ebx
        and ecx, COLOR_MASK
        cmp byte [turn], 0
        jne .vm_check_black
        cmp ecx, WHITE
        jne .vm_illegal
        jmp .vm_check_dest
.vm_check_black:
        cmp ecx, BLACK
        jne .vm_illegal

.vm_check_dest:
        ; Destination must not have own piece
        mov eax, [to_row]
        imul eax, 8
        add eax, [to_col]
        movzx edx, byte [board + eax]
        test edx, edx
        jz .vm_dest_ok
        mov eax, edx
        and eax, COLOR_MASK
        cmp eax, ecx            ; same color?
        je .vm_illegal

.vm_dest_ok:
        ; Basic piece movement validation
        mov eax, ebx
        and eax, PIECE_MASK

        cmp eax, PAWN
        je .vm_pawn
        cmp eax, KNIGHT
        je .vm_knight
        cmp eax, BISHOP
        je .vm_bishop
        cmp eax, ROOK
        je .vm_rook
        cmp eax, QUEEN
        je .vm_queen
        cmp eax, KING
        je .vm_king
        jmp .vm_illegal

.vm_pawn:
        ; Direction based on color
        mov eax, [to_col]
        sub eax, [from_col]
        mov ecx, [to_row]
        sub ecx, [from_row]

        mov edx, ebx
        and edx, COLOR_MASK
        cmp edx, WHITE
        jne .vm_pawn_black

        ; White pawn: forward = +row
        cmp eax, 0              ; straight
        jne .vm_pawn_capture
        cmp ecx, 1
        je .vm_pawn_forward_ok
        ; Double move from rank 2
        cmp dword [from_row], 1
        jne .vm_illegal
        cmp ecx, 2
        jne .vm_illegal
        ; Check intermediate square empty
        push ebx
        mov eax, [from_row]
        inc eax
        imul eax, 8
        add eax, [from_col]
        cmp byte [board + eax], 0
        pop ebx
        jne .vm_illegal
.vm_pawn_forward_ok:
        ; Destination must be empty for forward move
        mov eax, [to_row]
        imul eax, 8
        add eax, [to_col]
        cmp byte [board + eax], 0
        jne .vm_illegal
        jmp .vm_legal

.vm_pawn_capture:
        ; Must move diagonally by 1
        cmp ecx, 1
        jne .vm_illegal
        cmp eax, 1
        je .vm_pawn_cap_ok
        cmp eax, -1
        jne .vm_illegal
.vm_pawn_cap_ok:
        ; Must have enemy piece at destination
        push ebx
        mov eax, [to_row]
        imul eax, 8
        add eax, [to_col]
        movzx ebx, byte [board + eax]
        test ebx, ebx
        pop ebx
        jz .vm_illegal
        jmp .vm_legal

.vm_pawn_black:
        ; Black pawn: forward = -row
        cmp eax, 0
        jne .vm_bpawn_capture
        cmp ecx, -1
        je .vm_bpawn_forward_ok
        cmp dword [from_row], 6
        jne .vm_illegal
        cmp ecx, -2
        jne .vm_illegal
        push ebx
        mov eax, [from_row]
        dec eax
        imul eax, 8
        add eax, [from_col]
        cmp byte [board + eax], 0
        pop ebx
        jne .vm_illegal
.vm_bpawn_forward_ok:
        mov eax, [to_row]
        imul eax, 8
        add eax, [to_col]
        cmp byte [board + eax], 0
        jne .vm_illegal
        jmp .vm_legal

.vm_bpawn_capture:
        cmp ecx, -1
        jne .vm_illegal
        cmp eax, 1
        je .vm_bpc_ok
        cmp eax, -1
        jne .vm_illegal
.vm_bpc_ok:
        push ebx
        mov eax, [to_row]
        imul eax, 8
        add eax, [to_col]
        movzx ebx, byte [board + eax]
        test ebx, ebx
        pop ebx
        jz .vm_illegal
        jmp .vm_legal

.vm_knight:
        mov eax, [to_col]
        sub eax, [from_col]
        ; abs
        test eax, eax
        jns .vk_abs1
        neg eax
.vk_abs1:
        mov ecx, [to_row]
        sub ecx, [from_row]
        test ecx, ecx
        jns .vk_abs2
        neg ecx
.vk_abs2:
        ; L-shape: (1,2) or (2,1)
        cmp eax, 1
        jne .vk_try2
        cmp ecx, 2
        je .vm_legal
        jmp .vm_illegal
.vk_try2:
        cmp eax, 2
        jne .vm_illegal
        cmp ecx, 1
        je .vm_legal
        jmp .vm_illegal

.vm_bishop:
        call check_diagonal
        test eax, eax
        jz .vm_legal
        jmp .vm_illegal

.vm_rook:
        call check_straight
        test eax, eax
        jz .vm_legal
        jmp .vm_illegal

.vm_queen:
        call check_straight
        test eax, eax
        jz .vm_legal
        call check_diagonal
        test eax, eax
        jz .vm_legal
        jmp .vm_illegal

.vm_king:
        mov eax, [to_col]
        sub eax, [from_col]
        test eax, eax
        jns .vki_abs1
        neg eax
.vki_abs1:
        mov ecx, [to_row]
        sub ecx, [from_row]
        test ecx, ecx
        jns .vki_abs2
        neg ecx
.vki_abs2:
        cmp eax, 1
        jg .vm_illegal
        cmp ecx, 1
        jg .vm_illegal
        jmp .vm_legal

.vm_legal:
        popad
        xor eax, eax
        ret
.vm_illegal:
        popad
        mov eax, 1
        ret

;---------------------------------------
; check_straight: returns EAX=0 if valid straight line move with clear path
;---------------------------------------
check_straight:
        push ebx
        push ecx
        push edx
        push esi

        mov eax, [to_col]
        sub eax, [from_col]
        mov ecx, [to_row]
        sub ecx, [from_row]

        ; Must be on same rank or file
        test eax, eax
        jnz .cs_check_file
        test ecx, ecx
        jz .cs_fail             ; no movement
        jmp .cs_setup
.cs_check_file:
        test ecx, ecx
        jnz .cs_fail            ; diagonal, not straight

.cs_setup:
        ; Normalize to step (-1, 0, +1)
        mov edx, eax
        test edx, edx
        jz .cs_dx_done
        jns .cs_dx_pos
        mov edx, -1
        jmp .cs_dx_done
.cs_dx_pos:
        mov edx, 1
.cs_dx_done:
        mov esi, ecx
        test esi, esi
        jz .cs_dy_done
        jns .cs_dy_pos
        mov esi, -1
        jmp .cs_dy_done
.cs_dy_pos:
        mov esi, 1
.cs_dy_done:
        ; Walk from (from+step) to (to-step), checking empty
        mov eax, [from_col]
        mov ecx, [from_row]
        add eax, edx
        add ecx, esi
.cs_walk:
        cmp eax, [to_col]
        jne .cs_check_sq
        cmp ecx, [to_row]
        jne .cs_check_sq
        ; Reached destination
        xor eax, eax
        jmp .cs_ret
.cs_check_sq:
        push eax
        push ecx
        imul ecx, 8
        add ecx, eax
        cmp byte [board + ecx], 0
        pop ecx
        pop eax
        jnz .cs_fail
        add eax, edx
        add ecx, esi
        jmp .cs_walk

.cs_fail:
        mov eax, 1
.cs_ret:
        pop esi
        pop edx
        pop ecx
        pop ebx
        ret

;---------------------------------------
; check_diagonal: returns EAX=0 if valid diagonal with clear path
;---------------------------------------
check_diagonal:
        push ebx
        push ecx
        push edx
        push esi

        mov eax, [to_col]
        sub eax, [from_col]    ; dx
        mov ecx, [to_row]
        sub ecx, [from_row]    ; dy

        ; Must have |dx| == |dy|
        mov edx, eax
        test edx, edx
        jns .cd_abs1
        neg edx
.cd_abs1:
        mov esi, ecx
        test esi, esi
        jns .cd_abs2
        neg esi
.cd_abs2:
        cmp edx, esi
        jne .cd_fail
        test edx, edx
        jz .cd_fail

        ; Normalize steps
        mov edx, eax
        test edx, edx
        jns .cd_dx_pos
        mov edx, -1
        jmp .cd_dx_done
.cd_dx_pos:
        mov edx, 1
.cd_dx_done:
        mov esi, ecx
        test esi, esi
        jns .cd_dy_pos
        mov esi, -1
        jmp .cd_dy_done
.cd_dy_pos:
        mov esi, 1
.cd_dy_done:
        mov eax, [from_col]
        mov ecx, [from_row]
        add eax, edx
        add ecx, esi
.cd_walk:
        cmp eax, [to_col]
        jne .cd_check
        cmp ecx, [to_row]
        jne .cd_check
        xor eax, eax
        jmp .cd_ret
.cd_check:
        push eax
        push ecx
        imul ecx, 8
        add ecx, eax
        cmp byte [board + ecx], 0
        pop ecx
        pop eax
        jnz .cd_fail
        add eax, edx
        add ecx, esi
        jmp .cd_walk

.cd_fail:
        mov eax, 1
.cd_ret:
        pop esi
        pop edx
        pop ecx
        pop ebx
        ret

;=======================================
; make_move - Execute the move
;=======================================
make_move:
        pushad
        ; Get source
        mov eax, [from_row]
        imul eax, 8
        add eax, [from_col]
        movzx ebx, byte [board + eax]
        mov byte [board + eax], EMPTY

        ; Place at destination
        mov eax, [to_row]
        imul eax, 8
        add eax, [to_col]
        mov [board + eax], bl

        ; Pawn promotion (simple: auto-queen)
        mov ecx, ebx
        and ecx, PIECE_MASK
        cmp ecx, PAWN
        jne .mm_done
        mov ecx, ebx
        and ecx, COLOR_MASK
        cmp ecx, WHITE
        jne .mm_black_promo
        cmp dword [to_row], 7
        jne .mm_done
        mov byte [board + eax], WHITE | QUEEN
        jmp .mm_done
.mm_black_promo:
        cmp dword [to_row], 0
        jne .mm_done
        mov byte [board + eax], BLACK | QUEEN

.mm_done:
        inc dword [move_count]
        popad
        ret

; === Data ===
; P=pawn N=knight B=bishop R=rook Q=queen K=king
piece_chars:    db 'P', 'N', 'B', 'R', 'Q', 'K'

title_str:      db "MELLIVORA CHESS", 0
str_white_move: db "WHITE TO MOVE", 0
str_black_move: db "BLACK TO MOVE", 0
str_input:      db "MOVE:", 0
str_invalid:    db "INVALID FORMAT", 0
str_illegal:    db "ILLEGAL MOVE", 0
str_hint:       db "TYPE E2E4 FORMAT  N=NEW  ESC=QUIT", 0

; === BSS ===
board:          times 64 db 0
turn:           db 0
move_count:     dd 0
from_col:       dd 0
from_row:       dd 0
to_col:         dd 0
to_row:         dd 0
input_len:      db 0
input_err:      db 0
input_buf:      times 8 db 0
